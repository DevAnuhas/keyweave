import Combine
import Foundation
import TabTypeKit
import XCTest
@testable import TabType

private actor StartupModelLoader {
    private(set) var paths: [String] = []

    func load(_ path: String) { paths.append(path) }
}

private struct InvalidStartupModel: Error, CustomStringConvertible {
    var description: String { "synthetic invalid model" }
}

@MainActor
final class ModelStartupTests: XCTestCase {
    func testMissingPartialTruncatedAndDeletedCustomSelectionsStayIdleWithoutCreatingStorage() async throws {
        let catalog = try ModelCatalog.bundled()
        let entry = try XCTUnwrap(catalog.models.first)
        for fixture in ["absent", "partial", "truncated", "deleted-custom"] {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let domain = "dev.anuhas.keyweave.tests.model-start.\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            defer {
                try? FileManager.default.removeItem(at: home)
                defaults.removePersistentDomain(forName: domain)
            }
            let store = ModelStore(paths: AppPaths(homeDirectory: home))
            let selected = fixture == "deleted-custom" ? "custom:missing.gguf" : entry.id
            defaults.set(selected, forKey: "llamaModelID")
            let before = defaults.persistentDomain(forName: domain)! as NSDictionary
            var file: URL?
            let bytes = Data("unfinished synthetic model".utf8)
            if fixture == "partial" || fixture == "truncated" {
                try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
                let destination = store.url(for: entry)
                file = fixture == "partial" ? destination.appendingPathExtension("part") : destination
                try bytes.write(to: XCTUnwrap(file))
            }
            let loader = StartupModelLoader()
            let models = LlamaModelManager(defaults: defaults, store: store, ramGB: 64,
                                          loadModel: { await loader.load($0) })

            _ = models.entries
            models.start()
            models.start()

            XCTAssertEqual(models.status, .noModel, fixture)
            XCTAssertNil(models.loadedID, fixture)
            let loadedPaths = await loader.paths
            XCTAssertEqual(loadedPaths, [], fixture)
            let inferenceState = await models.inference.state
            XCTAssertEqual(inferenceState, .unloaded, fixture)
            XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, before, fixture)
            if let file {
                XCTAssertEqual(try Data(contentsOf: file), bytes, fixture)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), [file.lastPathComponent], fixture)
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: home.path), fixture)
            }
        }
    }

    func testInvalidInstalledModelReportsLoadFailureWithoutRetryingOrDownloading() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "dev.anuhas.keyweave.tests.model-start.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            try? FileManager.default.removeItem(at: home)
            defaults.removePersistentDomain(forName: domain)
        }
        let store = ModelStore(paths: AppPaths(homeDirectory: home))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appendingPathComponent("synthetic.gguf")
        let bytes = Data("invalid synthetic model".utf8)
        try bytes.write(to: file)
        defaults.set("custom:synthetic.gguf", forKey: "llamaModelID")
        let loader = StartupModelLoader()
        let models = LlamaModelManager(defaults: defaults, store: store, ramGB: 64,
                                      loadModel: { path in
                                          await loader.load(path)
                                          throw InvalidStartupModel()
                                      })
        models.start()
        XCTAssertEqual(models.status, .loading(id: "custom:synthetic.gguf"))
        guard case .loading = models.status else { return }
        let failed = expectation(description: "model load failure is visible")
        let observation = models.$status.sink { status in
            if case .failed = status { failed.fulfill() }
        }
        defer { observation.cancel() }
        let result = await XCTWaiter.fulfillment(of: [failed], timeout: 3)
        XCTAssertEqual(result, .completed)
        models.start()

        XCTAssertEqual(models.status, .failed(id: "custom:synthetic.gguf",
                                              message: "Couldn't load synthetic: synthetic invalid model"))
        XCTAssertNil(models.loadedID)
        let loadedPaths = await loader.paths
        XCTAssertEqual(loadedPaths, [file.path])
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), [file.lastPathComponent])
    }

    func testUnknownSavedSelectionReportsRecoverableSetupFailureWithoutLoading() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "dev.anuhas.keyweave.tests.model-start.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("unknown:removed-catalog-model", forKey: "llamaModelID")
        let before = defaults.persistentDomain(forName: domain)! as NSDictionary
        let loader = StartupModelLoader()
        let models = LlamaModelManager(defaults: defaults, store: ModelStore(paths: AppPaths(homeDirectory: home)),
                                      ramGB: 64, loadModel: { await loader.load($0) })

        models.start()
        models.start()

        XCTAssertEqual(models.status, .failed(id: "unknown:removed-catalog-model",
                                              message: "Selected model is unavailable. Choose a model in Settings."))
        let loadedPaths = await loader.paths
        XCTAssertEqual(loadedPaths, [])
        XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }

    func testStartLoadsInstalledSelectedModelOnceWithoutChangingStores() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "dev.anuhas.keyweave.tests.model-start.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            try? FileManager.default.removeItem(at: home)
            defaults.removePersistentDomain(forName: domain)
        }
        let store = ModelStore(paths: AppPaths(homeDirectory: home))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let file = store.directory.appendingPathComponent("synthetic.gguf")
        let bytes = Data("synthetic model bytes; native loader must never see these".utf8)
        try bytes.write(to: file)
        defaults.set("custom:synthetic.gguf", forKey: "llamaModelID")
        defaults.set("unchanged", forKey: "unrelated")
        let preferences = defaults.persistentDomain(forName: domain)! as NSDictionary
        let loader = StartupModelLoader()
        let models = LlamaModelManager(defaults: defaults, store: store, ramGB: 64,
                                      loadModel: { await loader.load($0) })

        XCTAssertEqual(models.status, .noModel, "Construction is passive")
        _ = models.entries
        XCTAssertTrue(models.isInstalled(models.selectedID))
        let beforeStart = await loader.paths
        XCTAssertEqual(beforeStart, [], "Settings reads never load a model")

        models.start()
        models.start()
        XCTAssertEqual(models.status, .loading(id: "custom:synthetic.gguf"))
        guard case .loading = models.status else { return }
        let ready = expectation(description: "selected installed model becomes ready")
        let observation = models.$status.sink { status in
            if case .ready = status { ready.fulfill() }
        }
        defer { observation.cancel() }
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 3)
        XCTAssertEqual(result, .completed)
        models.start()

        XCTAssertEqual(models.status, .ready(id: "custom:synthetic.gguf"))
        XCTAssertEqual(models.loadedID, "custom:synthetic.gguf")
        let loadedPaths = await loader.paths
        XCTAssertEqual(loadedPaths, [file.path])
        let inferenceState = await models.inference.state
        XCTAssertEqual(inferenceState, .unloaded, "The test replaces only the native runtime boundary")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), [file.lastPathComponent])
        XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, preferences)
    }
}
