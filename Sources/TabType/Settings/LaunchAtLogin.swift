import Foundation
import ServiceManagement

/// Wraps `SMAppService` to toggle launch at login. Works only for a
/// properly bundled, signed .app.
@MainActor
enum LaunchAtLogin {
    enum Status: Equatable {
        case disabled, enabled, requiresApproval, unavailable

        var isRequested: Bool { self == .enabled || self == .requiresApproval }
    }

    @MainActor
    struct SystemBoundary {
        var isEnabled: @MainActor () -> Bool
        var setEnabled: @MainActor (Bool) throws -> Void
        var readStatus: (@MainActor () -> Status)? = nil

        init(isEnabled: @escaping @MainActor () -> Bool,
             setEnabled: @escaping @MainActor (Bool) throws -> Void,
             readStatus: (@MainActor () -> Status)? = nil) {
            self.isEnabled = isEnabled
            self.setEnabled = setEnabled
            self.readStatus = readStatus
        }

        init(status: @escaping @MainActor () -> Status,
             register: @escaping @MainActor () throws -> Void,
             unregister: @escaping @MainActor () throws -> Void) {
            isEnabled = { status() == .enabled }
            readStatus = status
            setEnabled = { enabled in
                let current = status()
                if enabled {
                    if !current.isRequested { try register() }
                } else if current.isRequested {
                    try unregister()
                }
            }
        }

        static let live = SystemBoundary(
            status: { systemStatus() },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() })
    }

    static var isEnabled: Bool {
        isEnabled(using: .live)
    }

    static func isEnabled(using system: SystemBoundary) -> Bool {
        return system.isEnabled()
    }

    static var status: Status { status(using: .live) }

    static func status(using system: SystemBoundary) -> Status {
        system.readStatus?() ?? (system.isEnabled() ? .enabled : .disabled)
    }

    /// Only an explicit Settings action reaches registration. The caller must
    /// display failures and keep its toggle aligned with the observed status.
    @discardableResult
    static func set(_ enabled: Bool, using system: SystemBoundary = .live) -> Result<Status, Error> {
        do {
            try system.setEnabled(enabled)
            return .success(status(using: system))
        } catch {
            return .failure(error)
        }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    private static func systemStatus() -> Status {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
}
