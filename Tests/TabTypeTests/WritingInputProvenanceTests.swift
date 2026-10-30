import XCTest
@testable import TabType

final class WritingInputProvenanceTests: XCTestCase {
    func testMissingAccessibilityValueKeepsPredictionFallbackButCannotBecomeWriting() {
        let selected = ContextReader.selectInput(accessibilityBefore: nil,
                                                fallbackBuffer: "Synthetic fallback text", inputChars: 100)
        XCTAssertEqual(selected.input, "Synthetic fallback text")
        XCTAssertNil(selected.writingSnapshot)
    }

    func testEmptyAccessibilityValueCannotPromoteFallbackToWriting() {
        let selected = ContextReader.selectInput(accessibilityBefore: "",
                                                fallbackBuffer: "Synthetic unconfirmed input", inputChars: 100)
        XCTAssertEqual(selected.input, "Synthetic unconfirmed input")
        XCTAssertNil(selected.writingSnapshot)
    }

    func testConfirmedAccessibilityTextWinsForWritingEvenWhenFallbackIsNewer() {
        let selected = ContextReader.selectInput(accessibilityBefore: "Confirmed synthetic text",
                                                fallbackBuffer: "Confirmed synthetic text plus pending keys", inputChars: 100)
        XCTAssertEqual(selected.input, "Confirmed synthetic text")
        XCTAssertEqual(selected.writingSnapshot, "Confirmed synthetic text")
    }

    func testLaterPredictionReconciliationCannotChangeWritingSnapshot() {
        let selected = ContextReader.selectInput(accessibilityBefore: "Confirmed synthetic text",
                                                fallbackBuffer: "Pending synthetic text", inputChars: 100)
        var context = ContextReader.Result(dedupKey: selected.input, input: selected.input,
                                           afterCursor: "", focused: nil, window: nil, hasInput: true,
                                           writingSnapshot: selected.writingSnapshot)
        context.input = "Unconfirmed prediction reconciliation"
        XCTAssertEqual(context.writingSnapshot, "Confirmed synthetic text")
    }

    func testManualPredictionContextHasNoWritingProvenanceByDefault() {
        let context = ContextReader.Result(dedupKey: "synthetic", input: "Synthetic prediction fallback",
                                           afterCursor: "", focused: nil, window: nil, hasInput: true)
        XCTAssertNil(context.writingSnapshot)
    }

    func testWritingSnapshotUsesTheSameBoundedAccessibilityWindow() {
        let selected = ContextReader.selectInput(accessibilityBefore: "Synthetic AX sentence",
                                                fallbackBuffer: "Unconfirmed fallback", inputChars: 8)
        XCTAssertEqual(selected.input, "sentence")
        XCTAssertEqual(selected.writingSnapshot, "sentence")
    }
}
