import XCTest
@testable import TabType

private actor ContextReadProbe {
    private(set) var calls: [String] = []
    let screenText: ContextSourceReader.Content?
    let accessibleText: ContextSourceReader.Content?

    init(screenText: ContextSourceReader.Content?, accessibleText: ContextSourceReader.Content?) {
        self.screenText = screenText
        self.accessibleText = accessibleText
    }

    func readOCR() -> ContextSourceReader.Content? {
        calls.append("ocr")
        return screenText
    }

    func readAccessibility() -> ContextSourceReader.Content? {
        calls.append("accessibility")
        return accessibleText
    }
}

@MainActor
final class ContextSourceReaderTests: XCTestCase {
    func testDeniedScreenRecordingReturnsAccessibleConversationWithoutOCR() async {
        let transcript = "Synthetic writer: This conversation is a fixture. No private writing appears in this example."
        let probe = ContextReadProbe(
            screenText: ("Wrong source", "com.example.screen", "Synthetic screenshot text"),
            accessibleText: ("Synthetic Chat", "com.example.chat", transcript))

        let reading = await ContextSourceReader.read(
            screenRecordingAllowed: false, accessibilityEligible: true,
            ocr: { await probe.readOCR() }, accessibility: { await probe.readAccessibility() })

        XCTAssertEqual(reading, .init(source: .accessibility, app: "Synthetic Chat",
                                     bundleId: "com.example.chat", text: transcript))
        let calls = await probe.calls
        XCTAssertEqual(calls, ["accessibility"])
    }

    func testIneligibleAccessibilityNeverReadsATranscript() async {
        for permission in [false, true] {
            let probe = ContextReadProbe(
                screenText: nil,
                accessibleText: ("Synthetic Chat", "com.example.chat", String(repeating: "a", count: 80)))

            let reading = await ContextSourceReader.read(
                screenRecordingAllowed: permission, accessibilityEligible: false,
                ocr: { await probe.readOCR() }, accessibility: { await probe.readAccessibility() })

            XCTAssertNil(reading)
            let calls = await probe.calls
            XCTAssertEqual(calls, permission ? ["ocr"] : [])
        }
    }

    func testDeniedScreenRecordingRejectsMissingOrThinTranscript() async {
        let transcripts: [ContextSourceReader.Content?] = [
            nil, ("Synthetic Chat", "com.example.chat", String(repeating: "a", count: 79))
        ]
        for transcript in transcripts {
            let probe = ContextReadProbe(
                screenText: ("Synthetic Screen", "com.example.screen", "OCR fixture!"),
                accessibleText: transcript)

            let reading = await ContextSourceReader.read(
                screenRecordingAllowed: false, accessibilityEligible: true,
                ocr: { await probe.readOCR() }, accessibility: { await probe.readAccessibility() })

            XCTAssertNil(reading)
            let calls = await probe.calls
            XCTAssertEqual(calls, ["accessibility"])
        }
    }

    func testPermittedUsableOCRRemainsPreferred() async {
        let probe = ContextReadProbe(
            screenText: ("Synthetic Screen", "com.example.screen", "OCR fixture!"),
            accessibleText: ("Synthetic Chat", "com.example.chat", String(repeating: "a", count: 80)))

        let reading = await ContextSourceReader.read(
            screenRecordingAllowed: true, accessibilityEligible: true,
            ocr: { await probe.readOCR() }, accessibility: { await probe.readAccessibility() })

        XCTAssertEqual(reading, .init(source: .ocr, app: "Synthetic Screen",
                                     bundleId: "com.example.screen", text: "OCR fixture!"))
        let calls = await probe.calls
        XCTAssertEqual(calls, ["ocr"])
    }

    func testPermittedMissingOrThinOCRFallsBackToAccessibility() async {
        let screenReads: [ContextSourceReader.Content?] = [
            nil, ("Synthetic Screen", "com.example.screen", "OCR short!!")
        ]
        let transcript = String(repeating: "a", count: 80)
        for screenText in screenReads {
            let probe = ContextReadProbe(
                screenText: screenText,
                accessibleText: ("Synthetic Chat", "com.example.chat", transcript))

            let reading = await ContextSourceReader.read(
                screenRecordingAllowed: true, accessibilityEligible: true,
                ocr: { await probe.readOCR() }, accessibility: { await probe.readAccessibility() })

            XCTAssertEqual(reading, .init(source: .accessibility, app: "Synthetic Chat",
                                         bundleId: "com.example.chat", text: transcript))
            let calls = await probe.calls
            XCTAssertEqual(calls, ["ocr", "accessibility"])
        }
    }
}
