/// Selects usable surrounding text without owning platform access. Callers must
/// enforce context consent before providing the lazy readers; neither reader has
/// a live default. OCR remains preferred when Screen Recording is available.
enum ContextSourceReader {
    typealias Content = (app: String, bundleId: String, text: String)

    enum Source: String, Sendable {
        case ocr
        case accessibility = "ax transcript"
    }

    struct Reading: Equatable, Sendable {
        let source: Source
        let app: String
        let bundleId: String
        let text: String
    }

    static func read(
        screenRecordingAllowed: Bool,
        accessibilityEligible: Bool,
        ocr: @Sendable () async -> Content?,
        accessibility: @Sendable () async -> Content?
    ) async -> Reading? {
        if screenRecordingAllowed, let content = await ocr(), content.text.count >= 12 {
            return Reading(source: .ocr, app: content.app, bundleId: content.bundleId, text: content.text)
        }
        if accessibilityEligible, let content = await accessibility(), content.text.count >= 80 {
            return Reading(source: .accessibility, app: content.app, bundleId: content.bundleId, text: content.text)
        }
        return nil
    }
}
