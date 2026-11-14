import Foundation
import NoteCore
import Testing
@testable import SearchKit

private struct FixedTextRecognizer: HandwritingRecognizing {
    let recognitionVersion = 1
    let output: String?

    func text(for strokes: [StrokeRecord]) async -> String? {
        output
    }
}

private func cacheTestRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchKitCacheTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cacheTestPage() -> Page {
    var page = Page(id: UUID(), width: 612, height: 792, template: .blank)
    page.strokes = [
        StrokeRecord(
            id: UUID(),
            layerID: page.layers[0].id,
            tool: StrokeTool(engine: "metal", inkType: "pen", color: .black, width: 2),
            createdAt: Date(timeIntervalSince1970: 0),
            randomSeed: 1,
            points: [
                StrokePoint(
                    x: 1,
                    y: 2,
                    timeOffset: 0,
                    width: 2,
                    height: 2,
                    opacity: 1,
                    force: 0.5,
                    azimuth: 0,
                    altitude: 1.5,
                    secondaryScale: 1
                )
            ]
        )
    ]
    return page
}

private func cacheTestTypedPage(_ text: String) -> Page {
    var page = cacheTestPage()
    page.elements = [
        PageElement(
            id: UUID(),
            layerID: page.layers[0].id,
            frame: ElementFrame(x: 0, y: 0, width: 400, height: 80),
            zIndex: 0,
            updatedAt: Date(timeIntervalSince1970: 0),
            content: .text(text, fontName: "System", fontSize: 14, color: .black)
        )
    ]
    return page
}

/// Search results with and without the precomputed folded text must be identical,
/// including snippets and highlight ranges.
@Test func foldedTextCacheDoesNotChangeResults() async throws {
    let index = SearchIndex(root: try cacheTestRoot())
    let notebookID = UUID()
    let pages: [(Page, String, String)] = [
        (cacheTestPage(), "The force of gravity pulls things down and the forc is misread", ""),
        (cacheTestPage(), "Buy milk and eggs tomorrow morning", ""),
        (cacheTestPage(), "A needle in a haystack near the end", ""),
        (cacheTestTypedPage("Le Café du matin and naïveté"), "alpha beta gamma", ""),
        (cacheTestPage(), "spoken words about integrals", "the integral of x squared"),
        (cacheTestPage(), "Nothing relevant here at all", "")
    ]
    for (offset, entry) in pages.enumerated() {
        _ = try await index.update(
            page: entry.0,
            in: notebookID,
            pageIndex: offset + 1,
            transcriptText: entry.2,
            using: FixedTextRecognizer(output: entry.1)
        )
    }

    let queries = [
        "force", "forc", "formula", "cafe", "CAFÉ", "naive", "café matin",
        "\"gravity pulls\"", "alpha OR beta", "milk -bread", "needle",
        "zzz", "in", "the", "integral"
    ]
    for query in queries {
        let cached = await index.search(query)
        await index.setFoldedTextCacheEnabled(false)
        let uncached = await index.search(query)
        await index.setFoldedTextCacheEnabled(true)
        #expect(cached == uncached, Comment(rawValue: query))
    }
}

@Test func foldedTextCacheFollowsPageUpdates() async throws {
    let index = SearchIndex(root: try cacheTestRoot())
    let notebookID = UUID()
    var page = cacheTestPage()

    _ = try await index.update(
        page: page,
        in: notebookID,
        using: FixedTextRecognizer(output: "original wording")
    )
    #expect(await index.search("original").count == 1)

    page.strokes[0].createdAt = Date(timeIntervalSince1970: 99)
    _ = try await index.update(
        page: page,
        in: notebookID,
        using: FixedTextRecognizer(output: "replacement wording")
    )
    #expect(await index.search("original").isEmpty)
    #expect(await index.search("replacement").count == 1)
}
