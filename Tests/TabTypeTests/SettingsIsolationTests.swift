import AppKit
import SwiftUI
import TabTypeKit
import XCTest
@testable import TabType

/// Exercise the real Settings view graph, including constructors and getters
/// that used to import writing, create keys, probe iCloud, or create model roots.
@MainActor
final class SettingsIsolationTests: XCTestCase {
    func testReopeningSettingsLeavesSyntheticStoresUntouched() throws {
        guard let testHome = ProcessInfo.processInfo.environment["KEYWEAVE_TEST_HOME"],
              let token = ProcessInfo.processInfo.environment["KEYWEAVE_TEST_TOKEN"] else {
            throw XCTSkip("Run Scripts/test.sh to create an owned disposable Settings fixture")
        }
        let home = try validatedFixtureHome(testHome, token: token)
        let paths = AppPaths(homeDirectory: home)
        let fm = FileManager.default
        let roots = fixtureRoots(home: home)
        for root in roots {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for name in ["history.key", "writing.enc", "typing-history.enc", "import-writing.jsonl"] {
                try Data("synthetic sentinel: \(name)".utf8).write(to: root.appendingPathComponent(name), options: .withoutOverwriting)
            }
        }
        var adversarial = AppOverride()
        adversarial.readConversation = true
        adversarial.learnFromWriting = true
        AppSettings.shared.appOverrides = ["com.example.synthetic": adversarial]
        defer { AppSettings.shared.appOverrides = [:] }
        let before = try snapshot(home)
        _ = NSApplication.shared
        let delegate = AppDelegate()
        var firstWindow: NSWindow?
        let sections: [SettingsView.Section] = [.setup, .general, .engine, .context, .personalization, .about]
        for _ in 0..<2 {
            for section in sections {
                SettingsNavigator.shared.pendingSection = section
                delegate.openSettings()
                let window = try XCTUnwrap(delegate.settingsWindow)
                if let firstWindow { XCTAssertTrue(window === firstWindow, "Reopening must exercise the cached window path") }
                else { firstWindow = window }
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.04))
                XCTAssertTrue(window.isVisible)
                window.close()
            }
        }

        XCTAssertEqual(try snapshot(home), before, "Reopening Settings must not create keys/models, consume imports, migrate writing or touch upstream stores")
        XCTAssertFalse(AppSettings.shared.collectTypingHistory)
        XCTAssertFalse(AppSettings.shared.useScreenContext)
        XCTAssertFalse(AppSettings.shared.useClipboardContext)
        XCTAssertFalse(AppSettings.shared.useScreenshotAppearance)
        XCTAssertFalse(SyncManager.shared.enabled)
        XCTAssertFalse(SyncManager.shared.hasPassphrase)
        XCTAssertNil(SyncManager.shared.folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.modelsDirectory.path))
    }

    func testFixtureValidationRejectsUnownedExistingAndEscapingPaths() throws {
        XCTAssertThrowsError(try validatedFixtureHome("/", token: "unowned"))
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("keyweave-gate0-tests-\(UUID())")
        let outside = fm.temporaryDirectory.appendingPathComponent("keyweave-gate0-outside-\(UUID())")
        defer { try? fm.removeItem(at: home); try? fm.removeItem(at: outside) }
        try fm.createDirectory(at: home, withIntermediateDirectories: false)
        try Data("owned".utf8).write(to: home.appendingPathComponent(".keyweave-test-home"), options: .withoutOverwriting)
        let preexisting = home.appendingPathComponent("Library/Application Support/TabType")
        try fm.createDirectory(at: preexisting, withIntermediateDirectories: true)
        let sentinel = preexisting.appendingPathComponent("history.key")
        let payload = Data("never overwrite this existing key".utf8)
        try payload.write(to: sentinel)
        XCTAssertThrowsError(try validatedFixtureHome(home.path, token: "owned"))
        XCTAssertEqual(try Data(contentsOf: sentinel), payload)
        try fm.removeItem(at: home.appendingPathComponent("Library"))
        try fm.createDirectory(at: outside, withIntermediateDirectories: false)
        try fm.createSymbolicLink(at: home.appendingPathComponent("Library"), withDestinationURL: outside)
        XCTAssertThrowsError(try validatedFixtureHome(home.path, token: "owned"))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: outside.path), [])
    }

    func testPersistedDirectAndSyncedAppOverridesCannotEnableContextOrWriting() throws {
        let domain = "dev.anuhas.keyweave.tests.overrides.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain); AppPolicyStore.userOverrides = [:] }
        var override = AppOverride()
        override.readConversation = true
        override.learnFromWriting = true
        let overrides = ["com.example.synthetic": override]
        defaults.set(try JSONEncoder().encode(overrides), forKey: "appOverrides")
        let before = defaults.persistentDomain(forName: domain)! as NSDictionary
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, before)
        let engine = Engine(settings: settings)
        func assertDenied() {
            let policy = AppPolicyStore.policy(forBundleId: "com.example.synthetic")
            XCTAssertFalse(engine.learnsFromWriting("com.example.synthetic"))
            XCTAssertFalse(engine.usesScreenContext(for: policy))
        }
        assertDenied()
        settings.appOverrides = overrides
        assertDenied()
        var snapshot = settings.syncSnapshot
        snapshot.appOverrides = overrides
        settings.apply(snapshot)
        assertDenied()
    }

    private enum UnsafeFixture: Error { case unowned, existing, escaping }

    private func fixtureRoots(home: URL) -> [URL] {
        [AppPaths(homeDirectory: home).supportDirectory,
         home.appendingPathComponent("Library/Application Support/TabType"),
         home.appendingPathComponent("Library/Application Support/app.cotypist.Cotypist"),
         home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/TabType Sync")]
    }

    /// Never trust an arbitrary absolute environment path as writable test data.
    private func validatedFixtureHome(_ path: String, token: String) throws -> URL {
        guard path.hasPrefix("/"), !token.isEmpty else { throw UnsafeFixture.unowned }
        let home = URL(fileURLWithPath: path, isDirectory: true)
        let canonical = home.resolvingSymlinksInPath().standardizedFileURL
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.deletingLastPathComponent().path == temporary.path,
              canonical.lastPathComponent.hasPrefix("keyweave-gate0-tests-"),
              try String(contentsOf: home.appendingPathComponent(".keyweave-test-home"), encoding: .utf8) == token
        else { throw UnsafeFixture.unowned }
        for root in fixtureRoots(home: home) {
            var ancestor = home
            for component in root.path.dropFirst(home.path.count).split(separator: "/") {
                ancestor.appendPathComponent(String(component))
                if (try? ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw UnsafeFixture.escaping
                }
            }
            guard root.resolvingSymlinksInPath().path.hasPrefix(canonical.path + "/") else { throw UnsafeFixture.escaping }
            guard !FileManager.default.fileExists(atPath: root.path) else { throw UnsafeFixture.existing }
        }
        return home
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            result[String(url.path.dropFirst(root.path.count))] = try Data(contentsOf: url)
        }
        return result
    }
}
