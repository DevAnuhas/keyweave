import Foundation
import TabTypeKit

/// Lightweight file logger for diagnosing behavior in specific apps without a
/// debugger. Writes to Keyweave's own log directory. Verbose entries are
/// gated by `verbose` so normal runs stay quiet. The file is capped: past
/// `maxBytes` its newest `keptBytes` move to keyweave.1.log and it starts over,
/// so the log (which holds typed text when verbose) never piles up.
final class Log: @unchecked Sendable {
    static let shared = Log()

    var verbose = false

    private let url: URL
    private let previousURL: URL
    private let queue = DispatchQueue(label: "app.tabtype.log")
    private let formatter: DateFormatter
    private var writesSinceCheck = 0

    static let maxBytes: UInt64 = 5 * 1024 * 1024
    static let keptBytes = 1024 * 1024

    init(directory: URL = AppPaths.current.logsDirectory) {
        url = directory.appendingPathComponent("keyweave.log")
        previousURL = directory.appendingPathComponent("keyweave.1.log")
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
    }

    static var fileURL: URL { shared.url }

    /// Always-logged line (lifecycle, errors).
    func info(_ message: @autoclosure () -> String) { write(message()) }

    /// Only logged when verbose logging is enabled.
    func debug(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        write(message())
    }

    /// Delete both log files (Settings → Advanced).
    func clear() {
        queue.async { [url, previousURL] in
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: previousURL)
        }
    }

    /// Wait for already queued writes and clears to finish. Does not write or rotate.
    func flush() { queue.sync {} }

    private func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async { [self] in
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Defer the initial check until real use, then recheck every 500 writes.
            // Each new process must check even if its previous session was short.
            if writesSinceCheck == 0 { rotateIfNeeded() }
            writesSinceCheck = (writesSinceCheck + 1) % 500
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// On the log queue.
    private func rotateIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64,
              size > Self.maxBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: size - UInt64(Self.keptBytes))
        var tail = handle.readDataToEndOfFile()
        // Start at a whole line.
        if let newline = tail.firstIndex(of: 0x0A) { tail = tail.suffix(from: tail.index(after: newline)) }
        try? tail.write(to: previousURL, options: .atomic)
        try? Data().write(to: url, options: .atomic)
    }
}
