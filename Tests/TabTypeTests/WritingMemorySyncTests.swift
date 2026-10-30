import CryptoKit
import Foundation
import TabTypeKit
import XCTest
@testable import TabType

@MainActor
final class WritingMemorySyncTests: XCTestCase {
    func testLearnedContinuationDisappearsImmediatelyOnOptOutAndErase() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeyWeave-learning-hint-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var optedIn = true
        let store = WritingStore(directory: root, collectionEnabled: { optedIn })
        store.record("Synthetic meadow messages end with a silver maple greeting.",
                     bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
        let index = PersonalIndex(store: store, collectionEnabled: { optedIn })
        defer { index.stop() }
        index.start()
        for _ in 0..<100 {
            if index.hint(after: "Synthetic meadow messages") != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(try XCTUnwrap(index.hint(after: "Synthetic meadow messages")).text.hasPrefix(" end with"))
        let saved = try Data(contentsOf: root.appendingPathComponent("writing.enc"))
        optedIn = false
        XCTAssertNil(index.hint(after: "Synthetic meadow messages"))
        store.stopCollection()
        index.stop()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("writing.enc")), saved)
        optedIn = true
        store.start()
        index.start()
        store.eraseAll()
        XCTAssertNil(index.hint(after: "Synthetic meadow messages"))
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(index.hint(after: "Synthetic meadow messages"))
    }

    func testNewWritingFilesAndDirectoryArePrivate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeyWeave-private-writing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WritingStore(directory: root, collectionEnabled: { true })
        store.record("Synthetic newly created writing must use private local files.",
                     bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
        let manager = FileManager.default
        XCTAssertEqual((try manager.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        for name in ["history.key", "writing.enc"] {
            XCTAssertEqual((try manager.attributesOfItem(atPath: root.appendingPathComponent(name).path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testDisabledSyncGettersAndDirectMethodsNeverReachKeychainOrCloud() throws {
        let name = "dev.anuhas.keyweave.test.memory-sync.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "syncEnabled")
        defaults.set("Synthetic author", forKey: "authorName")
        let before = try XCTUnwrap(defaults.persistentDomain(forName: name)) as NSDictionary
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("KeyWeave-disabled-sync-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        var keyReads = 0
        var keyWrites = 0
        var cloudReads = 0
        let boundary = SyncSystemBoundary(
            readPassphrase: { _ in keyReads += 1; return nil },
            storePassphrase: { _, _ in keyWrites += 1 },
            cloudDriveExists: { _ in cloudReads += 1; return true })
        let manager = SyncManager(defaults: defaults, settings: AppSettings(defaults: defaults),
                                  paths: AppPaths(homeDirectory: home), system: boundary)
        for _ in 0..<2 {
            XCTAssertFalse(manager.enabled)
            XCTAssertFalse(manager.hasPassphrase)
            XCTAssertNil(manager.folder)
            manager.start()
            manager.syncNow()
            manager.setPassphrase("Synthetic passphrase only")
            manager.stop()
        }
        XCTAssertEqual(keyReads, 0)
        XCTAssertEqual(keyWrites, 0)
        XCTAssertEqual(cloudReads, 0)
        XCTAssertEqual(defaults.persistentDomain(forName: name) as NSDictionary?, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }

    func testEraseWhileOptedOutSurvivesRestartAndRejectsStaleWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeyWeave-erased-writing-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        var optedIn = true
        let store = WritingStore(directory: root, collectionEnabled: { optedIn })
        store.record("Synthetic old writing must not return after an explicit erase.",
                     bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
        let stale = store.allDocuments
        XCTAssertEqual(stale.count, 1)
        optedIn = false
        store.stopCollection()
        store.eraseAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("writing.enc").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("history.key").path))
        optedIn = true
        let reopened = WritingStore(directory: root, collectionEnabled: { optedIn })
        reopened.start()
        reopened.merge(stale)
        XCTAssertTrue(reopened.texts.isEmpty)
        reopened.record("Synthetic new writing is allowed after the deletion has been observed.",
                        bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
        XCTAssertEqual(reopened.documentCount, 1)
    }

    func testUnreadableStoresRemainUnchangedAndReportRecoveryError() throws {
        for malformedKey in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeyWeave-invalid-writing-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let key = malformedKey ? Data("synthetic malformed key".utf8) : Data(repeating: 7, count: 32)
            let encrypted = Data("synthetic corrupt encrypted writing must survive".utf8)
            try key.write(to: root.appendingPathComponent("history.key"))
            try encrypted.write(to: root.appendingPathComponent("writing.enc"))
            let store = WritingStore(directory: root, collectionEnabled: { true })
            store.start()
            store.record("New synthetic text must not replace an unreadable archive.",
                         bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("history.key")), key)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("writing.enc")), encrypted)
            XCTAssertFalse(store.status.isEmpty)
            XCTAssertTrue(store.texts.isEmpty)
        }
    }

    func testOptedInWritingSurvivesRestartEncryptedAndNeverConsumesImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeyWeave-writing-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = Data("{\"text\":\"Synthetic import must never be consumed.\"}\n".utf8)
        try pending.write(to: root.appendingPathComponent("import-writing.jsonl"))
        let phrase = "Synthetic garden notes finish with the silver maple greeting."
        let store = WritingStore(directory: root, collectionEnabled: { true })
        XCTAssertTrue(store.texts.isEmpty)
        store.start()
        store.record(phrase, bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
        XCTAssertEqual(store.texts, [phrase])
        let encrypted = try Data(contentsOf: root.appendingPathComponent("writing.enc"))
        XCTAssertNil(encrypted.range(of: Data(phrase.utf8)))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("history.key")).count, 32)
        let reopened = WritingStore(directory: root, collectionEnabled: { true })
        XCTAssertTrue(reopened.texts.isEmpty)
        reopened.start()
        XCTAssertEqual(reopened.texts, [phrase])
        reopened.importPendingFile()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("import-writing.jsonl")), pending)
    }
}
