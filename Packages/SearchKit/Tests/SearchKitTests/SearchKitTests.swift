import Foundation
import NoteCore
import Testing
@testable import SearchKit

private actor FakeRecognizer: HandwritingRecognizing {
    nonisolated let recognitionVersion: Int
    private(set) var calls = 0
    private let output: String?

    init(text: String?, recognitionVersion: Int = 1) {
        self.output = text
        self.recognitionVersion = recognitionVersion
    }

    func text(for strokes: [StrokeRecord]) async -> String? {
        calls += 1
        return output
    }
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeStroke(index: Int) -> StrokeRecord {
    StrokeRecord(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID(),
        layerID: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        tool: StrokeTool(engine: "pencilkit", inkType: "pen", color: .black, width: 2),
        createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
        randomSeed: UInt32(index),
        points: [
            StrokePoint(
                x: 10 + Double(index),
                y: 20,
                timeOffset: 0,
                width: 2,
                height: 2,
                opacity: 1,
                force: 0.5,
                azimuth: 0,
                altitude: 1.5707963267948966,
                secondaryScale: 1
            )
        ]
    )
}

private func makePage(id: UUID = UUID(), strokeCount: Int = 2) -> Page {
    var page = Page(
        id: id,
        width: 612,
        height: 792,
        template: .blank
    )
    page.strokes = (0..<strokeCount).map(makeStroke(index:))
    return page
}

@Test func updateStoresTextAndSearchFindsIt() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookID = UUID()
    let page = makePage()
    let recognizer = FakeRecognizer(text: "Buy milk and eggs tomorrow")

    let record = try await index.update(page: page, in: notebookID, using: recognizer)
    #expect(record?.text == "Buy milk and eggs tomorrow")
    #expect(record?.recognitionVersion == 1)

    let hits = await index.search("milk")
    #expect(hits.count == 1)
    #expect(hits.first?.notebookID == notebookID)
    #expect(hits.first?.pageID == page.id)
    #expect(hits.first?.matchedTermCount == 1)
    #expect(hits.first?.snippet.contains("milk") == true)
}

@Test func searchIgnoresCaseAndDiacritics() async throws {
    let index = SearchIndex(root: try makeRoot())
    let page = makePage()
    _ = try await index.update(page: page, in: UUID(), using: FakeRecognizer(text: "Le Café du matin"))

    #expect(await index.search("cafe").count == 1)
    #expect(await index.search("CAFÉ").count == 1)
    #expect(await index.search("cafe matin").count == 1)
}

@Test func searchRequiresEveryTerm() async throws {
    let index = SearchIndex(root: try makeRoot())
    let page = makePage()
    _ = try await index.update(page: page, in: UUID(), using: FakeRecognizer(text: "Buy milk and eggs"))

    #expect(await index.search("milk eggs").count == 1)
    #expect(await index.search("milk bread").isEmpty)
    #expect(await index.search("   ").isEmpty)
    #expect(await index.search("").isEmpty)
}

@Test func indexPersistsAcrossInstances() async throws {
    let root = try makeRoot()
    let notebookID = UUID()
    let page = makePage()
    let first = SearchIndex(root: root)
    _ = try await first.update(page: page, in: notebookID, using: FakeRecognizer(text: "Persisted wording"))

    let second = SearchIndex(root: root)
    try await second.load()
    let record = await second.record(for: notebookID, pageID: page.id)
    #expect(record?.text == "Persisted wording")

    let hits = await second.search("persisted")
    #expect(hits.count == 1)
    #expect(hits.first?.pageID == page.id)
}

@Test func freshnessFollowsInkAndSkipsRecognition() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookID = UUID()
    var page = makePage()
    let recognizer = FakeRecognizer(text: "first", recognitionVersion: 3)

    _ = try await index.update(page: page, in: notebookID, using: recognizer)
    #expect(await index.isFresh(notebookID: notebookID, pageID: page.id, page: page, recognizerVersion: 3))

    page.strokes.append(makeStroke(index: 99))
    #expect(await index.isFresh(notebookID: notebookID, pageID: page.id, page: page, recognizerVersion: 3) == false)

    let updated = try await index.update(page: page, in: notebookID, using: recognizer)
    #expect(updated != nil)
    #expect(await index.isFresh(notebookID: notebookID, pageID: page.id, page: page, recognizerVersion: 3))
    #expect(await recognizer.calls == 2)

    let skipped = try await index.update(page: page, in: notebookID, using: recognizer)
    #expect(skipped == nil)
    #expect(await recognizer.calls == 2)
}

@Test func recognitionVersionChangeReindexes() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookID = UUID()
    let page = makePage()

    let old = FakeRecognizer(text: "old text", recognitionVersion: 1)
    _ = try await index.update(page: page, in: notebookID, using: old)

    let new = FakeRecognizer(text: "new text", recognitionVersion: 2)
    let record = try await index.update(page: page, in: notebookID, using: new)
    #expect(record?.recognitionVersion == 2)
    #expect(record?.text == "new text")
    #expect(await new.calls == 1)
    #expect(await index.search("old").isEmpty)
    #expect(await index.search("new").count == 1)
}

@Test func removePageAndNotebook() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookA = UUID()
    let notebookB = UUID()
    let pageA = makePage()
    let pageB = makePage()
    let pageC = makePage()

    _ = try await index.update(page: pageA, in: notebookA, using: FakeRecognizer(text: "alpha"))
    _ = try await index.update(page: pageB, in: notebookA, using: FakeRecognizer(text: "beta"))
    _ = try await index.update(page: pageC, in: notebookB, using: FakeRecognizer(text: "gamma"))

    try await index.remove(pageID: pageB.id, notebookID: notebookA)
    #expect(await index.record(for: notebookA, pageID: pageB.id) == nil)
    #expect(await index.search("beta").isEmpty)
    #expect(await index.search("alpha").count == 1)

    try await index.removeNotebook(notebookA)
    #expect(await index.record(for: notebookA, pageID: pageA.id) == nil)
    let remaining = await index.allRecords()
    #expect(remaining.count == 1)
    #expect(remaining.first?.notebookID == notebookB)
    #expect(await index.search("gamma").count == 1)
}

@Test func corruptIndexFileThrows() async throws {
    let root = try makeRoot()
    try Data("this is not json".utf8).write(to: root.appendingPathComponent("search-index.json"))
    let index = SearchIndex(root: root)

    await #expect(throws: SearchIndexError.self) {
        try await index.load()
    }
}

@Test func missingIndexFileIsEmpty() async throws {
    let index = SearchIndex(root: try makeRoot())
    try await index.load()
    #expect(await index.allRecords().isEmpty)
    #expect(await index.search("anything").isEmpty)
}

@Test func emptyRecognitionIsStoredWithoutHits() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookID = UUID()
    let page = makePage()

    let record = try await index.update(page: page, in: notebookID, using: FakeRecognizer(text: nil))
    #expect(record?.text.isEmpty == true)

    let stored = await index.record(for: notebookID, pageID: page.id)
    #expect(stored?.text.isEmpty == true)
    #expect(await index.search("anything").isEmpty)
    #expect(await index.isFresh(notebookID: notebookID, pageID: page.id, page: page, recognizerVersion: 1))
}

@Test func snippetIsOneLineAroundTheFirstMatch() async throws {
    let index = SearchIndex(root: try makeRoot())
    let filler = String(repeating: "lorem ipsum ", count: 30)
    let text = "\(filler)\n\(filler)needle in the haystack\n\(filler)"
    let page = makePage()
    _ = try await index.update(page: page, in: UUID(), using: FakeRecognizer(text: text))

    let hits = await index.search("haystack")
    let snippet = try #require(hits.first?.snippet)
    #expect(snippet.contains("haystack"))
    #expect(!snippet.contains("\n"))
    #expect(snippet.hasPrefix("…"))
    #expect(snippet.hasSuffix("…"))
}

@Test func typedTextBoxesAreSearchableAndReindex() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookID = UUID()
    var page = makePage(strokeCount: 0)
    let layerID = page.layers[0].id
    page.elements = [
        PageElement(
            id: UUID(),
            layerID: layerID,
            frame: ElementFrame(x: 20, y: 20, width: 200, height: 60),
            zIndex: 0,
            updatedAt: Date(),
            content: .text("Quarterly meeting notes", fontName: "System", fontSize: 14, color: .black)
        )
    ]

    _ = try await index.update(page: page, in: notebookID, using: FakeRecognizer(text: nil))
    #expect(await index.search("quarterly").count == 1)

    page.elements[0].content = .text("Holiday plans", fontName: "System", fontSize: 14, color: .black)
    _ = try await index.update(page: page, in: notebookID, using: FakeRecognizer(text: nil))
    #expect(await index.search("quarterly").isEmpty)
    #expect(await index.search("holiday").count == 1)
}

// MARK: - Hit metadata, snippets and sources

private func highlightedText(_ hit: SearchHit) -> String? {
    guard let range = hit.matchRange else { return nil }
    return String(hit.snippet[range])
}

private func typedPage(_ text: String, strokeCount: Int = 0) -> Page {
    var page = makePage(strokeCount: strokeCount)
    let layerID = page.layers[0].id
    page.elements = [
        PageElement(
            id: UUID(),
            layerID: layerID,
            frame: ElementFrame(x: 20, y: 20, width: 200, height: 60),
            zIndex: 0,
            updatedAt: Date(),
            content: .text(text, fontName: "System", fontSize: 14, color: .black)
        )
    ]
    return page
}

@Test func hitCarriesPageNumberAndSource() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookID = UUID()
    let page = makePage()
    _ = try await index.update(
        page: page,
        in: notebookID,
        pageIndex: 3,
        using: FakeRecognizer(text: "Buy milk and eggs")
    )

    let hit = try #require(await index.search("milk").first)
    #expect(hit.pageIndex == 3)
    #expect(hit.pageLabel == "p.3")
    #expect(hit.source == .handwriting)
    #expect(hit.notebookID == notebookID)
    #expect(hit.pageID == page.id)
}

@Test func typedTextIsTaggedWithItsOwnSource() async throws {
    let index = SearchIndex(root: try makeRoot())
    let page = typedPage("Quarterly meeting notes")
    _ = try await index.update(page: page, in: UUID(), pageIndex: 2, using: FakeRecognizer(text: nil))

    let hit = try #require(await index.search("quarterly").first)
    #expect(hit.source == .typedText)
    #expect(hit.pageIndex == 2)
}

@Test func onePageCanHitOncePerSource() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookID = UUID()
    let page = typedPage("Meeting notes", strokeCount: 2)
    _ = try await index.update(page: page, in: notebookID, pageIndex: 1, using: FakeRecognizer(text: "Notes from the meeting"))

    let hits = await index.search("notes")
    #expect(hits.count == 2)
    #expect(Set(hits.map(\.source)) == [.handwriting, .typedText])
    #expect(Set(hits.map(\.id)).count == 2)
}

@Test func sourceSectionTitlesMatchTheSearchUI() {
    #expect(PageTextSource.handwriting.sectionTitle == "Written Notes")
    #expect(PageTextSource.typedText.sectionTitle == "Text")
    #expect(PageTextSource.pdf.sectionTitle == "PDFs")
}

@Test func snippetHighlightIsCorrectAtPageStart() async throws {
    let index = SearchIndex(root: try makeRoot())
    let text = "needle in a haystack " + String(repeating: "lorem ipsum ", count: 20)
    _ = try await index.update(page: makePage(), in: UUID(), using: FakeRecognizer(text: text))

    let hit = try #require(await index.search("needle").first)
    #expect(hit.snippet.hasPrefix("needle"))
    #expect(!hit.snippet.hasPrefix("…"))
    #expect(!hit.snippet.contains("\n"))
    #expect(highlightedText(hit) == "needle")
}

@Test func snippetHighlightIsCorrectInTheMiddle() async throws {
    let index = SearchIndex(root: try makeRoot())
    let filler = String(repeating: "lorem ipsum ", count: 40)
    let text = "\(filler)needle in the haystack\(filler)"
    _ = try await index.update(page: makePage(), in: UUID(), using: FakeRecognizer(text: text))

    let hit = try #require(await index.search("haystack").first)
    #expect(hit.snippet.hasPrefix("…"))
    #expect(hit.snippet.hasSuffix("…"))
    #expect(hit.snippet.contains("needle in the haystack"))
    #expect(highlightedText(hit) == "haystack")
    #expect(hit.snippet.count <= 95)
}

@Test func snippetHighlightIsCorrectAtPageEnd() async throws {
    let index = SearchIndex(root: try makeRoot())
    let text = String(repeating: "lorem ipsum ", count: 40) + "the needle"
    _ = try await index.update(page: makePage(), in: UUID(), using: FakeRecognizer(text: text))

    let hit = try #require(await index.search("needle").first)
    #expect(!hit.snippet.hasSuffix("…"))
    #expect(hit.snippet.hasSuffix("needle"))
    #expect(highlightedText(hit) == "needle")
}

@Test func snippetShowsTheFirstOfSeveralMatches() async throws {
    let index = SearchIndex(root: try makeRoot())
    let text = "alpha beta alpha beta alpha"
    _ = try await index.update(page: makePage(), in: UUID(), using: FakeRecognizer(text: text))

    let hits = await index.search("alpha")
    // One hit per page-and-source, not one per occurrence.
    #expect(hits.count == 1)
    let hit = try #require(hits.first)
    #expect(highlightedText(hit) == "alpha")
    // The matched range is the first occurrence.
    #expect(hit.snippet.distance(from: hit.snippet.startIndex, to: try #require(hit.matchRange).lowerBound) == 0)
}

@Test func snippetsHandleUnicodeAndDiacritics() async throws {
    let index = SearchIndex(root: try makeRoot())
    let filler = String(repeating: "lorem ipsum ", count: 20)
    let text = "🔥 \(filler)Café au lait and naïveté\(filler) 🔥"
    _ = try await index.update(page: makePage(), in: UUID(), using: FakeRecognizer(text: text))

    let cafe = try #require(await index.search("cafe").first)
    #expect(highlightedText(cafe) == "Café")
    #expect(cafe.snippet.contains("Café au lait"))

    let naive = try #require(await index.search("naive").first)
    #expect(highlightedText(naive) == "naïve")
}

@Test func tolerantPrefixMatchFindsShortRecognition() async throws {
    let index = SearchIndex(root: try makeRoot())
    _ = try await index.update(
        page: makePage(),
        in: UUID(),
        using: FakeRecognizer(text: "the forc of gravity pulls things down")
    )

    // The query is longer than the misrecognised word on the page.
    let hit = try #require(await index.search("force").first)
    #expect(highlightedText(hit) == "forc")

    // And the shorter query still finds both spellings.
    #expect(await index.search("forc").count == 1)

    // The tolerant relation needs real words, not a stray substring.
    #expect(await index.search("formula").isEmpty)

    // A three-letter word that happens to prefix the query is not a match.
    _ = try await index.update(
        page: makePage(),
        in: UUID(),
        using: FakeRecognizer(text: "the cat sat on a mat")
    )
    #expect(await index.search("theme").isEmpty)
}

@Test func searchCanBeScopedToOneNotebook() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookA = UUID()
    let notebookB = UUID()
    _ = try await index.update(page: makePage(), in: notebookA, pageIndex: 1, using: FakeRecognizer(text: "milk and bread"))
    _ = try await index.update(page: makePage(), in: notebookB, pageIndex: 1, using: FakeRecognizer(text: "milk and eggs"))

    #expect(await index.search("milk").count == 2)
    let scoped = await index.search("milk", in: notebookA)
    #expect(scoped.count == 1)
    #expect(scoped.first?.notebookID == notebookA)
}

@Test func movingAPageRefreshesItsNumberWithoutRecognisingAgain() async throws {
    let index = SearchIndex(root: try makeRoot())
    let notebookID = UUID()
    let page = makePage()
    let recognizer = FakeRecognizer(text: "unchanged words")

    _ = try await index.update(page: page, in: notebookID, pageIndex: 1, using: recognizer)
    let moved = try await index.update(page: page, in: notebookID, pageIndex: 7, using: recognizer)
    #expect(moved != nil)
    #expect(await recognizer.calls == 1)

    let hit = try #require(await index.search("unchanged").first)
    #expect(hit.pageIndex == 7)
}

