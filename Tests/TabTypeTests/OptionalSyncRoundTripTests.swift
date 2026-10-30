import Foundation
import TabTypeKit
import XCTest
@testable import TabType

@MainActor
final class OptionalSyncRoundTripTests: XCTestCase {
    func testOfflineLocalSettingsSurviveReenableAndRelaunch() throws {
        for relaunch in [false, true] {
            let root = try fixtureRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let first = try SyntheticMac(home: root.appendingPathComponent("first"))
            let second = try SyntheticMac(home: root.appendingPathComponent("second"))
            defer { first.close(); second.close() }
            first.settings.customInstructions = "Synthetic original shared settings."
            first.manager.enabled = true
            try first.deliverCloudFiles(to: second)
            second.manager.enabled = true
            XCTAssertEqual(second.settings.customInstructions, first.settings.customInstructions)

            first.manager.enabled = false
            second.settings.customInstructions = "Synthetic remote edit T2."
            second.manager.syncNow()
            try second.deliverCloudFiles(to: first)
            first.settings.customInstructions = "Synthetic newer local edit T3."

            if relaunch {
                let restoredSettings = AppSettings(defaults: first.defaults)
                let restoredStore = WritingStore(directory: first.paths.supportDirectory,
                                                 collectionEnabled: { restoredSettings.collectTypingHistory })
                let restored = SyncManager(defaults: first.defaults, settings: restoredSettings,
                                           paths: first.paths, system: first.boundary, writingStore: restoredStore)
                defer { restored.stop() }
                restored.enabled = true
                XCTAssertEqual(restoredSettings.customInstructions, "Synthetic newer local edit T3.")
            } else {
                first.manager.enabled = true
                XCTAssertEqual(first.settings.customInstructions, "Synthetic newer local edit T3.")
            }
            try first.deliverCloudFiles(to: second)
            second.manager.syncNow()
            XCTAssertEqual(second.settings.customInstructions, "Synthetic newer local edit T3.")
        }
    }

    func testUnreadableLocalWritingDoesNotReplaceValidPublishedCiphertext() throws {
        for corruptKey in [false, true] {
            let root = try fixtureRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let mac = try SyntheticMac(home: root.appendingPathComponent("first"))
            defer { mac.close() }
            mac.store.record("Synthetic archived writing must remain in its valid encrypted cloud file.",
                             bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
            mac.manager.enabled = true
            let published = try XCTUnwrap(try cloudNames(mac).first)
            let publishedURL = mac.paths.syncDirectory.appendingPathComponent(published)
            let before = try Data(contentsOf: publishedURL)
            mac.manager.stop()
            let brokenURL = mac.paths.supportDirectory.appendingPathComponent(corruptKey ? "history.key" : "writing.enc")
            let broken = Data("Synthetic unreadable local file must be preserved.".utf8)
            try broken.write(to: brokenURL)
            let reopenedStore = WritingStore(directory: mac.paths.supportDirectory,
                                             collectionEnabled: { mac.settings.collectTypingHistory })
            let reopened = SyncManager(defaults: mac.defaults, settings: mac.settings, paths: mac.paths,
                                       system: mac.boundary, writingStore: reopenedStore)
            defer { reopened.stop() }
            reopened.syncNow()
            XCTAssertEqual(try Data(contentsOf: publishedURL), before)
            XCTAssertEqual(try Data(contentsOf: brokenURL), broken)
            XCTAssertFalse(reopenedStore.status.isEmpty)
            XCTAssertTrue(reopened.status.contains("Sync failed"))
        }
    }

    func testKeychainSaveFailureKeepsExistingPassphraseAndReportsError() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let mac = try SyntheticMac(home: root.appendingPathComponent("first"))
        defer { mac.close() }
        mac.manager.enabled = true
        let previous = mac.passphrase
        mac.keychainWriteFailure = true
        mac.manager.setPassphrase("Synthetic replacement passphrase only")
        XCTAssertEqual(mac.passphrase, previous)
        XCTAssertTrue(mac.manager.status.contains("Keychain"))
    }

    func testLearningOffDoesNotImportWritingOrCreateLocalKey() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try SyntheticMac(home: root.appendingPathComponent("first"))
        let second = try SyntheticMac(home: root.appendingPathComponent("second"), learning: false)
        defer { first.close(); second.close() }
        first.store.record("Synthetic private writing is not imported without local learning consent.",
                           bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
        first.manager.enabled = true
        try first.deliverCloudFiles(to: second)
        second.manager.enabled = true
        XCTAssertFalse(second.settings.collectTypingHistory)
        XCTAssertTrue(second.store.texts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.paths.supportDirectory.path))
    }

    func testWrongPassphraseDoesNotImportOrModifyAnotherMacFile() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try SyntheticMac(home: root.appendingPathComponent("first"))
        let second = try SyntheticMac(home: root.appendingPathComponent("second"))
        defer { first.close(); second.close() }
        first.store.record("Synthetic writing encrypted with the first passphrase remains private.",
                           bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
        first.manager.enabled = true
        let file = try XCTUnwrap(try cloudNames(first).first)
        let before = try Data(contentsOf: first.paths.syncDirectory.appendingPathComponent(file))
        try first.deliverCloudFiles(to: second)
        second.passphrase = "Synthetic wrong passphrase only"
        second.manager.enabled = true
        XCTAssertTrue(second.store.texts.isEmpty)
        XCTAssertEqual(second.manager.otherMacs, 0)
        XCTAssertTrue(second.manager.status.contains("different passphrase"))
        XCTAssertEqual(try Data(contentsOf: second.paths.syncDirectory.appendingPathComponent(file)), before)
    }

    func testMachineOnlyStateDoesNotOverrideNewerSharedSettings() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try SyntheticMac(home: root.appendingPathComponent("first"))
        let second = try SyntheticMac(home: root.appendingPathComponent("second"))
        defer { first.close(); second.close() }
        first.settings.customInstructions = "Synthetic first revision."
        first.manager.enabled = true
        try first.deliverCloudFiles(to: second)
        second.manager.enabled = true
        first.settings.customInstructions = "Synthetic second revision."
        first.manager.syncNow()
        second.settings.inputMonitoringState = .active
        try first.deliverCloudFiles(to: second)
        second.manager.syncNow()
        XCTAssertEqual(second.settings.customInstructions, "Synthetic second revision.")
    }

    func testTwoSyntheticMacsExchangeEncryptedWritingAndSettings() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try SyntheticMac(home: root.appendingPathComponent("first"))
        let second = try SyntheticMac(home: root.appendingPathComponent("second"))
        defer { first.close(); second.close() }
        let phrase = "Synthetic meadow messages end with a silver maple greeting."
        first.store.record(phrase, bundleId: "test.synthetic.writer", fieldKey: "draft", kind: .field)
        first.settings.customInstructions = "Use synthetic meadow examples."
        first.manager.enabled = true
        try first.deliverCloudFiles(to: second)
        second.manager.enabled = true
        XCTAssertEqual(second.store.texts, [phrase])
        XCTAssertEqual(second.settings.customInstructions, "Use synthetic meadow examples.")
        XCTAssertEqual(second.manager.otherMacs, 1)
        let files = try FileManager.default.contentsOfDirectory(at: first.paths.syncDirectory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == ProductIdentity.syncFileExtension {
            XCTAssertNil(try Data(contentsOf: file).range(of: Data(phrase.utf8)))
        }
        XCTAssertTrue(first.keychainServices.allSatisfy { $0 == ProductIdentity.keychainService })
        XCTAssertTrue(second.keychainServices.allSatisfy { $0 == ProductIdentity.keychainService })
    }

    func testErasePropagatesAndStaleFutureDatedPayloadCannotResurrectAfterRestart() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try SyntheticMac(home: root.appendingPathComponent("first"))
        let second = try SyntheticMac(home: root.appendingPathComponent("second"))
        defer { first.close(); second.close() }
        second.store.merge([WritingStore.Document(
            key: "synthetic-future-draft", bundleId: "test.synthetic.writer",
            text: "Synthetic stale future-dated writing must not return after erase.",
            updated: Date().addingTimeInterval(86_400))])
        first.manager.enabled = true
        let firstFiles = try cloudNames(first)
        try first.deliverCloudFiles(to: second)
        second.manager.enabled = true
        let secondOwnFiles = try cloudNames(second).subtracting(firstFiles)
        let secondOwnFile = try XCTUnwrap(secondOwnFiles.first)
        let stale = try Data(contentsOf: second.paths.syncDirectory.appendingPathComponent(secondOwnFile))
        try second.deliverCloudFiles(to: first)
        first.manager.syncNow()
        XCTAssertEqual(first.store.documentCount, 1)

        first.settings.collectTypingHistory = false
        first.store.stopCollection()
        first.store.eraseAll()
        first.manager.syncNow()
        try first.deliverCloudFiles(to: second)
        second.manager.syncNow()
        XCTAssertTrue(second.store.texts.isEmpty)

        first.manager.stop()
        let reopenedStore = WritingStore(directory: first.paths.supportDirectory,
                                         collectionEnabled: { first.settings.collectTypingHistory })
        let reopened = SyncManager(defaults: first.defaults, settings: first.settings, paths: first.paths,
                                   system: first.boundary, writingStore: reopenedStore)
        defer { reopened.stop() }
        try stale.write(to: first.paths.syncDirectory.appendingPathComponent(secondOwnFile), options: .atomic)
        reopened.syncNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.paths.supportDirectory.appendingPathComponent("history.key").path))
        first.settings.collectTypingHistory = true
        reopenedStore.start()
        reopened.syncNow()
        XCTAssertTrue(reopenedStore.texts.isEmpty)

        let fresh = "Synthetic new writing is welcome after the erase is acknowledged."
        second.store.record(fresh, bundleId: "test.synthetic.writer", fieldKey: "new-draft", kind: .field)
        second.manager.syncNow()
        try second.deliverCloudFiles(to: first)
        reopened.syncNow()
        XCTAssertEqual(reopenedStore.texts, [fresh])
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeyWeave-synthetic-Macs-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return root
    }

    private func cloudNames(_ mac: SyntheticMac) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: mac.paths.syncDirectory.path)
            .filter { $0.hasSuffix("." + ProductIdentity.syncFileExtension) })
    }
}

/// Two independent homes, suites and fake Keychains. Copying only the encrypted
/// cloud-folder files simulates a file provider; this is not a real iCloud test.
@MainActor
private final class SyntheticMac {
    let domain = "dev.anuhas.keyweave.test.synthetic-Mac.\(UUID())"
    let defaults: UserDefaults
    let settings: AppSettings
    let paths: AppPaths
    let store: WritingStore
    var passphrase: String? = "Synthetic test passphrase only"
    var keychainWriteFailure = false
    var keychainServices: [String] = []
    lazy var boundary = SyncSystemBoundary(
        readPassphrase: { [unowned self] service in
            self.keychainServices.append(service)
            return self.passphrase
        },
        storePassphrase: { [unowned self] service, value in
            self.keychainServices.append(service)
            if self.keychainWriteFailure { throw CocoaError(.fileWriteNoPermission) }
            self.passphrase = value
        },
        cloudDriveExists: { [unowned self] drive in
            drive == self.paths.syncDirectory.deletingLastPathComponent()
        })
    lazy var manager = SyncManager(defaults: defaults, settings: settings, paths: paths,
                                   system: boundary, writingStore: store)

    init(home: URL, learning: Bool = true) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defaults.set("Synthetic author", forKey: "authorName")
        settings = AppSettings(defaults: defaults)
        settings.collectTypingHistory = learning
        paths = AppPaths(homeDirectory: home)
        let settings = self.settings
        store = WritingStore(directory: paths.supportDirectory, collectionEnabled: { settings.collectTypingHistory })
        try FileManager.default.createDirectory(at: paths.syncDirectory.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
    }

    func deliverCloudFiles(to other: SyntheticMac) throws {
        try FileManager.default.createDirectory(at: other.paths.syncDirectory, withIntermediateDirectories: true)
        for file in try FileManager.default.contentsOfDirectory(at: paths.syncDirectory, includingPropertiesForKeys: nil)
        where file.lastPathComponent == "salt" || file.pathExtension == ProductIdentity.syncFileExtension {
            try Data(contentsOf: file).write(to: other.paths.syncDirectory.appendingPathComponent(file.lastPathComponent), options: .atomic)
        }
    }

    func close() {
        manager.stop()
        defaults.removePersistentDomain(forName: domain)
    }
}
