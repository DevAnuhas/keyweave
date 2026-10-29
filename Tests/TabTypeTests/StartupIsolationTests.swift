import Foundation
import XCTest
import TabTypeKit
@testable import TabType

private final class StartupNetworkProbe: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests = 0
    static func reset() { lock.withLock { requests = 0 } }
    static var requestCount: Int { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.requests += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

private final class PlatformOperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    func record(_ operation: String) { lock.withLock { recorded.append(operation) } }
    var operations: [String] { lock.withLock { recorded } }
}

final class StartupIsolationTests: XCTestCase {
    @MainActor
    func testDirectUpdateCheckCannotUseNetworkOrPersistPreferences() async throws {
        let suite = "dev.anuhas.keyweave.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "checkForUpdates")
        defaults.set("sentinel", forKey: "unrelated")
        let before = defaults.persistentDomain(forName: suite)! as NSDictionary
        StartupNetworkProbe.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StartupNetworkProbe.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let updater = Updater(defaults: defaults, session: session)

        updater.automatic = true
        updater.checkIfDue()
        updater.install(.init(version: "99", page: URL(string: "https://update.invalid/release")!,
                              dmg: URL(string: "https://update.invalid/app.dmg")!, sha256: nil))
        await updater.check()

        XCTAssertFalse(updater.automatic, "Persisted or direct enablement cannot enable updates in Gate0")
        XCTAssertEqual(updater.state, .idle)
        XCTAssertEqual(StartupNetworkProbe.requestCount, 0)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)! as NSDictionary, before)
    }

    @MainActor
    func testGate0ScreenAPIsNeverReachPermissionTitleOrCaptureOperations() async {
        let recorder = PlatformOperationRecorder()
        let provider = ScreenContextProvider(platform: .init(
            preflightPermission: { recorder.record("preflight"); return false },
            requestPermission: { recorder.record("request"); return true },
            focusedWindowTitle: { recorder.record("title"); return "Synthetic chat" }))
        provider.onFreshContext = { _ in recorder.record("fresh context") }

        XCTAssertFalse(provider.hasPermission())
        XCTAssertFalse(provider.requestPermission())
        provider.refreshIfStale()
        provider.selfTest()
        XCTAssertEqual(provider.contextText(for: "synthetic.chat", cap: 64), "")
        XCTAssertEqual(provider.contextText(for: "synthetic.chat", cap: 64, windowTitle: nil), "")
        let capture = await ScreenContextProvider.captureFocusedWindow(
            pid: nil, fieldText: "", cropMode: .caretCropped, caretRect: nil, windowFrame: nil,
            capture: { recorder.record("capture"); return ("Chat", "synthetic.chat", "Private synthetic context") })

        XCTAssertNil(capture)
        XCTAssertEqual(recorder.operations, [], "Gate0 must return before any platform access, even for direct capture")
        XCTAssertFalse(provider.isCapturing)
        XCTAssertTrue(provider.history.isEmpty)
    }

    @MainActor
    func testModelConstructionGettersAndRepeatedStartNeverCreateLoadOrResume() async throws {
        let bundled = try ModelCatalog.bundled()
        let entry = try XCTUnwrap(bundled.models.first)
        for fixture in ["absent", "partial", "installed"] {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: home) }
            let paths = AppPaths(homeDirectory: home)
            let store = ModelStore(paths: paths)
            let suite = "dev.anuhas.keyweave.tests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let selected = fixture == "installed" ? "custom:synthetic.gguf" : entry.id
            defaults.set(selected, forKey: "llamaModelID")
            defaults.set("sentinel", forKey: "unrelated")
            if fixture != "absent" {
                try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
                let file = fixture == "partial"
                    ? store.url(for: entry).appendingPathExtension("part")
                    : store.directory.appendingPathComponent("synthetic.gguf")
                try Data("synthetic model bytes, never for native inference".utf8).write(to: file)
            }
            let filesBefore = try snapshot(home)
            let preferencesBefore = defaults.persistentDomain(forName: suite)! as NSDictionary
            let models = LlamaModelManager(defaults: defaults, store: store, ramGB: 64)

            XCTAssertEqual(models.catalog, bundled)
            _ = models.entries
            _ = models.entry(id: selected)
            _ = models.fit(entry)
            XCTAssertEqual(models.isInstalled(selected), fixture == "installed", fixture)
            XCTAssertFalse(models.isInstalled("custom:missing.gguf"))
            models.start()
            models.start()

            XCTAssertEqual(models.status, .noModel, fixture)
            XCTAssertNil(models.loadedID, fixture)
            let inferenceState = await models.inference.state
            XCTAssertEqual(inferenceState, .unloaded, fixture)
            XCTAssertEqual(try snapshot(home), filesBefore, fixture)
            XCTAssertEqual(defaults.persistentDomain(forName: suite)! as NSDictionary, preferencesBefore, fixture)
        }
    }

    @MainActor
    func testAutomaticStartupCannotStartInputMonitoringEvenWithExistingTrust() {
        for trusted in [false, true] {
            let recorder = PlatformOperationRecorder()
            AppDelegate.startEngineIfTrusted(operations: .init(
                accessibilityTrusted: { recorder.record("trust"); return trusted },
                startEngine: { recorder.record("engine") }))
            XCTAssertTrue(recorder.operations.isEmpty)
        }
    }

    @MainActor
    func testDirectEngineStartCannotEnableInputMonitoring() throws {
        let suite = "dev.anuhas.keyweave.tests.input.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = Engine(settings: AppSettings(defaults: defaults))
        XCTAssertFalse(engine.start())
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return [:]
        }
        var result: [String: Data] = [:]
        for case let file as URL in files {
            let regular = try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            result[String(file.path.dropFirst(root.path.count))] = regular ? try Data(contentsOf: file) : Data()
        }
        return result
    }
}
