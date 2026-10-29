import Foundation
import XCTest
@testable import TabTypeKit

private final class CatalogNetworkProbe: URLProtocol, @unchecked Sendable {
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

final class BundledCatalogIsolationTests: XCTestCase {
    func testLatestIgnoresRemoteAndNewerCacheWithoutWriting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("catalog-cache.json")
        let bundled = try ModelCatalog.bundled()
        var upstream = bundled
        upstream.version += 100
        let originalCache = try JSONEncoder().encode(upstream)
        try originalCache.write(to: cache)

        CatalogNetworkProbe.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogNetworkProbe.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let catalog = await ModelCatalog.latest(
            remote: URL(string: "https://catalog.invalid/models.json")!, cacheURL: cache, session: session)

        XCTAssertEqual(catalog, bundled, "Gate0 always uses the catalog shipped with this build")
        XCTAssertEqual(CatalogNetworkProbe.requestCount, 0, "Catalog access must not issue a request")
        XCTAssertEqual(try Data(contentsOf: cache), originalCache, "An upstream cache must remain untouched")
    }

    func testModelStoreGettersIgnoreSyntheticUpstreamAndDoNotCreateForkRoot() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let upstream = home.appendingPathComponent("Library/Application Support/TabType/Models")
        try FileManager.default.createDirectory(at: upstream, withIntermediateDirectories: true)
        let sentinel = upstream.appendingPathComponent("private.gguf")
        let bytes = Data("GGUF".utf8)
        try bytes.write(to: sentinel)
        let entry = ModelCatalog.Entry(
            id: "synthetic", name: "Synthetic", summary: "", template: "base",
            url: URL(string: "https://model.invalid/private.gguf")!, fileName: "private.gguf",
            sizeBytes: 4, sha256: nil, license: "", licenseURL: nil,
            requiresTermsNotice: false, minimumRAMGB: 0, showThreshold: nil, extensionThreshold: nil)

        let paths = AppPaths(homeDirectory: home)
        let store = ModelStore(paths: paths)
        XCTAssertEqual(store.directory, paths.modelsDirectory)
        XCTAssertFalse(store.isInstalled(entry), "An upstream model must not appear installed")
        XCTAssertTrue(store.customModels(excluding: ModelCatalog(version: 0, models: [], recommendations: [])).isEmpty)
        _ = store.url(for: entry)
        _ = store.freeDiskBytes()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.supportDirectory.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
    }
}
