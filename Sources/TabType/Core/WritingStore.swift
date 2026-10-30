import CryptoKit
import Darwin
import Foundation
import TabTypeKit

/// The author's own writing, kept (opt-in) so suggestions can reuse their
/// phrasing. Encrypted at rest; scrubbed of secrets before storage; capped in
/// size. Acquisition is available only while the local learning control is on.
@MainActor
final class WritingStore: ObservableObject {
    static let shared = WritingStore()

    struct Document: Codable, Equatable {
        /// Messages get a unique key; a field's text is keyed by app + window so
        /// later versions of the same draft replace earlier ones.
        var key: String
        var bundleId: String
        var text: String
        var updated: Date
    }

    /// A clear operation starts a new writing generation. Remote writing must
    /// acknowledge it before any documents can be imported again.
    struct Erasure: Codable, Equatable {
        var date: Date
        var id: String
    }

    struct SyncState: Codable {
        var writing: [Document]
        var erasure: Erasure?
    }

    private struct Archive: Codable {
        var version = 1
        var state: SyncState
    }

    enum Kind { case message, field }

    @Published private(set) var documentCount = 0
    @Published private(set) var characterCount = 0
    @Published private(set) var status = ""
    /// Fires (debounced by the caller) when the stored writing changed.
    var onChange: (() -> Void)?
    /// Sync between Macs wants to hear about new writing.
    var onSyncNeeded: (() -> Void)?

    private var documents: [Document] = []
    private var loaded = false
    private var storageBlocked = false
    private var erasure: Erasure?
    private let maxCharacters = 1_000_000
    private let minimumLength = 20
    private let directory: URL
    private let collectionEnabled: @MainActor () -> Bool
    private var fileURL: URL { directory.appendingPathComponent("writing.enc") }
    private var keyURL: URL { directory.appendingPathComponent("history.key") }
    private var erasureURL: URL { directory.appendingPathComponent("writing-erasure.json") }

    init(directory: URL = AppPaths.current.supportDirectory,
         collectionEnabled: @escaping @MainActor () -> Bool = { AppSettings.shared.collectTypingHistory }) {
        self.directory = directory
        self.collectionEnabled = collectionEnabled
    }

    /// Loading is an explicit lifecycle operation, never part of construction.
    func start() {
        guard collectionEnabled() else { stopCollection(); return }
        guard !loaded, !storageBlocked else { return }
        load()
    }

    /// Stop using the saved writing immediately; persistent deletion is explicit.
    func stopCollection() {
        let changed = !documents.isEmpty
        documents.removeAll()
        loaded = false
        storageBlocked = false
        status = ""
        refreshCounts()
        if changed { onChange?() }
    }

    var texts: [String] { collectionEnabled() ? documents.map(\.text) : [] }

    func record(_ text: String, bundleId: String, fieldKey: String?, kind: Kind) {
        guard collectionEnabled() else { return }
        start()
        guard !storageBlocked else { return }
        let clean = SecretSanitizer.sanitize(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= minimumLength else { return }
        let previous = documents
        switch kind {
        case .message:
            guard documents.last?.text != clean else { return }
            documents.append(Document(key: "msg:\(UUID().uuidString)", bundleId: bundleId, text: clean, updated: Date()))
        case .field:
            let key = "field:\(bundleId)|\(fieldKey ?? "")"
            if let i = documents.firstIndex(where: { $0.key == key }) {
                guard documents[i].text != clean else { return }
                documents[i].text = clean
                documents[i].updated = Date()
            } else {
                documents.append(Document(key: key, bundleId: bundleId, text: clean, updated: Date()))
            }
        }
        trim()
        if !persist() { documents = previous; refreshCounts() }
    }

    /// Retained for source compatibility. Import files are never consumed.
    func importPendingFile() {}

    /// Everything stored (for sync between Macs).
    var allDocuments: [Document] { collectionEnabled() ? documents : [] }

    /// Merge writing from another Mac: union by key, the newer version wins.
    func merge(_ incoming: [Document]) {
        guard collectionEnabled() else { return }
        start()
        // Legacy callers cannot acknowledge a clear operation.
        guard !storageBlocked, erasure == nil else { return }
        mergeDocuments(incoming)
    }

    private func mergeDocuments(_ incoming: [Document]) {
        let previous = documents
        var changed = false
        for incomingDocument in incoming {
            var doc = incomingDocument
            doc.text = SecretSanitizer.sanitize(doc.text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard doc.text.count >= minimumLength, doc.text.count <= maxCharacters,
                  doc.updated.timeIntervalSince1970.isFinite else { continue }
            if let i = documents.firstIndex(where: { $0.key == doc.key }) {
                if doc.updated > documents[i].updated, doc.text != documents[i].text {
                    documents[i] = doc
                    changed = true
                }
            } else {
                documents.append(doc)
                changed = true
            }
        }
        guard changed else { return }
        trim()
        if !persist() { documents = previous; refreshCounts() }
    }

    func eraseAll() {
        documents.removeAll()
        loaded = true
        storageBlocked = true
        refreshCounts()
        onChange?()
        do {
            let previous = Self.newer(erasure, try? readErasure())
            let date = max(Date(), previous?.date.addingTimeInterval(0.001) ?? .distantPast)
            let cleared = Erasure(date: date, id: UUID().uuidString)
            try writeErasure(cleared)
            erasure = cleared
            try removeWritingFiles()
            loaded = false
            storageBlocked = false
            status = ""
            refreshCounts()
            onSyncNeeded?()
        } catch {
            status = "Saved writing could not be fully erased. Check storage access and try again."
        }
    }

    /// Called only by an explicitly enabled sync service. With learning off it
    /// reads deletion metadata only, never the encryption key or writing file.
    func stateForSync() throws -> SyncState {
        let newest = Self.newer(erasure, try readErasure())
        if newest != erasure {
            erasure = newest
            documents.removeAll()
            loaded = false
            storageBlocked = false
            refreshCounts()
            onChange?()
        }
        if collectionEnabled() {
            start()
            guard !storageBlocked else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: status])
            }
        }
        return SyncState(writing: collectionEnabled() ? documents : [], erasure: erasure)
    }

    /// Sync consent permits propagating an explicit erase while learning is
    /// off. Importing any actual writing still requires local learning consent.
    func mergeSyncState(_ incoming: SyncState) throws {
        let newest = Self.newer(Self.newer(erasure, try readErasure()), incoming.erasure)
        if newest != erasure, let newest {
            try writeErasure(newest)
            erasure = newest
            documents.removeAll()
            refreshCounts()
            onChange?()
            do { try removeWritingFiles() }
            catch {
                loaded = true
                storageBlocked = true
                status = "Saved writing could not be fully erased. Check storage access and try again."
                throw error
            }
            loaded = false
            storageBlocked = false
            status = ""
            onSyncNeeded?()
        }
        guard collectionEnabled() else { return }
        start()
        guard !storageBlocked, incoming.erasure == erasure else { return }
        mergeDocuments(incoming.writing)
    }

    // MARK: Storage

    private func trim() {
        documents.sort { $0.updated < $1.updated }
        var total = documents.reduce(0) { $0 + $1.text.count }
        while total > maxCharacters, !documents.isEmpty {
            total -= documents.removeFirst().text.count
        }
        refreshCounts()
    }

    private func refreshCounts() {
        documentCount = documents.count
        characterCount = documents.reduce(0) { $0 + $1.text.count }
    }

    @discardableResult
    private func persist() -> Bool {
        guard collectionEnabled(), !storageBlocked,
              let key = encryptionKeyForWriting(),
              let data = try? JSONEncoder().encode(Archive(state: SyncState(writing: documents, erasure: erasure))),
              let sealed = try? AES.GCM.seal(data, using: key).combined else {
            status = "Saved writing could not be updated. Existing files were preserved."
            return false
        }
        do {
            try writePrivate(sealed, to: fileURL)
            status = ""
            onChange?()
            onSyncNeeded?()
            return true
        } catch {
            status = "Saved writing could not be updated. Check storage access and try again."
            return false
        }
    }

    private func load() {
        guard collectionEnabled() else { return }
        loaded = true
        do { erasure = Self.newer(erasure, try readErasure()) }
        catch { unreadableStore(); return }
        let manager = FileManager.default
        let hasKey = manager.fileExists(atPath: keyURL.path)
        let hasWriting = manager.fileExists(atPath: fileURL.path)
        guard hasKey || hasWriting else { return }
        guard let key = existingEncryptionKey() else { unreadableStore(); return }
        guard hasWriting else { return }
        guard let sealed = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key) else {
            unreadableStore()
            return
        }
        let state: SyncState
        if let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1 {
            state = archive.state
        } else if let legacy = try? JSONDecoder().decode([Document].self, from: data) {
            state = SyncState(writing: legacy, erasure: nil)
        } else { unreadableStore(); return }
        erasure = Self.newer(erasure, state.erasure)
        documents = state.erasure == erasure ? state.writing : []
        refreshCounts()
    }

    private static func newer(_ first: Erasure?, _ second: Erasure?) -> Erasure? {
        guard let first else { return second }
        guard let second else { return first }
        if first.date != second.date { return first.date > second.date ? first : second }
        return first.id >= second.id ? first : second
    }

    private func readErasure() throws -> Erasure? {
        guard FileManager.default.fileExists(atPath: erasureURL.path) else { return nil }
        let value = try JSONDecoder().decode(Erasure.self, from: Data(contentsOf: erasureURL))
        guard UUID(uuidString: value.id) != nil, value.date.timeIntervalSince1970.isFinite else {
            throw CocoaError(.coderInvalidValue)
        }
        return value
    }

    private func writeErasure(_ value: Erasure) throws {
        guard UUID(uuidString: value.id) != nil, value.date.timeIntervalSince1970.isFinite else {
            throw CocoaError(.coderInvalidValue)
        }
        try writePrivate(JSONEncoder().encode(value), to: erasureURL)
    }

    private func removeWritingFiles() throws {
        for url in [fileURL, keyURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Create private files before making their contents visible. Replacement
    /// is atomic; new encryption keys additionally refuse any existing path.
    private func writePrivate(_ data: Data, to destination: URL, replace: Bool = true) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let staging = replace ? directory.appendingPathComponent(".writing-\(UUID().uuidString)") : destination
        let descriptor = Darwin.open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            if replace { try? FileManager.default.removeItem(at: staging) }
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        if replace, Darwin.rename(staging.path, destination.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func unreadableStore() {
        storageBlocked = true
        documents.removeAll()
        refreshCounts()
        status = "Saved writing could not be opened. Restore its original key/files, or explicitly erase it to start over."
    }

    /// Read-only lookup: absent or malformed keys must not be replaced by reads.
    private func existingEncryptionKey() -> SymmetricKey? {
        guard let data = try? Data(contentsOf: keyURL), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    /// A new key may only be created for an explicitly enabled write and a new
    /// store. An existing malformed/unreadable key or encrypted file is retained.
    private func encryptionKeyForWriting() -> SymmetricKey? {
        if let key = existingEncryptionKey() { return key }
        guard !FileManager.default.fileExists(atPath: keyURL.path),
              !FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let key = SymmetricKey(size: .bits256)
        do {
            try key.withUnsafeBytes { try writePrivate(Data($0), to: keyURL, replace: false) }
        } catch {
            return nil
        }
        return key
    }
}

/// Suffix index over the writing store, rebuilt in the background after changes.
@MainActor
final class PersonalIndex {
    static let shared = PersonalIndex()
    private(set) var index: SuffixIndex?
    private var rebuild: Task<Void, Never>?
    private let injectedStore: WritingStore?
    private let collectionEnabled: @MainActor () -> Bool
    private var store: WritingStore { injectedStore ?? WritingStore.shared }

    init(store: WritingStore? = nil,
         collectionEnabled: @escaping @MainActor () -> Bool = { AppSettings.shared.collectTypingHistory }) {
        injectedStore = store
        self.collectionEnabled = collectionEnabled
    }

    func start() {
        guard collectionEnabled() else { stop(); return }
        store.onChange = { [weak self] in self?.scheduleRebuild() }
        scheduleRebuild(delay: 0)
    }

    func stop() {
        rebuild?.cancel()
        rebuild = nil
        index = nil
        store.onChange = nil
    }

    func hint(after typed: String) -> RetrievalHint? {
        guard collectionEnabled() else { return nil }
        return index?.continuation(after: typed)
    }

    private func scheduleRebuild(delay: TimeInterval = 5) {
        guard collectionEnabled() else { stop(); return }
        rebuild?.cancel()
        let texts = store.texts
        guard !texts.isEmpty else { index = nil; rebuild = nil; return }
        rebuild = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, self?.collectionEnabled() == true else { return }
            let built = await Task.detached(priority: .utility) { SuffixIndex(documents: texts) }.value
            guard !Task.isCancelled, self?.collectionEnabled() == true else { return }
            self?.index = built.isEmpty ? nil : built
            Log.shared.debug("personal index: \(texts.count) documents, \(built.byteCount) bytes")
        }
    }
}
