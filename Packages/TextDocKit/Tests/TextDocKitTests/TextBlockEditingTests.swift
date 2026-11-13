import Foundation
import Testing
@testable import TextDocKit

@Suite("Block editing")
struct TextBlockEditingTests {
    private func paragraph(_ text: String) -> TextBlock {
        TextBlock(kind: .paragraph(text: text))
    }

    // MARK: - Splitting

    @Test("Return in a paragraph splits at the caret into a following block")
    func splitsParagraphAtCaret() throws {
        let first = paragraph("HelloWorld")
        var document = TextDocument(blocks: [first, paragraph("Tail")])

        let split = document.splitBlock(id: first.id, offset: 5)
        let caret = try #require(split)

        #expect(document.blocks.count == 3)
        #expect(document.blocks[0].text == "Hello")
        #expect(document.blocks[1].text == "World")
        #expect(document.blocks[2].text == "Tail")
        #expect(caret.blockID == document.blocks[1].id)
        #expect(caret.itemIndex == 0)
        #expect(caret.offset == 0)
    }

    @Test("Return at the end of a paragraph inserts an empty block after it")
    func splitsAtEnd() throws {
        let only = paragraph("Done")
        var document = TextDocument(blocks: [only])

        let split = document.splitBlock(id: only.id, offset: 99)
        let caret = try #require(split)

        #expect(document.blocks.map(\.text) == ["Done", ""])
        #expect(caret.blockID == document.blocks[1].id)
        #expect(caret.offset == 0)
    }

    @Test("A heading continues as a paragraph")
    func splitsHeading() {
        let heading = TextBlock(kind: .heading(level: 2, text: "TitleBody"))
        var document = TextDocument(blocks: [heading])

        _ = document.splitBlock(id: heading.id, offset: 5)

        #expect(document.blocks.count == 2)
        guard case let .heading(level, text) = document.blocks[0].kind else {
            Issue.record("Expected the first block to stay a heading")
            return
        }
        #expect(level == 2)
        #expect(text == "Title")
        #expect(document.blocks[1].text == "Body")
        guard case .paragraph = document.blocks[1].kind else {
            Issue.record("Expected the continuation to be a paragraph")
            return
        }
    }

    @Test("A bullet list continues as a bullet list")
    func splitsBulletList() throws {
        let list = TextBlock(kind: .bulletList(items: ["One", "TwoThree", "Four"]))
        var document = TextDocument(blocks: [list, paragraph("After")])

        let split = document.splitBlock(id: list.id, itemIndex: 1, offset: 3)
        let caret = try #require(split)

        #expect(document.blocks.count == 3)
        guard case let .bulletList(head) = document.blocks[0].kind else {
            Issue.record("Expected the first block to stay a bullet list")
            return
        }
        #expect(head == ["One", "Two"])
        guard case let .bulletList(tail) = document.blocks[1].kind else {
            Issue.record("Expected the continuation to be a bullet list")
            return
        }
        #expect(tail == ["Three", "Four"])
        #expect(document.blocks[2].text == "After")
        #expect(caret.blockID == document.blocks[1].id)
        #expect(caret.itemIndex == 0)
    }

    @Test("A numbered list continues as a numbered list")
    func splitsNumberedList() {
        let list = TextBlock(kind: .numberedList(items: ["First"]))
        var document = TextDocument(blocks: [list])

        _ = document.splitBlock(id: list.id, itemIndex: 0, offset: 5)

        guard case let .numberedList(head) = document.blocks[0].kind else {
            Issue.record("Expected a numbered list")
            return
        }
        guard case let .numberedList(tail) = document.blocks[1].kind else {
            Issue.record("Expected a numbered list continuation")
            return
        }
        #expect(head == ["First"])
        #expect(tail == [""])
    }

    @Test("Return on an empty list item turns it into a paragraph")
    func emptyItemEndsList() throws {
        let list = TextBlock(kind: .bulletList(items: ["One", ""]))
        var document = TextDocument(blocks: [list])

        let split = document.splitBlock(id: list.id, itemIndex: 1, offset: 0)
        let caret = try #require(split)

        guard case let .bulletList(items) = document.blocks[0].kind else {
            Issue.record("Expected the list to keep its first item")
            return
        }
        #expect(items == ["One"])
        guard case .paragraph = document.blocks[1].kind else {
            Issue.record("Expected a paragraph after the list")
            return
        }
        #expect(caret.blockID == document.blocks[1].id)
    }

    @Test("Return on the only, empty list item converts the block to a paragraph")
    func lastEmptyItemBecomesParagraph() throws {
        let list = TextBlock(kind: .checklist(items: [ChecklistItem(text: "")]))
        var document = TextDocument(blocks: [list])

        let split = document.splitBlock(id: list.id, itemIndex: 0, offset: 0)
        let caret = try #require(split)

        #expect(document.blocks.count == 1)
        guard case .paragraph = document.blocks[0].kind else {
            Issue.record("Expected the checklist to become a paragraph")
            return
        }
        #expect(caret.blockID == list.id)
    }

    @Test("Splitting a checklist keeps identity and checked state above the caret")
    func splitsChecklist() {
        let first = ChecklistItem(text: "Buy milk")
        let second = ChecklistItem(text: "CallSam")
        let list = TextBlock(kind: .checklist(items: [first, second]))
        var document = TextDocument(blocks: [list])

        _ = document.splitBlock(id: list.id, itemIndex: 1, offset: 4)

        guard case let .checklist(head) = document.blocks[0].kind else {
            Issue.record("Expected a checklist")
            return
        }
        guard case let .checklist(tail) = document.blocks[1].kind else {
            Issue.record("Expected a checklist continuation")
            return
        }
        #expect(head.map(\.text) == ["Buy milk", "Call"])
        #expect(head[0].id == first.id)
        #expect(tail.map(\.text) == ["Sam"])
        #expect(tail[0].isChecked == false)
    }

    @Test("Code blocks keep their newlines instead of splitting")
    func codeDoesNotSplit() {
        let code = TextBlock(kind: .code(text: "let x = 1", language: "swift"))
        var document = TextDocument(blocks: [code])

        let split = document.splitBlock(id: code.id, offset: 3)

        #expect(split == nil)
        #expect(document.blocks.count == 1)
    }

    // MARK: - Merging

    @Test("Backspace at offset zero merges a paragraph into the one above")
    func mergesParagraphBackward() throws {
        let first = paragraph("Hello")
        let second = paragraph("World")
        var document = TextDocument(blocks: [first, second])

        let merge = document.mergeBlockBackward(id: second.id)
        let caret = try #require(merge)

        #expect(document.blocks.count == 1)
        #expect(document.blocks[0].text == "HelloWorld")
        #expect(caret.blockID == first.id)
        #expect(caret.offset == 5)
    }

    @Test("Backspace at the start of a heading makes it a paragraph first")
    func headingBecomesParagraph() throws {
        let first = paragraph("Above")
        let heading = TextBlock(kind: .heading(level: 1, text: "Title"))
        var document = TextDocument(blocks: [first, heading])

        let merge = document.mergeBlockBackward(id: heading.id)
        let caret = try #require(merge)

        #expect(document.blocks.count == 2)
        guard case let .paragraph(text) = document.blocks[1].kind else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(text == "Title")
        #expect(caret.blockID == heading.id)
        #expect(caret.offset == 0)
    }

    @Test("Backspace at the start of the first list item makes it a paragraph")
    func firstListItemBecomesParagraph() throws {
        let list = TextBlock(kind: .bulletList(items: ["One", "Two"]))
        var document = TextDocument(blocks: [list])

        let merge = document.mergeBlockBackward(id: list.id, itemIndex: 0)
        let caret = try #require(merge)

        #expect(document.blocks.count == 1)
        #expect(document.blocks[0].text == "One\nTwo")
        #expect(caret.blockID == list.id)
    }

    @Test("Backspace at the start of a later item joins it onto the item above")
    func mergesListItemBackward() throws {
        let list = TextBlock(kind: .numberedList(items: ["Hello", "World"]))
        var document = TextDocument(blocks: [list])

        let merge = document.mergeBlockBackward(id: list.id, itemIndex: 1)
        let caret = try #require(merge)

        guard case let .numberedList(items) = document.blocks[0].kind else {
            Issue.record("Expected a numbered list")
            return
        }
        #expect(items == ["HelloWorld"])
        #expect(caret.itemIndex == 0)
        #expect(caret.offset == 5)
    }

    @Test("Backspace at the start of a paragraph appends it to a list above")
    func mergesParagraphIntoList() throws {
        let list = TextBlock(kind: .bulletList(items: ["One"]))
        let after = paragraph("Two")
        var document = TextDocument(blocks: [list, after])

        let merge = document.mergeBlockBackward(id: after.id)
        let caret = try #require(merge)

        #expect(document.blocks.count == 1)
        guard case let .bulletList(items) = document.blocks[0].kind else {
            Issue.record("Expected a bullet list")
            return
        }
        #expect(items == ["One", "Two"])
        #expect(caret.itemIndex == 1)
        #expect(caret.offset == 0)
    }

    @Test("Backspace at the very start of the document does nothing")
    func mergeAtDocumentStartDoesNothing() {
        let first = paragraph("Only")
        var document = TextDocument(blocks: [first])

        let merge = document.mergeBlockBackward(id: first.id)

        #expect(merge == nil)
        #expect(document.blocks.count == 1)
    }

    // MARK: - Convert and insert

    @Test("Converting a paragraph to a checklist splits its lines into items")
    func convertsToChecklist() {
        let block = paragraph("One\nTwo")
        var document = TextDocument(blocks: [block])

        let converted = document.convertBlock(id: block.id, to: .checklist)

        #expect(converted)
        guard case let .checklist(items) = document.blocks[0].kind else {
            Issue.record("Expected a checklist")
            return
        }
        #expect(items.map(\.text) == ["One", "Two"])
        #expect(items.allSatisfy { !$0.isChecked })
    }

    @Test("Converting a list to a paragraph joins its items with newlines")
    func convertsListToParagraph() {
        let block = TextBlock(kind: .bulletList(items: ["A", "B"]))
        var document = TextDocument(blocks: [block])

        let converted = document.convertBlock(id: block.id, to: .paragraph)

        #expect(converted)
        #expect(document.blocks[0].text == "A\nB")
    }

    @Test("Inserting after a block puts the new block in place, not at the end")
    func insertsAfterBlock() throws {
        let first = paragraph("A")
        var document = TextDocument(blocks: [first, paragraph("B")])

        let inserted = document.insertBlock(after: first.id, kind: .paragraph(text: ""))
        let caret = try #require(inserted)

        #expect(document.blocks.map(\.text) == ["A", "", "B"])
        #expect(caret.blockID == document.blocks[1].id)
    }

    @Test("Editing helpers ignore unknown blocks")
    func ignoresUnknownIDs() {
        var document = TextDocument(blocks: [paragraph("A")])
        let missing = UUID()

        let split = document.splitBlock(id: missing, offset: 0)
        let merge = document.mergeBlockBackward(id: missing)
        let inserted = document.insertBlock(after: missing, kind: .paragraph(text: ""))
        let converted = document.convertBlock(id: missing, to: .paragraph)

        #expect(split == nil)
        #expect(merge == nil)
        #expect(inserted == nil)
        #expect(converted == false)
    }
}
