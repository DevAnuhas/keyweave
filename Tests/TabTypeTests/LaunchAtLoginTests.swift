import XCTest
@testable import TabType

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    private struct RegistrationFailure: LocalizedError {
        var errorDescription: String? { "Synthetic registration denied" }
    }

    func testOnlyExplicitToggleChangesRegistration() {
        var enabled = false
        var reads = 0
        var writes: [Bool] = []
        let system = LaunchAtLogin.SystemBoundary(
            isEnabled: { reads += 1; return enabled },
            setEnabled: { enabled = $0; writes.append($0) })

        XCTAssertEqual(reads, 0)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertFalse(LaunchAtLogin.isEnabled(using: system))
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(writes.isEmpty)

        LaunchAtLogin.set(true, using: system)
        XCTAssertTrue(LaunchAtLogin.isEnabled(using: system))
        XCTAssertEqual(writes, [true])
        LaunchAtLogin.set(false, using: system)
        XCTAssertFalse(LaunchAtLogin.isEnabled(using: system))
        XCTAssertEqual(writes, [true, false])
    }

    func testFailedRegistrationReturnsErrorWithoutChangingObservedState() {
        var writes = 0
        let system = LaunchAtLogin.SystemBoundary(
            isEnabled: { false },
            setEnabled: { _ in writes += 1; throw RegistrationFailure() })

        switch LaunchAtLogin.set(true, using: system) {
        case .success: XCTFail("Registration failure must reach Settings")
        case .failure(let error): XCTAssertEqual(error.localizedDescription, "Synthetic registration denied")
        }
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(LaunchAtLogin.status(using: system), .disabled)
    }

    func testPendingApprovalCanBeCancelledWithoutRegisteringAgain() {
        var status = LaunchAtLogin.Status.requiresApproval
        var registers = 0
        var unregisters = 0
        let system = LaunchAtLogin.SystemBoundary(
            status: { status },
            register: { registers += 1 },
            unregister: { unregisters += 1; status = .disabled })

        XCTAssertEqual(LaunchAtLogin.status(using: system), .requiresApproval)
        XCTAssertFalse(LaunchAtLogin.isEnabled(using: system))
        XCTAssertEqual(registers, 0)
        XCTAssertEqual(unregisters, 0)
        LaunchAtLogin.set(true, using: system)
        XCTAssertEqual(registers, 0, "A pending registration already exists")
        LaunchAtLogin.set(false, using: system)
        XCTAssertEqual(unregisters, 1, "Turning off must cancel pending approval too")
        XCTAssertEqual(LaunchAtLogin.status(using: system), .disabled)
    }

    func testConfirmedRegistrationAndUnregistrationAreIdempotent() {
        var status = LaunchAtLogin.Status.disabled
        var registers = 0
        var unregisters = 0
        let system = LaunchAtLogin.SystemBoundary(
            status: { status },
            register: { registers += 1; status = .enabled },
            unregister: { unregisters += 1; status = .disabled })

        LaunchAtLogin.set(true, using: system)
        XCTAssertEqual(LaunchAtLogin.status(using: system), .enabled)
        LaunchAtLogin.set(true, using: system)
        XCTAssertEqual(registers, 1)
        LaunchAtLogin.set(false, using: system)
        LaunchAtLogin.set(false, using: system)
        XCTAssertEqual(LaunchAtLogin.status(using: system), .disabled)
        XCTAssertEqual(unregisters, 1)
    }

    func testUnavailableStatusReadsNeverAttemptRegistration() {
        var writes = 0
        let system = LaunchAtLogin.SystemBoundary(
            status: { .unavailable },
            register: { writes += 1 },
            unregister: { writes += 1 })

        for _ in 0..<2 {
            XCTAssertEqual(LaunchAtLogin.status(using: system), .unavailable)
            XCTAssertFalse(LaunchAtLogin.isEnabled(using: system))
        }
        XCTAssertEqual(writes, 0)
    }

    func testFailedUnregistrationPreservesEnabledStatus() {
        let system = LaunchAtLogin.SystemBoundary(
            status: { .enabled },
            register: { XCTFail("Disable must not register") },
            unregister: { throw RegistrationFailure() })

        switch LaunchAtLogin.set(false, using: system) {
        case .success: XCTFail("Unregistration failure must reach Settings")
        case .failure(let error): XCTAssertEqual(error.localizedDescription, "Synthetic registration denied")
        }
        XCTAssertEqual(LaunchAtLogin.status(using: system), .enabled)
    }
}
