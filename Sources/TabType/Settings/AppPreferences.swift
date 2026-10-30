import CryptoKit
import Foundation
import TabTypeKit

/// Available capabilities. Acquiring context, storing writing and syncing still
/// require their separate, local opt-in settings at every entry point.
enum AppSafetyPolicy {
    static let inputMonitoringEnabled = true
    static let syncEnabled = true
    static let writingEnabled = true
    static let screenContextEnabled = true
    static let clipboardContextEnabled = true
    static let screenshotAppearanceEnabled = true
    static let launchAtLoginEnabled = true
}

@MainActor
enum AppPreferences {
    static let current = makeCurrent()

    static func domain(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        guard let home = environment["KEYWEAVE_TEST_HOME"], home.hasPrefix("/") else {
            return ProductIdentity.preferencesDomain
        }
        let path = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return ProductIdentity.preferencesDomain + ".test." + digest
    }

    static func makeCurrent(environment: [String: String] = ProcessInfo.processInfo.environment) -> UserDefaults {
        DomainPreferences(domain: domain(environment: environment))
    }
}

/// Read only the named persistent domain. In particular, never search the
/// executable's defaults domain, argument domain, or global defaults for values.
private final class DomainPreferences: UserDefaults, @unchecked Sendable {
    private let domain: String

    init(domain: String) {
        self.domain = domain
        // Foundation rejects the process's own bundle ID as a named suite.
        // Its default store already writes to that domain; reads below still
        // use only our explicit domain, without argument/global fallbacks.
        super.init(suiteName: domain == Bundle.main.bundleIdentifier ? nil : domain)!
    }

    override func object(forKey key: String) -> Any? { persistentDomain(forName: domain)?[key] }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    override func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    override func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
    override func integer(forKey key: String) -> Int { (object(forKey: key) as? NSNumber)?.intValue ?? 0 }
    override func float(forKey key: String) -> Float { (object(forKey: key) as? NSNumber)?.floatValue ?? 0 }
    override func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }
    override func dictionaryRepresentation() -> [String: Any] { persistentDomain(forName: domain) ?? [:] }
}
