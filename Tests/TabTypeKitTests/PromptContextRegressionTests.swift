import XCTest
@testable import TabTypeKit

final class PromptContextRegressionTests: XCTestCase {
    func testConversationRetainsClipboardAlongsideTheAuthorsReply() {
        let context = PromptContext(
            typedText: "I can", authorName: "Mira Synthetic",
            screenText: "Ari: Could you review the outline?", isConversation: true,
            clipboard: "The review is due Friday.")
        XCTAssertEqual(PromptAssembler(template: .base).assemble(context),
                       "Copied text: The review is due Friday.\n\nAri: Could you review the outline?\nMira: I can")
    }
}
