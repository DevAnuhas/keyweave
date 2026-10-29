import CryptoKit
import Foundation
import TabTypeKit

/// The author's own writing, kept (opt-in) so suggestions can reuse their
/// phrasing. Encrypted at rest; scrubbed of secrets before storage; capped in
/// size. Gate0 never starts this service or reads/imports an older store.
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

    enum Kind { case message, field }

    @Published private(set) var documentCount = 0
    @Published private(set) var characterCount = 0
    /// Fires (debounced by the caller) when the stored writing changed.
    var onChange: (() -> Void)?
    /// Sync between Macs wants to hear about new writing.
    var onSyncNeeded: (() -> Void)?

    private var documents: [Document] = []
    private let maxCharacters = 1_000_000
    private let minimumLength = 20
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("writing.enc") }
    private var keyURL: URL { directory.appendingPathComponent("history.key") }

    init(directory: URL = AppPaths.current.supportDirectory) {
        self.directory = directory
    }

    /// Loading is an explicit lifecycle operation, never part of construction.
    func start() {
        guard AppSafetyPolicy.writingEnabled else { return }
        load()
    }

    var texts: [String] { documents.map(\.text) }

    func record(_ text: String, bundleId: String, fieldKey: String?, kind: Kind) {
        guard AppSafetyPolicy.writingEnabled else { return }
        let clean = SecretSanitizer.sanitize(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= minimumLength else { return }
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
        persist()
    }

    /// One-time import: `import-writing.jsonl` next to the store (one
    /// `{"bundleId": …, "text": …}` per line — e.g. past messages recovered
    /// from the local log) is recorded like anything written, then deleted.
    func importPendingFile() {
        guard AppSafetyPolicy.writingEnabled else { return }
        let url = directory.appendingPathComponent("import-writing.jsonl")
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return }
        var count = 0
        for line in data.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String],
                  let text = obj["text"], let bundleId = obj["bundleId"] else { continue }
            let before = documents.count
            record(text, bundleId: bundleId, fieldKey: nil, kind: .message)
            if documents.count > before { count += 1 }
        }
        try? FileManager.default.removeItem(at: url)
        Log.shared.info("writing: imported \(count) messages")
    }

    /// Everything stored (for sync between Macs).
    var allDocuments: [Document] { documents }

    /// Merge writing from another Mac: union by key, the newer version wins.
    func merge(_ incoming: [Document]) {
        guard AppSafetyPolicy.writingEnabled else { return }
        var changed = false
        for doc in incoming {
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
        persist()
    }

    func eraseAll() {
        guard AppSafetyPolicy.writingEnabled else { return }
        documents.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
        refreshCounts()
        onChange?()
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

    private func persist() {
        guard AppSafetyPolicy.writingEnabled,
              let key = encryptionKeyForWriting(), let data = try? JSONEncoder().encode(documents),
              let sealed = try? AES.GCM.seal(data, using: key).combined else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? sealed.write(to: fileURL, options: .atomic)
        onChange?()
        onSyncNeeded?()
    }

    private func load() {
        guard AppSafetyPolicy.writingEnabled,
              let key = existingEncryptionKey(), let sealed = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key),
              let docs = try? JSONDecoder().decode([Document].self, from: data) else { return }
        documents = docs
        refreshCounts()
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
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try key.withUnsafeBytes { Data($0) }.write(to: keyURL, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
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

    func start() {
        guard AppSafetyPolicy.writingEnabled else { return }
        WritingStore.shared.onChange = { [weak self] in self?.scheduleRebuild() }
        scheduleRebuild(delay: 0)
    }

    func hint(after typed: String) -> RetrievalHint? {
        guard AppSafetyPolicy.writingEnabled else { return nil }
        return index?.continuation(after: typed)
    }

    private func scheduleRebuild(delay: TimeInterval = 5) {
        guard AppSafetyPolicy.writingEnabled else { return }
        rebuild?.cancel()
        let texts = WritingStore.shared.texts
        rebuild = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            let built = await Task.detached(priority: .utility) { SuffixIndex(documents: texts) }.value
            guard !Task.isCancelled else { return }
            self?.index = built.isEmpty ? nil : built
            Log.shared.debug("personal index: \(texts.count) documents, \(built.byteCount) bytes")
        }
    }
}
