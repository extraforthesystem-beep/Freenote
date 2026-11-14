import CoreText
import Foundation
import NoteCore
import Testing
@testable import SearchKit

private func makeIndex(_ texts: [String]) async throws -> SearchIndex {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchQueryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let index = SearchIndex(root: root)
    for (offset, text) in texts.enumerated() {
        _ = try await index.update(page: inkPage(), in: UUID(), pageIndex: offset + 1, using: StubRecognizer(output: text))
    }
    return index
}

private struct StubRecognizer: HandwritingRecognizing {
    let output: String
    var recognitionVersion: Int { 1 }
    func text(for strokes: [StrokeRecord]) async -> String? { output }
}

private func inkPage() -> Page {
    var page = Page(id: UUID(), width: 612, height: 792, template: .blank)
    page.strokes = [
        StrokeRecord(
            id: UUID(),
            layerID: UUID(),
            tool: StrokeTool(engine: "pencilkit", inkType: "pen", color: .black, width: 2),
            createdAt: Date(timeIntervalSince1970: 0),
            randomSeed: 1,
            points: [StrokePoint(x: 10, y: 20, timeOffset: 0, width: 2, height: 2, opacity: 1, force: 0.5, azimuth: 0, altitude: 1.57, secondaryScale: 1)]
        )
    ]
    return page
}

@Test func parsesWordsPhrasesOrAndExclusions() {
    let query = SearchQuery(#"milk "fresh bread" eggs OR butter -cheese -"blue sky""#)
    #expect(query.groups == [
        [.init("milk")],
        [.init("fresh bread", isPhrase: true)],
        [.init("eggs"), .init("butter")],
    ])
    #expect(query.excluded == [.init("cheese"), .init("blue sky", isPhrase: true)])
    #expect(query.positiveTerms == ["milk", "fresh bread", "eggs", "butter"])
}

@Test func parserToleratesStrayOperators() {
    #expect(SearchQuery("OR milk OR").groups == [[.init("milk")]])
    #expect(SearchQuery("e-mail - x").groups == [[.init("e-mail")], [.init("x")]])
    #expect(SearchQuery("\u{201C}curly quotes\u{201D}").groups == [[.init("curly quotes", isPhrase: true)]])
    #expect(SearchQuery(#""unclosed phrase"#).groups == [[.init("unclosed phrase", isPhrase: true)]])
    #expect(SearchQuery("-only").isEmpty)
    #expect(SearchQuery("   ").isEmpty)
}

@Test func phraseNeedsTheWordsInOrder() async throws {
    let index = try await makeIndex(["buy fresh bread today", "bread was not fresh"])
    let hits = await index.search(SearchQuery(#""fresh bread""#), filter: .all)
    #expect(hits.map(\.pageIndex) == [1])
}

@Test func phraseMatchesAcrossALineBreak() async throws {
    let index = try await makeIndex(["buy fresh\nbread today"])
    #expect(await index.search(SearchQuery(#""fresh bread""#), filter: .all).count == 1)
}

@Test func orMatchesEitherSide() async throws {
    let index = try await makeIndex(["milk", "butter", "cheese"])
    let hits = await index.search(SearchQuery("milk OR butter"), filter: .all)
    #expect(Set(hits.map(\.pageIndex)) == [1, 2])
}

@Test func exclusionRemovesPages() async throws {
    let index = try await makeIndex(["milk and cheese", "milk and eggs"])
    let hits = await index.search(SearchQuery("milk -cheese"), filter: .all)
    #expect(hits.map(\.pageIndex) == [2])
}

@Test func filterLimitsSources() async throws {
    let index = try await makeIndex(["milk"])
    #expect(await index.search(SearchQuery("milk"), filter: SearchFilter(sources: [.typedText, .pdf])).isEmpty)
    #expect(await index.search(SearchQuery("milk"), filter: SearchFilter(sources: [.handwriting])).count == 1)
    #expect(await index.search(SearchQuery("milk"), filter: SearchFilter(sources: [])).isEmpty)
}

@Test func titleMatchUsesTheSameSyntax() {
    #expect(SearchQuery("physics -draft").matches("Physics notes"))
    #expect(!SearchQuery("physics -draft").matches("Physics draft"))
    #expect(SearchQuery("maths OR physics").matches("Physics"))
    #expect(!SearchQuery("-draft").matches("Anything"))
}

// MARK: - Edit date filter

private func pageEdited(at date: Date, text: String) -> Page {
    var page = Page(id: UUID(), width: 612, height: 792, template: .blank)
    page.elements = [
        PageElement(
            id: UUID(),
            layerID: page.layers[0].id,
            frame: ElementFrame(x: 40, y: 50, width: 200, height: 60, rotation: 15),
            zIndex: 0,
            updatedAt: date,
            content: .text(text, fontName: "System", fontSize: 14, color: .black)
        )
    ]
    return page
}

@Test func dateFilterUsesTheNewestEditOnThePage() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchQueryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let index = SearchIndex(root: root)
    let now = Date()
    _ = try await index.update(page: pageEdited(at: now.addingTimeInterval(-3600), text: "milk"), in: UUID(), pageIndex: 1, using: StubRecognizer(output: ""))
    _ = try await index.update(page: pageEdited(at: now.addingTimeInterval(-40 * 86_400), text: "milk"), in: UUID(), pageIndex: 2, using: StubRecognizer(output: ""))

    let week = SearchFilter(editedAfter: SearchDateRange.pastWeek.start(relativeTo: now))
    #expect(await index.search(SearchQuery("milk"), filter: week).map(\.pageIndex) == [1])
    #expect(await index.search(SearchQuery("milk"), filter: .all).count == 2)
}

@Test func dateRangesStartWhereTheyShould() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let calendar = Calendar(identifier: .gregorian)
    #expect(SearchDateRange.anyTime.start(relativeTo: now) == nil)
    #expect(SearchDateRange.today.start(relativeTo: now, calendar: calendar) == calendar.startOfDay(for: now))
    #expect(SearchDateRange.pastWeek.start(relativeTo: now, calendar: calendar) == now.addingTimeInterval(-7 * 86_400))
}

// MARK: - Page marks

@Test func typedTextMarksTheMatchingBoxWithItsRotation() {
    let page = pageEdited(at: Date(), text: "Buy fresh bread")
    let marks = PageMatchLocator.typedTextMarks(for: SearchQuery("bread"), in: page)
    #expect(marks == [PageMatchMark(rect: CGRect(x: 40, y: 50, width: 200, height: 60), rotation: 15)])
    #expect(PageMatchLocator.typedTextMarks(for: SearchQuery("cheese"), in: page).isEmpty)
}

@Test func pdfMarksLandInsideTheDrawnPage() throws {
    let assets = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchQueryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try makeTextPDF("Hello quarterly report", at: assets.appendingPathComponent("doc.pdf"))

    var page = Page(id: UUID(), width: 612, height: 792, template: .blank)
    // Drawn at half size, offset on the page.
    page.elements = [
        PageElement(
            id: UUID(),
            layerID: page.layers[0].id,
            frame: ElementFrame(x: 100, y: 100, width: 306, height: 396),
            zIndex: 0,
            updatedAt: Date(),
            content: .pdfPage(assetName: "doc.pdf", pageIndex: 0)
        )
    ]
    let marks = PageMatchLocator.pdfMarks(for: SearchQuery("quarterly"), in: page, assetsDirectory: assets)
    let mark = try #require(marks.first)
    #expect(marks.count == 1)
    let drawn = CGRect(x: 100, y: 100, width: 306, height: 396)
    #expect(drawn.contains(mark.rect))
    // The text sits near the top of the PDF page, so near the top of the element.
    #expect(mark.rect.minY < 100 + 396 / 2)
}

@Test func pdfMarksStopWhenTheTaskIsCancelled() async throws {
    let assets = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchQueryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try makeTextPDF("Hello quarterly report", at: assets.appendingPathComponent("doc.pdf"))

    var page = Page(id: UUID(), width: 612, height: 792, template: .blank)
    page.elements = [
        PageElement(
            id: UUID(),
            layerID: page.layers[0].id,
            frame: ElementFrame(x: 100, y: 100, width: 306, height: 396),
            zIndex: 0,
            updatedAt: Date(),
            content: .pdfPage(assetName: "doc.pdf", pageIndex: 0)
        )
    ]

    // A page flip abandons the extraction: it must not read the PDF at all.
    let task = Task { () -> [PageMatchMark] in
        withUnsafeCurrentTask { $0?.cancel() }
        return PageMatchLocator.pdfMarks(for: SearchQuery("quarterly"), in: page, assetsDirectory: assets)
    }
    let marks = await task.value
    #expect(marks.isEmpty)
}

/// A one-page US Letter PDF with `text` near the top-left.
private func makeTextPDF(_ text: String, at url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
    context.beginPDFPage(nil)
    let attributed = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 24, nil),
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 72, y: 700)
    CTLineDraw(line, context)
    context.endPDFPage()
    context.closePDF()
}
