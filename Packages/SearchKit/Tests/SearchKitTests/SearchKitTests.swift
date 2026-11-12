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
