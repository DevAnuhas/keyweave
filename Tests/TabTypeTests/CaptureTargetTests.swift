import CoreGraphics
import XCTest
@testable import TabType

final class CaptureTargetTests: XCTestCase {
    private let target = WindowCaptureTarget(pid: 123, bundleId: "synthetic.writer",
                                             frame: CGRect(x: 100, y: 100, width: 600, height: 400))

    func testMissingIntendedWindowNeverCapturesAnotherApplicationOrWindow() {
        XCTAssertNil(target.selectedWindowID(in: [
            .init(id: 1, pid: 987, bundleId: "synthetic.other", frame: target.frame, onScreen: true)
        ]))
        XCTAssertNil(target.selectedWindowID(in: [
            .init(id: 2, pid: 123, bundleId: "synthetic.writer", frame: CGRect(x: 900, y: 100, width: 600, height: 400), onScreen: true)
        ]))
        XCTAssertNil(target.selectedWindowID(in: [
            .init(id: 3, pid: 123, bundleId: "synthetic.writer", frame: CGRect(x: 0, y: 0, width: 800, height: 600), onScreen: true)
        ]), "Equal centers do not identify the same window")
    }

    func testOnlyUnambiguousMatchingOwnerAndGeometryCanBeSelected() {
        let intended = WindowCaptureTarget.Window(id: 42, pid: 123, bundleId: "synthetic.writer",
                                                  frame: target.frame.insetBy(dx: 2, dy: 2), onScreen: true)
        let unrelated = WindowCaptureTarget.Window(id: 99, pid: 987, bundleId: "synthetic.other",
                                                  frame: target.frame, onScreen: true)
        XCTAssertEqual(target.selectedWindowID(in: [unrelated, intended]), 42)
        XCTAssertNil(target.selectedWindowID(in: [intended, .init(id: 43, pid: 123, bundleId: "synthetic.writer", frame: target.frame, onScreen: true)]))
        XCTAssertNil(target.selectedWindowID(in: [.init(id: 42, pid: 123, bundleId: "synthetic.writer", frame: intended.frame, onScreen: false)]))
        XCTAssertNil(target.selectedWindowID(in: [.init(id: 42, pid: 123, bundleId: "synthetic.impostor", frame: intended.frame, onScreen: true)]))
    }
}
