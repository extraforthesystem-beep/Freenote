import Foundation
import NoteCore
import Testing
@testable import SearchKit

private actor TranscriptFakeRecognizer: HandwritingRecognizing {
    nonisolated let recognitionVersion = 1
    private(set) var calls = 0

    func text(for strokes: [StrokeRecord]) async -> String? {
        calls += 1
        return "written words"
    }
}

private func makeTranscriptRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchKitTranscriptTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func transcriptPage() -> Page {
    var page = Page(id: UUID(), width: 595, height: 842, template: .blank)
    page.strokes = [
        StrokeRecord(
            id: UUID(),
            layerID: page.layers[0].id,
            tool: StrokeTool(engine: "pencilkit", inkType: "pen", color: .black, width: 2),
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            randomSeed: 1,
            points: [
                StrokePoint(
                    x: 10,
                    y: 20,
                    timeOffset: 0,
                    width: 2,
                    height: 2,
                    opacity: 1,
                    force: 0.5,
                    azimuth: 0,
                    altitude: 1.5707963267948966,
                    secondaryScale: 1
                ),
            ]
        ),
    ]
    return page
}

@Test func transcriptTextIsSearchableAsItsOwnSource() async throws {
    let index = SearchIndex(root: try makeTranscriptRoot())
    let page = transcriptPage()
    let notebookID = UUID()

    let record = try await index.update(
        page: page,
        in: notebookID,
        transcriptText: "The derivative is a rate of change",
        using: TranscriptFakeRecognizer()
    )

    #expect(record?.segments.contains { $0.source == .transcript && $0.text.contains("derivative") } == true)
    #expect(record?.text == "written words\nThe derivative is a rate of change")

    let hits = await index.search("derivative")
    #expect(hits.count == 1)
    #expect(hits.first?.source == .transcript)
    #expect(hits.first?.pageID == page.id)

    // The filter keeps a transcript hit out when that source is off.
    let filtered = await index.search(
        SearchQuery("derivative"),
        filter: SearchFilter(sources: [.handwriting])
    )
    #expect(filtered.isEmpty)
}

@Test func editedTranscriptReindexesWithoutNewInk() async throws {
    let index = SearchIndex(root: try makeTranscriptRoot())
    let page = transcriptPage()
    let notebookID = UUID()
    let recognizer = TranscriptFakeRecognizer()

    _ = try await index.update(
        page: page,
        in: notebookID,
        transcriptText: "first attempt",
        using: recognizer
    )
    _ = try await index.update(
        page: page,
        in: notebookID,
        transcriptText: "corrected words",
        using: recognizer
    )

    #expect(await recognizer.calls == 2)
    #expect(await index.search("attempt").isEmpty)
    #expect(await index.search("corrected").count == 1)
}

@Test func emptyTranscriptLeavesNoSegment() async throws {
    let index = SearchIndex(root: try makeTranscriptRoot())
    let record = try await index.update(
        page: transcriptPage(),
        in: UUID(),
        transcriptText: "   \n",
        using: TranscriptFakeRecognizer()
    )

    #expect(record?.segments.contains { $0.source == .transcript } == false)
}
