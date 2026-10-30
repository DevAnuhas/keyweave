import AppKit
import TabTypeKit
import XCTest
@testable import TabType

@MainActor
private final class ContextConsentFixture {
    var enabled = true
    var generation = UUID()
    var target: WindowCaptureTarget? = WindowCaptureTarget(
        pid: 123, bundleId: "synthetic.writer", frame: CGRect(x: 100, y: 100, width: 600, height: 400),
        title: "Synthetic document", host: nil, fieldID: 1)
}

@MainActor
final class ContextConsentTests: XCTestCase {
    func testOffContextAndAppearanceNeverTouchPlatformBoundaries() async {
        var operations: [String] = []
        let provider = ScreenContextProvider(platform: .init(
            preflightPermission: { operations.append("preflight"); return true },
            requestPermission: { operations.append("request"); return true },
            focusedWindowTitle: { operations.append("title"); return "Synthetic document" }),
            contextEnabled: { false }, appearanceEnabled: { false })
        XCTAssertFalse(provider.hasPermission())
        XCTAssertFalse(provider.requestPermission())
        provider.refreshIfStale()
        provider.selfTest()
        XCTAssertEqual(provider.contextText(for: "synthetic.writer", cap: 100), "")
        provider.invalidate()
        let probe = GhostAppearanceProbe(appearanceEnabled: { false }, permissionAllowed: {
            operations.append("appearance permission"); return true
        })
        probe.refresh(caretRect: CGRect(x: 300, y: 200, width: 1, height: 20))
        XCTAssertNil(probe.current)
        probe.invalidate()
        let cache = FieldFitCache(screenCaptureAllowed: {
            operations.append("fit permission"); return true
        }, appearanceEnabled: { false })
        XCTAssertNil(cache.cached(key: "synthetic"))
        let fit = await cache.fit(caret: CGRect(x: 300, y: 200, width: 1, height: 20), fieldFrame: nil,
                                  key: "synthetic", lineText: "Synthetic text", verbose: true)
        XCTAssertNil(fit)
        XCTAssertEqual(operations, [])
    }

    func testAnExplicitContextOrAppearanceOptInAllowsThePermissionAction() {
        for appearance in [false, true] {
            var requests = 0
            let provider = ScreenContextProvider(platform: .init(
                preflightPermission: { false }, requestPermission: { requests += 1; return true }),
                contextEnabled: { !appearance }, appearanceEnabled: { appearance })
            XCTAssertFalse(provider.hasPermission())
            XCTAssertTrue(provider.requestPermission())
            XCTAssertEqual(requests, 1)
        }
    }

    func testContextCaptureAcceptsOnlyTheConsentedUnchangedTarget() async throws {
        let fixture = ContextConsentFixture()
        let target = try XCTUnwrap(fixture.target)
        let reading = await ScreenContextProvider.captureFocusedWindow(
            pid: target.pid, fieldText: "Synthetic input", cropMode: .caretCropped,
            caretRect: nil, windowFrame: target.frame,
            capture: { ("Synthetic Writer", "synthetic.writer", "Synthetic surrounding document") },
            consent: { fixture.enabled }, currentTarget: { fixture.target })
        XCTAssertEqual(reading?.2, "Synthetic surrounding document")

        let stale = await ScreenContextProvider.captureFocusedWindow(
            pid: target.pid, fieldText: "Synthetic input", cropMode: .caretCropped,
            caretRect: nil, windowFrame: target.frame,
            capture: {
                await MainActor.run { fixture.target?.fieldID = 2 }
                return ("Synthetic Writer", "synthetic.writer", "Stale surrounding document")
            }, consent: { fixture.enabled }, currentTarget: { fixture.target })
        XCTAssertNil(stale)
    }

    func testContextCaptureDropsResultWhenConsentIsRevokedDuringCapture() async throws {
        let fixture = ContextConsentFixture()
        let target = try XCTUnwrap(fixture.target)
        let result = await ScreenContextProvider.captureFocusedWindow(
            pid: target.pid, fieldText: "", cropMode: .caretCropped,
            caretRect: nil, windowFrame: target.frame,
            capture: {
                await MainActor.run { fixture.enabled = false }
                return ("Synthetic Writer", "synthetic.writer", "Synthetic surrounding document")
            }, consent: { fixture.enabled }, currentTarget: { fixture.target })
        XCTAssertNil(result)
    }

    func testOffDirectCaptureDoesNotEvenAcquireATarget() async {
        var targetReads = 0
        let result = await ScreenContextProvider.captureFocusedWindow(
            pid: nil, fieldText: "", cropMode: .caretCropped, caretRect: nil, windowFrame: nil,
            capture: { XCTFail("No capture while off"); return nil }, consent: { false },
            currentTarget: { targetReads += 1; return nil })
        XCTAssertNil(result)
        let image = await GhostAppearanceProbe.captureScaled(
            rect: CGRect(x: 100, y: 100, width: 60, height: 20), consent: { false },
            currentTarget: { targetReads += 1; return nil },
            capture: { _, _ in XCTFail("No capture while off"); return nil })
        XCTAssertNil(image)
        XCTAssertEqual(targetReads, 0)
    }

    func testOffOnCycleCannotReuseAnEarlierCapture() async throws {
        let fixture = ContextConsentFixture()
        let target = try XCTUnwrap(fixture.target)
        let result = await ScreenContextProvider.captureFocusedWindow(
            pid: target.pid, fieldText: "", cropMode: .caretCropped, caretRect: nil, windowFrame: target.frame,
            capture: {
                await MainActor.run {
                    fixture.enabled = false
                    fixture.generation = UUID()
                    fixture.enabled = true
                }
                return ("Synthetic Writer", "synthetic.writer", "Expired synthetic context")
            }, consent: { fixture.enabled }, currentTarget: { fixture.target },
            currentGeneration: { fixture.generation })
        XCTAssertNil(result)
    }

    func testAppearanceRejectsAChangedTargetAndPixelsOutsideItsWindow() async throws {
        let fixture = ContextConsentFixture()
        let context = try XCTUnwrap(CGContext(data: nil, width: 60, height: 20, bitsPerComponent: 8,
                                            bytesPerRow: 60 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let valid = await GhostAppearanceProbe.captureScaled(
            rect: CGRect(x: 120, y: 120, width: 60, height: 20),
            consent: { fixture.enabled }, currentTarget: { fixture.target },
            capture: { _, _ in (image, 1) })
        XCTAssertEqual(valid?.image.width, 60)
        let stale = await GhostAppearanceProbe.captureScaled(
            rect: CGRect(x: 120, y: 120, width: 60, height: 20),
            consent: { fixture.enabled }, currentTarget: { fixture.target },
            capture: { _, _ in
                await MainActor.run { fixture.target?.title = "Different synthetic window" }
                return (image, 1)
            })
        XCTAssertNil(stale)
        let outside = await GhostAppearanceProbe.captureScaled(
            rect: CGRect(x: 10, y: 10, width: 60, height: 20),
            consent: { fixture.enabled }, currentTarget: { fixture.target },
            capture: { _, _ in XCTFail("No pixels outside intended window"); return (image, 1) })
        XCTAssertNil(outside)
    }
}
