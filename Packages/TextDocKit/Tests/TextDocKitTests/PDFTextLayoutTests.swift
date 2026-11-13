import Foundation
import Testing
@testable import TextDocKit

@Suite("PDF text layout")
struct PDFTextLayoutTests {
    private let options = PDFTextLayout.Options(
        pageSize: PDFTextLayout.PageSize(width: 400, height: 300),
        margins: PDFTextLayout.Insets(top: 20, leading: 20, bottom: 20, trailing: 20),
        blockSpacing: 10
    )

    private func paragraph(_ text: String) -> TextBlock {
        TextBlock(kind: .paragraph(text: text))
    }

    @Test("An empty document has one page and no frames")
    func emptyDocumentHasOnePage() {
        let plan = PDFTextLayout.plan(
            for: TextDocument(),
            options: options,
            measureText: { _, _, _ in 100 },
            imageHeight: { _ in 100 }
        )

        #expect(plan.pageCount == 1)
        #expect(plan.frames.isEmpty)
        #expect(plan.pageSize == PDFTextLayout.PageSize(width: 400, height: 300))
    }

    @Test("A block that would overflow starts a new page")
    func overflowStartsANewPage() {
        let document = TextDocument(blocks: [
            paragraph("One"),
            paragraph("Two"),
            paragraph("Three"),
        ])

        let plan = PDFTextLayout.plan(
            for: document,
            options: options,
            measureText: { _, _, _ in 100 },
            imageHeight: { _ in 0 }
        )

        #expect(plan.pageCount == 2)
        #expect(plan.frames.map(\.pageIndex) == [0, 0, 1])
        #expect(plan.frames[0].rect == PDFTextLayout.Rect(x: 20, y: 20, width: 360, height: 100))
        #expect(plan.frames[1].rect.y == 130)
        #expect(plan.frames[2].rect == PDFTextLayout.Rect(x: 20, y: 20, width: 360, height: 100))
        #expect(plan.frames(onPage: 0).count == 2)
        #expect(plan.frames(onPage: 1).count == 1)
    }

    @Test("Headings, paragraphs, quotes and code use the measurer")
    func textBlocksUseTheMeasurer() {
        let document = TextDocument(blocks: [
            TextBlock(kind: .heading(level: 1, text: "H")),
            TextBlock(kind: .paragraph(text: "P")),
            TextBlock(kind: .quote(text: "Q")),
            TextBlock(kind: .code(text: "C", language: "swift")),
        ])
        var measured: [String] = []

        let plan = PDFTextLayout.plan(
            for: document,
            options: options,
            measureText: { _, text, _ in
                measured.append(text)
                return 10
            },
            imageHeight: { _ in 0 }
        )

        #expect(measured == ["H", "P", "Q", "C"])
        #expect(plan.frames.count == 4)
    }

    @Test("Lists are measured item by item at the indented width")
    func listsAreMeasuredItemByItem() {
        let document = TextDocument(blocks: [
            TextBlock(kind: .bulletList(items: ["A", "B", "C"])),
        ])
        var measured: [(String, Double)] = []

        let plan = PDFTextLayout.plan(
            for: document,
            options: options,
            measureText: { _, text, width in
                measured.append((text, width))
                return 40
            },
            imageHeight: { _ in 0 }
        )

        #expect(measured.map(\.0) == ["A", "B", "C"])
        #expect(measured.allSatisfy { $0.1 == 336 })
        #expect(plan.frames.first?.rect.height == 120)
        #expect(plan.frames.first?.kind == .bulletList)
    }

    @Test("Checklists are measured from item text")
    func checklistsAreMeasuredFromItemText() {
        let document = TextDocument(blocks: [
            TextBlock(kind: .checklist(items: [
                ChecklistItem(text: "One"),
                ChecklistItem(text: "Two", isChecked: true),
            ])),
        ])
        var measured: [String] = []

        let plan = PDFTextLayout.plan(
            for: document,
            options: options,
            measureText: { _, text, _ in
                measured.append(text)
                return 30
            },
            imageHeight: { _ in 0 }
        )

        #expect(measured == ["One", "Two"])
        #expect(plan.frames.first?.rect.height == 60)
        #expect(plan.frames.first?.kind == .checklist)
    }

    @Test("Images use the supplied height, not the text measurer")
    func imagesUseSuppliedHeight() {
        let image = TextBlock(kind: .image(assetName: "photo.png", width: 200))
        let document = TextDocument(blocks: [image])
        var textMeasureCalls = 0

        let plan = PDFTextLayout.plan(
            for: document,
            options: options,
            measureText: { _, _, _ in
                textMeasureCalls += 1
                return 999
            },
            imageHeight: { block in
                block.tag == .image ? 150 : 0
            }
        )

        #expect(textMeasureCalls == 0)
        #expect(plan.frames.first?.rect.height == 150)
        #expect(plan.frames.first?.kind == .image)
    }

    @Test("Dividers use the configured height")
    func dividersUseConfiguredHeight() {
        let document = TextDocument(blocks: [TextBlock(kind: .divider)])

        let plan = PDFTextLayout.plan(
            for: document,
            options: options,
            measureText: { _, _, _ in 0 },
            imageHeight: { _ in 0 }
        )

        #expect(plan.frames.first?.rect.height == 1)
        #expect(plan.frames.first?.kind == .divider)
    }

    @Test("A block taller than the page is placed alone and overflows")
    func oversizedBlockIsPlacedAloneOnAPage() {
        let document = TextDocument(blocks: [
            paragraph("Tall"),
            paragraph("Next"),
        ])

        let plan = PDFTextLayout.plan(
            for: document,
            options: options,
            measureText: { _, text, _ in text == "Tall" ? 400 : 50 },
            imageHeight: { _ in 0 }
        )

        #expect(plan.frames[0].pageIndex == 0)
        #expect(plan.frames[0].rect.height == 400)
        #expect(plan.frames[1].pageIndex == 1)
        #expect(plan.frames[1].rect.y == 20)
        #expect(plan.pageCount == 2)
    }
}
