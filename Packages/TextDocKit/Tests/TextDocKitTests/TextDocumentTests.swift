import Foundation
import Testing
@testable import TextDocKit

@Suite("Text document editing")
struct TextDocumentTests {
    private func paragraph(_ text: String) -> TextBlock {
        TextBlock(kind: .paragraph(text: text))
    }

    @Test("Insert clamps the index and preserves order")
    func insertClampsIndex() {
        var document = TextDocument(title: "Test")
        document.insert(paragraph("A"), at: 0)
        document.insert(paragraph("B"), at: 1)
        document.insert(paragraph("C"), at: 99)
        document.insert(paragraph("First"), at: -3)

        #expect(document.blocks.map(\.text) == ["First", "A", "B", "C"])
    }

    @Test("Remove works by id and by index and ignores invalid requests")
    func removeByIDAndIndex() {
        let a = paragraph("A")
        let b = paragraph("B")
        let c = paragraph("C")
        var document = TextDocument(blocks: [a, b, c])

        let removedB = document.removeBlock(id: b.id)
        #expect(removedB?.text == "B")
        #expect(document.blocks.map(\.text) == ["A", "C"])

        let removedA = document.removeBlock(at: 0)
        #expect(removedA?.text == "A")
        #expect(document.blocks.map(\.text) == ["C"])

        let missingIndex = document.removeBlock(at: 10)
        #expect(missingIndex == nil)

        let missingID = document.removeBlock(id: UUID())
        #expect(missingID == nil)
        #expect(document.blocks.map(\.text) == ["C"])
    }

    @Test("Move reorders blocks and clamps the destination")
    func moveBlockReorders() {
        let a = paragraph("A")
        let b = paragraph("B")
        let c = paragraph("C")
        let d = paragraph("D")
        var document = TextDocument(blocks: [a, b, c, d])

        let firstMove = document.moveBlock(from: 0, to: 2)
        #expect(firstMove)
        #expect(document.blocks.map(\.text) == ["B", "C", "A", "D"])

        let secondMove = document.moveBlock(id: d.id, to: 0)
        #expect(secondMove)
        #expect(document.blocks.map(\.text) == ["D", "B", "C", "A"])

        let badSource = document.moveBlock(from: 99, to: 0)
        #expect(badSource == false)

        let missingID = document.moveBlock(id: UUID(), to: 0)
        #expect(missingID == false)
        #expect(document.blocks.map(\.text) == ["D", "B", "C", "A"])
    }

    @Test("plainText joins block text without list markers")
    func plainTextSkipsNonTextBlocks() {
        let document = TextDocument(
            title: "Doc",
            blocks: [
                TextBlock(kind: .heading(level: 1, text: "Title")),
                TextBlock(kind: .paragraph(text: "First line\nSecond line")),
                TextBlock(kind: .bulletList(items: ["A", "B"])),
                TextBlock(kind: .numberedList(items: ["One"])),
                TextBlock(kind: .quote(text: "Quoted")),
                TextBlock(kind: .code(text: "let x = 1", language: "swift")),
                TextBlock(kind: .image(assetName: "photo.png", width: 200)),
                TextBlock(kind: .divider),
                TextBlock(kind: .checklist(items: [
                    ChecklistItem(text: "Done", isChecked: true),
                    ChecklistItem(text: "Todo"),
                ])),
            ]
        )

        #expect(
            document.plainText
                == "Title\nFirst line\nSecond line\nA\nB\nOne\nQuoted\nlet x = 1\nDone\nTodo"
        )
    }

    @Test("A document round-trips through Codable")
    func documentRoundTripsThroughJSON() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.125)
        let document = TextDocument(
            title: "Round trip",
            blocks: [
                TextBlock(kind: .heading(level: 2, text: "Heading")),
                TextBlock(
                    kind: .paragraph(text: "Hello"),
                    style: TextStyle(isBold: true, alignment: .center, fontSize: 18)
                ),
                TextBlock(kind: .checklist(items: [
                    ChecklistItem(text: "Done", isChecked: true),
                ])),
            ],
            createdAt: date,
            updatedAt: date
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(TextDocument.self, from: data)

        #expect(decoded == document)
    }

    @Test("Every block kind round-trips through Codable")
    func everyBlockKindRoundTripsThroughCodable() throws {
        let document = TextDocument(
            title: "Every block",
            blocks: [
                TextBlock(kind: .heading(level: 3, text: "Heading")),
                TextBlock(kind: .paragraph(text: "Paragraph")),
                TextBlock(kind: .bulletList(items: ["One", "Two"])),
                TextBlock(kind: .numberedList(items: ["First", "Second"])),
                TextBlock(kind: .quote(text: "Quote")),
                TextBlock(kind: .code(text: "let x = 1", language: "swift")),
                TextBlock(kind: .image(assetName: "photo.png", width: 240)),
                TextBlock(kind: .divider),
                TextBlock(kind: .checklist(items: [
                    ChecklistItem(text: "Done", isChecked: true),
                    ChecklistItem(text: "Todo"),
                ])),
            ]
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(TextDocument.self, from: data)

        #expect(decoded == document)
    }

    @Test("touch updates updatedAt only")
    func touchUpdatesUpdatedAt() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let touched = Date(timeIntervalSince1970: 1_700_000_500)
        var document = TextDocument(createdAt: created)

        #expect(document.updatedAt == created)
        document.touch(at: touched)
        #expect(document.updatedAt == touched)
        #expect(document.createdAt == created)
    }
}
