import Foundation
import Testing
@testable import TextDocKit

@Suite("Markdown round trip")
struct MarkdownRoundTripTests {
    @Test("Every supported block kind round-trips")
    func allSupportedBlocksRoundTrip() {
        let document = TextDocument(
            title: "Round trip",
            blocks: [
                TextBlock(kind: .heading(level: 2, text: "Notes")),
                TextBlock(kind: .paragraph(text: "Hello **world**")),
                TextBlock(kind: .bulletList(items: ["One", "Two"])),
                TextBlock(kind: .numberedList(items: ["First", "Second"])),
                TextBlock(kind: .quote(text: "Line one\nLine two")),
                TextBlock(kind: .code(text: "let x = 1\nprint(x)", language: "swift")),
                TextBlock(kind: .image(assetName: "diagram.png", width: 320)),
                TextBlock(kind: .divider),
                TextBlock(kind: .checklist(items: [
                    ChecklistItem(text: "Done", isChecked: true),
                    ChecklistItem(text: "Todo"),
                ])),
            ]
        )

        let markdown = MarkdownExporter().render(document)
        #expect(markdown.contains("## Notes"))
        #expect(markdown.contains("- One\n- Two"))
        #expect(markdown.contains("1. First\n2. Second"))
        #expect(markdown.contains("> Line one\n> Line two"))
        #expect(markdown.contains("```swift\nlet x = 1\nprint(x)\n```"))
        #expect(markdown.contains("![diagram.png](diagram.png \"width=320\")"))
        #expect(markdown.contains("\n---\n"))
        #expect(markdown.contains("- [x] Done\n- [ ] Todo"))

        let imported = MarkdownImporter().parse(markdown)
        assertSameBlocks(document.blocks, imported.blocks)
    }

    @Test("Code containing backticks uses a longer fence")
    func codeContainingBackticksUsesALongerFence() {
        let code = "let fence = \"```\""
        let document = TextDocument(
            blocks: [TextBlock(kind: .code(text: code, language: nil))]
        )

        let markdown = MarkdownExporter().render(document)
        #expect(markdown.hasPrefix("````\n"))
        #expect(markdown.contains("\n````\n"))

        let imported = MarkdownImporter().parse(markdown)
        #expect(imported.blocks.count == 1)
        #expect(imported.blocks.first?.kind == .code(text: code, language: nil))
    }

    @Test("Paragraph text that looks like Markdown survives")
    func paragraphTextThatLooksLikeMarkdownSurvives() {
        let text = "# not a heading\n- not a list\n---\n1. not numbered\n> not a quote\n\\# literal backslash"
        let document = TextDocument(
            blocks: [TextBlock(kind: .paragraph(text: text))]
        )

        let markdown = MarkdownExporter().render(document)
        #expect(markdown.contains("\\# not a heading"))

        let imported = MarkdownImporter().parse(markdown)
        #expect(imported.blocks.count == 1)
        #expect(imported.blocks.first?.kind == .paragraph(text: text))
    }

    @Test("Image names with spaces round-trip")
    func imageNamesWithSpacesRoundTrip() {
        let document = TextDocument(
            blocks: [TextBlock(kind: .image(assetName: "my photo.png", width: 200.5))]
        )

        let imported = MarkdownImporter().parse(MarkdownExporter().render(document))
        #expect(imported.blocks.first?.kind == .image(assetName: "my photo.png", width: 200.5))
    }

    @Test("Quotes preserve internal blank lines")
    func quoteWithBlankLineRoundTrips() {
        let document = TextDocument(
            blocks: [TextBlock(kind: .quote(text: "One\n\nTwo"))]
        )

        let imported = MarkdownImporter().parse(MarkdownExporter().render(document))
        #expect(imported.blocks.first?.kind == .quote(text: "One\n\nTwo"))
    }

    @Test("The title can be included as a heading")
    func titleCanBeIncluded() {
        let document = TextDocument(
            title: "My Notes",
            blocks: [TextBlock(kind: .paragraph(text: "Body"))]
        )

        let markdown = MarkdownExporter(includeTitle: true).render(document)
        #expect(markdown.hasPrefix("# My Notes\n\n"))
    }

    @Test("An empty document renders as empty Markdown")
    func emptyDocumentRoundTrips() {
        let document = TextDocument(title: "Empty")

        let markdown = MarkdownExporter().render(document)
        #expect(markdown.isEmpty)
        #expect(MarkdownImporter().parse(markdown).blocks.isEmpty)
    }

    private func assertSameBlocks(_ expected: [TextBlock], _ actual: [TextBlock]) {
        #expect(actual.count == expected.count)
        for (expectedBlock, actualBlock) in zip(expected, actual) {
            #expect(actualBlock.tag == expectedBlock.tag)
            switch (expectedBlock.kind, actualBlock.kind) {
            case let (.heading(expectedLevel, expectedText), .heading(actualLevel, actualText)):
                #expect(actualLevel == expectedLevel)
                #expect(actualText == expectedText)
            case let (.paragraph(expectedText), .paragraph(actualText)):
                #expect(actualText == expectedText)
            case let (.bulletList(expectedItems), .bulletList(actualItems)):
                #expect(actualItems == expectedItems)
            case let (.numberedList(expectedItems), .numberedList(actualItems)):
                #expect(actualItems == expectedItems)
            case let (.quote(expectedText), .quote(actualText)):
                #expect(actualText == expectedText)
            case let (.code(expectedText, expectedLanguage), .code(actualText, actualLanguage)):
                #expect(actualText == expectedText)
                #expect(actualLanguage == expectedLanguage)
            case let (.image(expectedName, expectedWidth), .image(actualName, actualWidth)):
                #expect(actualName == expectedName)
                #expect(actualWidth == expectedWidth)
            case (.divider, .divider):
                break
            case let (.checklist(expectedItems), .checklist(actualItems)):
                #expect(actualItems.map(\.text) == expectedItems.map(\.text))
                #expect(actualItems.map(\.isChecked) == expectedItems.map(\.isChecked))
            default:
                Issue.record("block kinds differ: \(expectedBlock.kind) vs \(actualBlock.kind)")
            }
        }
    }
}
