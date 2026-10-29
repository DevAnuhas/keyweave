import Combine
import Foundation
import TabTypeKit

/// Gate0 has no update feed, transport, installer, process runner, or relaunch
/// path. Keep the former interface inert so direct callers cannot re-enable it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let disabledReason = "Updates are disabled in this Keyweave build."

    struct Release: Equatable {
        var version: String
        var page: URL
        var dmg: URL
        var sha256: String?
    }

    enum State: Equatable {
        case idle, checking, upToDate
        case available(Release)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var automatic: Bool {
        get { false }
        set { /* Gate0 ignores persisted and direct attempts to enable updates. */ }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Accept isolated dependencies for callers of the former updater API. Gate0
    /// neither retains nor uses a preferences store or a network session.
    init(defaults: UserDefaults = AppPreferences.current, session: URLSession? = nil) {}

    func checkIfDue() {}
    func check() async {}
    func install(_ release: Release) {}

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
