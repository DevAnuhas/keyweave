import AppKit
import XCTest
@testable import TabType

@MainActor
final class ClipboardOwnershipTests: XCTestCase {
    func testDelayedPasteRestorePreservesANewerUserCopy() {
        let board = NSPasteboard(name: .init("dev.anuhas.keyweave.test.\(UUID())"))
        defer { board.releaseGlobally() }
        board.setString("Original synthetic copy", forType: .string)
        var restore: (@MainActor () -> Void)?
        var pasted = false
        TextInserter.paste("Synthetic suggestion", on: board,
                           postPaste: { pasted = true }, scheduleRestore: { restore = $0 })
        XCTAssertTrue(pasted)
        XCTAssertTrue(TextInserter.isTemporaryPasteboardContent(on: board))
        board.clearContents()
        board.setString("Newer synthetic user copy", forType: .string)
        restore?()
        XCTAssertEqual(board.string(forType: .string), "Newer synthetic user copy")
        XCTAssertFalse(TextInserter.isTemporaryPasteboardContent(on: board))
    }

    func testUnchangedPasteRestoresAllOriginalFormats() {
        let board = NSPasteboard(name: .init("dev.anuhas.keyweave.test.\(UUID())"))
        defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("Synthetic rich text", forType: .string)
        original.setData(Data([1, 2, 3]), forType: .rtf)
        board.writeObjects([original])
        var restore: (@MainActor () -> Void)?
        TextInserter.paste("Synthetic suggestion", on: board,
                           postPaste: {}, scheduleRestore: { restore = $0 })
        restore?()
        XCTAssertEqual(board.string(forType: .string), "Synthetic rich text")
        XCTAssertEqual(board.data(forType: .rtf), Data([1, 2, 3]))
    }

    func testOverlappingPastesRestoreTheOriginalCopyRatherThanTheFirstSuggestion() {
        let board = NSPasteboard(name: .init("dev.anuhas.keyweave.test.\(UUID())"))
        defer { board.releaseGlobally() }
        board.setString("Original synthetic copy", forType: .string)
        var restores: [@MainActor () -> Void] = []
        TextInserter.paste("First suggestion", on: board, postPaste: {}, scheduleRestore: { restores.append($0) })
        TextInserter.paste("Second suggestion", on: board, postPaste: {}, scheduleRestore: { restores.append($0) })
        restores[0]()
        XCTAssertEqual(board.string(forType: .string), "Second suggestion")
        restores[1]()
        XCTAssertEqual(board.string(forType: .string), "Original synthetic copy")
    }
}
