import Foundation
import ServiceManagement

/// Wraps `SMAppService` to toggle launch at login. Works only for a
/// properly bundled, signed .app.
@MainActor
enum LaunchAtLogin {
    @MainActor
    struct SystemBoundary {
        var isEnabled: @MainActor () -> Bool
        var setEnabled: @MainActor (Bool) throws -> Void

        static let live = SystemBoundary(
            isEnabled: { SMAppService.mainApp.status == .enabled },
            setEnabled: { enabled in
                if enabled {
                    if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            })
    }

    static var isEnabled: Bool {
        isEnabled(using: .live)
    }

    static func isEnabled(using system: SystemBoundary) -> Bool {
        guard AppSafetyPolicy.launchAtLoginEnabled else { return false }
        return system.isEnabled()
    }

    static func set(_ enabled: Bool, using system: SystemBoundary = .live) {
        guard AppSafetyPolicy.launchAtLoginEnabled else { return }
        do {
            try system.setEnabled(enabled)
        } catch {
            NSLog("Keyweave: launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
