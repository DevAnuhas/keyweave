import Combine
import CommonCrypto
import CryptoKit
import Foundation
import Security
import TabTypeKit

/// Opt-in sync through iCloud Drive. Each Mac writes one AES-GCM-sealed file to
/// iCloud Drive/Keyweave Sync/ with its settings and learned writing; the key is
/// derived from a passphrase the user sets on every Mac, so Apple only ever
/// stores ciphertext. Local privacy controls never follow another Mac.
@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published private(set) var status = ""
    @Published private(set) var otherMacs = 0

    private let defaults: UserDefaults
    private let injectedSettings: AppSettings?
    private var injectedWritingStore: WritingStore?
    private var settings: AppSettings { injectedSettings ?? AppSettings.shared }
    private var writingStore: WritingStore { injectedWritingStore ?? WritingStore.shared }
    private var settingsWatch: AnyCancellable?
    private var timer: Timer?
    private var pendingSync: DispatchWorkItem?
    private var applyingRemote = false
    private var running = false
    private var lastSettingsSnapshot: SyncedSettings?

    private static let enabledKey = "syncEnabled"
    private static let machineKey = "syncMachineID"
    private static let settingsChangedKey = "syncSettingsChangedAt"
    private static let publishedSettingsKey = "syncPublishedSharedSettings"
    private let paths: AppPaths
    private let system: SyncSystemBoundary

    var enabled: Bool {
        get { AppSafetyPolicy.syncEnabled && defaults.bool(forKey: Self.enabledKey) }
        set {
            guard AppSafetyPolicy.syncEnabled else { return }
            defaults.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
            if newValue { start() } else { stop(); status = "" }
        }
    }

    var hasPassphrase: Bool {
        guard enabled else { return false }
        return system.readPassphrase(ProductIdentity.keychainService) != nil
    }

    /// iCloud Drive's folder for Keyweave (nil while sync is unavailable).
    var folder: URL? {
        guard enabled else { return nil }
        let drive = paths.syncDirectory.deletingLastPathComponent()
        guard system.cloudDriveExists(drive) else { return nil }
        return paths.syncDirectory
    }

    private var machineID: String {
        guard AppSafetyPolicy.syncEnabled else { return "" }
        if let id = defaults.string(forKey: Self.machineKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.machineKey)
        return id
    }

    private var settingsChangedAt: Date {
        get { defaults.object(forKey: Self.settingsChangedKey) as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: Self.settingsChangedKey) }
    }

    init(defaults: UserDefaults = AppPreferences.current, settings: AppSettings? = nil,
         paths: AppPaths = .current, system: SyncSystemBoundary = .live) {
        self.defaults = defaults
        injectedSettings = settings
        self.paths = paths
        self.system = system
    }

    convenience init(defaults: UserDefaults, settings: AppSettings?, paths: AppPaths,
                     system: SyncSystemBoundary, writingStore: WritingStore?) {
        self.init(defaults: defaults, settings: settings, paths: paths, system: system)
        injectedWritingStore = writingStore
    }

    func start() {
        guard enabled, !running else { return }
        running = true
        prepareSettingsSnapshot()
        settingsWatch = settings.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.applyingRemote else { return }
                // objectWillChange arrives before the actual property change.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.enabled, self.running, !self.applyingRemote else { return }
                    self.markChangedSettings()
                }
            }
        }
        writingStore.onSyncNeeded = { [weak self] in
            guard let self, !self.applyingRemote else { return }
            self.scheduleSync(after: 30)
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        syncNow()
    }

    func stop() {
        let wasRunning = running
        running = false
        settingsWatch = nil
        timer?.invalidate()
        timer = nil
        pendingSync?.cancel()
        pendingSync = nil
        lastSettingsSnapshot = nil
        if wasRunning { writingStore.onSyncNeeded = nil }
    }

    func setPassphrase(_ passphrase: String) {
        guard enabled else { return }
        guard passphrase.count >= 8 else { status = "Use at least 8 characters"; return }
        do {
            try system.storePassphrase(ProductIdentity.keychainService, passphrase)
        } catch {
            status = "Keychain could not save the sync passphrase. Its existing value was kept; check access and try again."
            return
        }
        objectWillChange.send()
        syncNow()
    }

    private func scheduleSync(after delay: TimeInterval) {
        guard enabled else { return }
        pendingSync?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncNow() }
        pendingSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func transferableSettings() -> SyncedSettings {
        var snapshot = settings.syncSnapshot
        snapshot.useScreenContext = false
        snapshot.useClipboardContext = false
        snapshot.useScreenshotAppearance = false
        snapshot.collectTypingHistory = false
        snapshot.recordWithoutAccepts = false
        for key in snapshot.appOverrides.keys {
            snapshot.appOverrides[key]?.readConversation = nil
            snapshot.appOverrides[key]?.learnFromWriting = nil
        }
        return snapshot
    }

    private func markChangedSettings() {
        let current = transferableSettings()
        guard let previous = lastSettingsSnapshot, current != previous else { return }
        lastSettingsSnapshot = current
        settingsChangedAt = Date()
        scheduleSync(after: 5)
    }

    private func prepareSettingsSnapshot() {
        guard lastSettingsSnapshot == nil else { return }
        let current = transferableSettings()
        if let data = defaults.data(forKey: Self.publishedSettingsKey),
           let published = try? JSONDecoder().decode(SyncedSettings.self, from: data),
           current != published {
            // No observers run while sync is off. Detect those local edits on
            // re-entry; a first-time join has no published baseline to compare.
            settingsChangedAt = Date()
        }
        lastSettingsSnapshot = current
    }

    // MARK: Sync

    struct Payload: Codable {
        var machine: String
        var written: Date
        var settingsChangedAt: Date
        var settings: SyncedSettings
        var writing: [WritingStore.Document]
        var erasure: WritingStore.Erasure?
    }

    func syncNow() {
        guard AppSafetyPolicy.syncEnabled, enabled else { return }
        guard let folder else { status = "Turn on iCloud Drive to sync"; return }
        guard let passphrase = system.readPassphrase(ProductIdentity.keychainService) else {
            status = "Set a sync passphrase, or unlock Keychain if one is already saved"
            return
        }
        do {
            prepareSettingsSnapshot()
            markChangedSettings()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let key = try Self.key(passphrase: passphrase, salt: try Self.salt(in: folder))

            // Read the other Macs first, then write ours with the merged result.
            var others = 0
            var unreadable = 0
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where file.pathExtension == ProductIdentity.syncFileExtension && file.deletingPathExtension().lastPathComponent != machineID {
                guard let sealed = try? Data(contentsOf: file),
                      let box = try? AES.GCM.SealedBox(combined: sealed),
                      let data = try? AES.GCM.open(box, using: key),
                      let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                    unreadable += 1
                    continue
                }
                others += 1
                applyingRemote = true
                do {
                    try writingStore.mergeSyncState(.init(writing: payload.writing, erasure: payload.erasure))
                } catch {
                    applyingRemote = false
                    throw error
                }
                if payload.settingsChangedAt > settingsChangedAt {
                    settings.apply(payload.settings)
                    settingsChangedAt = payload.settingsChangedAt
                    lastSettingsSnapshot = transferableSettings()
                }
                applyingRemote = false
            }

            if settingsChangedAt == .distantPast { settingsChangedAt = Date() }
            let writing = try writingStore.stateForSync()
            let mine = Payload(machine: "Mac", written: Date(),
                               settingsChangedAt: settingsChangedAt, settings: transferableSettings(),
                               writing: writing.writing, erasure: writing.erasure)
            let publishedSettings = try JSONEncoder().encode(mine.settings)
            let sealed = try AES.GCM.seal(try JSONEncoder().encode(mine), using: key).combined!
            let destination = folder.appendingPathComponent("\(machineID).\(ProductIdentity.syncFileExtension)")
            try sealed.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            defaults.set(publishedSettings, forKey: Self.publishedSettingsKey)
            lastSettingsSnapshot = mine.settings

            otherMacs = others
            let time = Date().formatted(date: .omitted, time: .shortened)
            status = unreadable > 0
                ? "Synced at \(time) — \(unreadable) Mac(s) use a different passphrase"
                : "Synced at \(time) with \(others) other Mac\(others == 1 ? "" : "s")"
        } catch {
            status = "Sync failed: \(error.localizedDescription)"
            Log.shared.info("sync: \(error)")
        }
    }

    // MARK: Keys

    /// The folder's shared random salt (made by the first Mac to sync).
    private static func salt(in folder: URL) throws -> Data {
        let url = folder.appendingPathComponent("salt")
        if FileManager.default.fileExists(atPath: url.path) {
            let salt = try Data(contentsOf: url)
            guard salt.count == 16 else { throw CocoaError(.coderInvalidValue) }
            return salt
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, 16, &bytes) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        let salt = Data(bytes)
        do { try salt.write(to: url, options: .withoutOverwriting) }
        catch {
            let existing = try Data(contentsOf: url)
            guard existing.count == 16 else { throw CocoaError(.coderInvalidValue) }
            return existing
        }
        return salt
    }

    /// PBKDF2-HMAC-SHA256, 200k rounds.
    nonisolated static func key(passphrase: String, salt: Data) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let pw = Array(passphrase.utf8)
        let status = salt.withUnsafeBytes { saltPtr in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                 saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &derived, derived.count)
        }
        guard status == kCCSuccess else { throw CocoaError(.coderInvalidValue) }
        return SymmetricKey(data: derived)
    }

}

/// The system interfaces used by sync. Merely constructing this value does not
/// inspect Keychain or iCloud; synthetic tests replace every closure.
@MainActor
struct SyncSystemBoundary {
    var readPassphrase: @MainActor (String) -> String?
    var storePassphrase: @MainActor (String, String) throws -> Void
    var cloudDriveExists: @MainActor (URL) -> Bool

    static let live = SyncSystemBoundary(
        readPassphrase: readPassphrase,
        storePassphrase: storePassphrase,
        cloudDriveExists: { FileManager.default.fileExists(atPath: $0.path) })

    private static func readPassphrase(service: String) -> String? {
        guard AppSafetyPolicy.syncEnabled else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func storePassphrase(service: String, passphrase: String) throws {
        guard AppSafetyPolicy.syncEnabled else { return }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service]
        let value = Data(passphrase.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = value
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
