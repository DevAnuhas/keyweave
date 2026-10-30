import Foundation
import TabTypeKit
import XCTest
@testable import TabType

@MainActor
final class PassiveStorageIsolationTests: XCTestCase {
    func testPreferencesReadOnlyTheirExplicitSyntheticDomain() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("Keyweave-Gate0-preferences-\(UUID())")
        let environment = ["KEYWEAVE_TEST_HOME": home.path]
        let domain = AppPreferences.domain(environment: environment)
        let defaults = AppPreferences.makeCurrent(environment: environment)
        let fallbackDomain = "dev.anuhas.keyweave.test.fallback.\(UUID())"
        let fallback = try XCTUnwrap(UserDefaults(suiteName: fallbackDomain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            fallback.removePersistentDomain(forName: fallbackDomain)
        }
        fallback.set("synthetic upstream preference", forKey: "text")
        fallback.set(true, forKey: "flag")
        fallback.set(37, forKey: "number")
        fallback.set(["synthetic"], forKey: "list")
        fallback.set(["synthetic": "value"], forKey: "map")
        fallback.set(Data([1, 2, 3]), forKey: "bytes")
        fallback.set(home.appendingPathComponent("synthetic-file").path, forKey: "url")
        let before = try XCTUnwrap(fallback.persistentDomain(forName: fallbackDomain)) as NSDictionary
        defaults.addSuite(named: fallbackDomain)
        defaults.setVolatileDomain(["text": "synthetic argument override", "flag": true], forName: UserDefaults.argumentDomain)
        for _ in 0..<2 {
            XCTAssertNil(defaults.object(forKey: "text"))
            XCTAssertNil(defaults.string(forKey: "text"))
            XCTAssertNil(defaults.array(forKey: "list"))
            XCTAssertNil(defaults.stringArray(forKey: "list"))
            XCTAssertNil(defaults.dictionary(forKey: "map"))
            XCTAssertNil(defaults.data(forKey: "bytes"))
            XCTAssertNil(defaults.url(forKey: "url"))
            XCTAssertFalse(defaults.bool(forKey: "flag"))
            XCTAssertEqual(defaults.integer(forKey: "number"), 0)
            XCTAssertEqual(defaults.float(forKey: "number"), 0)
            XCTAssertEqual(defaults.double(forKey: "number"), 0)
            XCTAssertTrue(defaults.dictionaryRepresentation().isEmpty)
        }
        defaults.set("Keyweave synthetic preference", forKey: "text")
        XCTAssertEqual(defaults.string(forKey: "text"), "Keyweave synthetic preference")
        XCTAssertEqual(fallback.persistentDomain(forName: fallbackDomain) as NSDictionary?, before)
        XCTAssertTrue(domain.hasPrefix("dev.anuhas.keyweave.test."))
        XCTAssertEqual(AppPreferences.domain(environment: ["KEYWEAVE_TEST_HOME": home.path + "/."]), domain)
        XCTAssertNotEqual(AppPreferences.domain(environment: ["KEYWEAVE_TEST_HOME": home.appendingPathComponent("other").path]), domain)
        XCTAssertEqual(AppPreferences.domain(environment: [:]), "dev.anuhas.keyweave")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }

    func testSettingsServicesStayPassiveBeforeCaptureAndLoginBoundaries() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("Keyweave-Gate0-services-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = AppPaths(homeDirectory: home)
        let upstreamLogs = home.appendingPathComponent("Library/Logs/TabType")
        let oldLog = Data("synthetic upstream log sentinel".utf8)
        let oversizedLog = Data(repeating: 65, count: Int(Log.maxBytes) + 1)
        for directory in [upstreamLogs, paths.logsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try oldLog.write(to: upstreamLogs.appendingPathComponent("tabtype.log"))
        try oversizedLog.write(to: paths.logsDirectory.appendingPathComponent("keyweave.log"))
        let domain = "dev.anuhas.keyweave.test.services.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(7, forKey: "stat_suggestionsShown")
        defaults.set(["synthetic-emoji"], forKey: "emojiRecents")
        let before = try XCTUnwrap(defaults.persistentDomain(forName: domain)) as NSDictionary

        var permissionReads = 0
        var loginReads = 0
        var loginWrites = 0
        let login = LaunchAtLogin.SystemBoundary(
            isEnabled: { loginReads += 1; return true },
            setEnabled: { _ in loginWrites += 1 })
        let cache = FieldFitCache(paths: paths,
                                  screenCaptureAllowed: { permissionReads += 1; return false },
                                  appearanceEnabled: { false })
        XCTAssertEqual(loginReads, 0)
        XCTAssertEqual(loginWrites, 0)
        for _ in 0..<2 {
            _ = Log(directory: paths.logsDirectory)
            _ = Log(directory: home.appendingPathComponent("uncreated-log"))
            let statistics = Statistics(defaults: defaults)
            XCTAssertEqual(statistics.suggestionsShown, 7)
            XCTAssertEqual(statistics.wordsCompleted, 0)
            XCTAssertNil(statistics.latencyPercentiles)
            XCTAssertEqual(EmojiUsageStore(defaults: defaults).recentCodes, ["synthetic-emoji"])
            XCTAssertTrue(LaunchAtLogin.isEnabled(using: login))
            XCTAssertNil(cache.cached(key: "synthetic"))
            let fit = await cache.fit(caret: CGRect(x: 100, y: 100, width: 1, height: 20), fieldFrame: nil,
                                      key: "synthetic", lineText: "Synthetic text only", verbose: true)
            XCTAssertNil(fit)
        }
        XCTAssertEqual(permissionReads, 0)
        XCTAssertEqual(loginReads, 2)
        XCTAssertEqual(loginWrites, 0)
        XCTAssertEqual(defaults.persistentDomain(forName: domain) as NSDictionary?, before)
        XCTAssertEqual(try Data(contentsOf: upstreamLogs.appendingPathComponent("tabtype.log")), oldLog)
        XCTAssertEqual(try Data(contentsOf: paths.logsDirectory.appendingPathComponent("keyweave.log")), oversizedLog)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.logsDirectory.path), ["keyweave.log"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("uncreated-log").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.fitCapturesDirectory.path))
    }

    func testSettingsConstructionPreservesStoredPreferences() throws {
        let domain = "dev.anuhas.keyweave.test.settings.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(0.123, forKey: "temperature") // Retired keys are not cleaned up implicitly.
        defaults.set("Synthetic author", forKey: "authorName")
        defaults.set(try JSONEncoder().encode(KeyBinding.escape), forKey: "acceptWordKey")
        let before = try XCTUnwrap(defaults.persistentDomain(forName: domain)) as NSDictionary

        for _ in 0..<2 {
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.acceptWordKey, .escape)
            XCTAssertEqual(settings.authorName, "Synthetic author")
        }
        XCTAssertEqual(defaults.persistentDomain(forName: domain) as NSDictionary?, before)
    }

    func testSyncSettingsGettersAndDisabledLifecycleNeverReachSystemBoundaries() throws {
        let domain = "dev.anuhas.keyweave.test.sync.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: "syncEnabled")
        defaults.set("Synthetic author", forKey: "authorName")
        defaults.set("synthetic preference sentinel", forKey: "sentinel")
        let before = try XCTUnwrap(defaults.persistentDomain(forName: domain)) as NSDictionary
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("Keyweave-Gate0-sync-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        var keyReads = 0
        var keyWrites = 0
        var cloudReads = 0
        let system = SyncSystemBoundary(
            readPassphrase: { _ in keyReads += 1; return nil },
            storePassphrase: { _, _ in keyWrites += 1 },
            cloudDriveExists: { _ in cloudReads += 1; return false })
        let manager = SyncManager(defaults: defaults, settings: AppSettings(defaults: defaults),
                                  paths: AppPaths(homeDirectory: home), system: system)
        for _ in 0..<2 {
            XCTAssertFalse(manager.enabled)
            XCTAssertFalse(manager.hasPassphrase)
            XCTAssertNil(manager.folder)
            XCTAssertEqual(manager.status, "")
            XCTAssertEqual(manager.otherMacs, 0)
        }
        manager.start()
        manager.syncNow()
        manager.setPassphrase("synthetic passphrase, never a real credential")
        manager.stop()
        XCTAssertEqual(keyReads, 0)
        XCTAssertEqual(keyWrites, 0)
        XCTAssertEqual(cloudReads, 0)
        XCTAssertNil(defaults.object(forKey: "syncMachineID"))
        XCTAssertEqual(defaults.persistentDomain(forName: domain) as NSDictionary?, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }

    func testWritingConstructionGettersAndDisabledLifecycleLeaveSentinelsUntouched() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("Keyweave-Gate0-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let upstream = home.appendingPathComponent("Library/Application Support/TabType")
        let current = AppPaths(homeDirectory: home).supportDirectory
        let fixtures = [
            "history.key": Data("malformed key — must never be replaced".utf8),
            "writing.enc": Data("synthetic encrypted writing sentinel".utf8),
            "typing-history.enc": Data("synthetic legacy history sentinel".utf8),
            "import-writing.jsonl": Data("{\"bundleId\":\"test.synthetic\",\"text\":\"Synthetic import must remain untouched forever.\"}\n".utf8)
        ]
        for directory in [upstream, current] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, data) in fixtures { try data.write(to: directory.appendingPathComponent(name)) }
        }

        let store = WritingStore(directory: current, collectionEnabled: { false })
        var changes = 0
        store.onChange = { changes += 1 }
        store.onSyncNeeded = { changes += 1 }
        for _ in 0..<2 {
            XCTAssertEqual(store.texts, [])
            XCTAssertEqual(store.allDocuments, [])
            XCTAssertEqual(store.documentCount, 0)
            XCTAssertEqual(store.characterCount, 0)
        }
        store.start()
        store.record("Synthetic writing that must never enter an opted-out store.", bundleId: "test.synthetic", fieldKey: nil, kind: .message)
        store.merge([.init(key: "synthetic", bundleId: "test.synthetic", text: "Synthetic remote writing.", updated: .distantPast)])
        store.importPendingFile()
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(store.allDocuments, [])
        for directory in [upstream, current] {
            XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)), Set(fixtures.keys))
            for (name, data) in fixtures { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), data) }
        }
        let absent = home.appendingPathComponent("uncreated-writing")
        _ = WritingStore(directory: absent, collectionEnabled: { false }).texts
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
    }
}
