import Combine
import Foundation
import TabTypeKit
import XCTest
@testable import TabType

@MainActor
final class LocalCompletionIntegrationTests: XCTestCase {
    func testInstalledCatalogModelStartsAndCompletesSyntheticWriting() async throws {
        guard let path = ProcessInfo.processInfo.environment["KEYWEAVE_TEST_MODEL"], path.hasPrefix("/") else {
            throw XCTSkip("Opt in with KEYWEAVE_TEST_MODEL pointing to a verified model outside git")
        }
        let source = URL(fileURLWithPath: path)
        let catalog = try ModelCatalog.bundled()
        let entry = try XCTUnwrap(catalog.models.first { $0.fileName == source.lastPathComponent })
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "dev.anuhas.keyweave.tests.local-completion.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: home)
        }
        let store = ModelStore(paths: AppPaths(homeDirectory: home))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        // A hard link preserves the catalog's exact file-size check without
        // duplicating or modifying the approved external fixture.
        try FileManager.default.linkItem(at: source, to: store.url(for: entry))
        defaults.set(entry.id, forKey: "llamaModelID")
        let models = LlamaModelManager(defaults: defaults, store: store)
        let loaded = expectation(description: "installed local model finishes startup")
        let observation = models.$status.sink { status in
            switch status {
            case .ready, .failed: loaded.fulfill()
            default: break
            }
        }
        models.start()
        let outcome = await XCTWaiter.fulfillment(of: [loaded], timeout: 30)
        observation.cancel()
        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(models.status, .ready(id: entry.id))
        let engine = LlamaEngine(models: models)
        let completion = await engine.complete(.init(
            beforeCursor: "The capital of France is", afterCursor: "", screenContext: "", maxWords: 3))
        XCTAssertNotNil(engine.lastResult)
        let clipboardConsent = AppSettings.shared.useClipboardContext
        AppSettings.shared.useClipboardContext.toggle()
        XCTAssertNil(engine.lastResult, "A previous context result must become unavailable immediately when consent changes")
        AppSettings.shared.useClipboardContext = clipboardConsent
        await models.shutdown()
        XCTAssertNotNil(completion)
        XCTAssertTrue(completion?.contains("Paris") == true, "The real application completion path should continue the synthetic sentence: \(completion ?? "<none>")")
    }
}
