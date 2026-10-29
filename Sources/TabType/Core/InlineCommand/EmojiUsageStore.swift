import Foundation

/// Tracks recently-used emoji so they rank higher next time. Stored in UserDefaults.
@MainActor
final class EmojiUsageStore {
    static let shared = EmojiUsageStore()
    private let key = "emojiRecents"
    private let maxRecents = 24
    private let defaults: UserDefaults

    private(set) var recentCodes: [String]

    init(defaults: UserDefaults = AppPreferences.current) {
        self.defaults = defaults
        recentCodes = defaults.stringArray(forKey: key) ?? []
    }

    func record(_ code: String) {
        recentCodes.removeAll { $0 == code }
        recentCodes.insert(code, at: 0)
        if recentCodes.count > maxRecents { recentCodes.removeLast(recentCodes.count - maxRecents) }
        defaults.set(recentCodes, forKey: key)
    }
}
