import Combine
import Foundation
import TabTypeKit

/// Sparkle owns downloading, signature verification, replacement and relaunch.
/// This facade keeps construction passive and rejects unconfigured/test hosts.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    nonisolated static let feedURL = "https://raw.githubusercontent.com/DevAnuhas/keyweave/main/Updates/appcast.xml"
    nonisolated static let publicKey = "pc1gLnpongI0flX6p0FOVK509djxXgyrKN8rcMB4bRU="

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isRunning = false
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var failure: String?
    let isAvailable: Bool
    private let makeDriver: () -> any UpdateDriver
    private var driver: (any UpdateDriver)?
    private var observation: AnyCancellable?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    var automatic: Bool {
        get { driver?.automaticallyChecksForUpdates ?? false }
        set {
            guard let driver else { return }
            driver.automaticallyChecksForUpdates = newValue
            refresh()
        }
    }

    init(allowed: Bool = Updater.isSupportedHost(),
         makeDriver: @escaping () -> any UpdateDriver = { SparkleUpdateDriver() }) {
        isAvailable = allowed
        self.makeDriver = makeDriver
    }

    func start() {
        guard isAvailable, !isRunning else { return }
        do {
            let service = makeDriver()
            try service.start()
            driver = service
            isRunning = true
            failure = nil
            observation = service.changes.sink { [weak self] in self?.refresh() }
            refresh()
        } catch {
            failure = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        driver?.checkForUpdates()
    }

    private func refresh() {
        objectWillChange.send()
        canCheckForUpdates = driver?.canCheckForUpdates ?? false
        lastCheckDate = driver?.lastUpdateCheckDate
    }

    static func isSupportedHost() -> Bool {
        let bundle = Bundle.main
        return permits(bundleIdentifier: bundle.bundleIdentifier,
                       isApplication: bundle.bundleURL.pathExtension == "app",
                       feed: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                       key: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                       signedFeed: bundle.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool ?? false,
                       verifiedExtraction: bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool ?? false,
                       isTestProcess: ProcessInfo.processInfo.environment["KEYWEAVE_TEST_HOME"] != nil)
    }

    nonisolated static func permits(bundleIdentifier: String?, isApplication: Bool,
                                    feed: String?, key: String?, signedFeed: Bool,
                                    verifiedExtraction: Bool, isTestProcess: Bool) -> Bool {
        !isTestProcess && isApplication && bundleIdentifier == ProductIdentity.bundleIdentifier
            && feed == feedURL && key == publicKey && signedFeed && verifiedExtraction
    }

    /// "1.10.0" > "1.9.2"; pre-release suffixes are ignored.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// The release notes' "**SHA-256** `…`" line.
    nonisolated static func sha256(inNotes notes: String) -> String? {
        guard let range = notes.range(of: #"SHA-256\**\s*`([0-9a-fA-F]{64})`"#, options: .regularExpression)
        else { return nil }
        let match = String(notes[range])
        return match.range(of: #"[0-9a-fA-F]{64}"#, options: .regularExpression).map { String(match[$0]).lowercased() }
    }

}
