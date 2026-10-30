import CoreGraphics
import Foundation

/// Identity of the explicitly consented focused window. Capture never substitutes
/// another application/window when this target cannot be matched.
struct WindowCaptureTarget: Equatable, Sendable {
    let pid: pid_t
    let bundleId: String
    let frame: CGRect
    var title: String?
    var host: String?
    var fieldID: UInt?
    var consentRevision: UUID? = nil

    struct Window: Sendable {
        let id: UInt32
        let pid: pid_t
        let bundleId: String
        let frame: CGRect
        let onScreen: Bool
    }

    func selectedWindowID(in windows: [Window]) -> UInt32? {
        guard pid > 0, !bundleId.isEmpty, Self.valid(frame) else { return nil }
        let matching = windows.filter {
            $0.onScreen && $0.pid == pid && $0.bundleId == bundleId && Self.valid($0.frame)
                && abs($0.frame.minX - frame.minX) <= 12
                && abs($0.frame.minY - frame.minY) <= 12
                && abs($0.frame.maxX - frame.maxX) <= 12
                && abs($0.frame.maxY - frame.maxY) <= 12
        }
        // Overlapping equal-geometry windows are ambiguous; skip the capture.
        return matching.count == 1 ? matching.first?.id : nil
    }

    func contains(_ rect: CGRect) -> Bool {
        Self.valid(rect) && frame.insetBy(dx: -1, dy: -1).contains(rect)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }
}
