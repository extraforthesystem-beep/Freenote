import Foundation
import NoteCore
import Testing
@testable import SearchKit

private func pdfTestRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchKitPDFTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func pdfTestPage(assetName: String, pageIndex: Int = 0) -> Page {
    var page = Page(id: UUID(), width: 612, height: 792, template: .blank)
    let layerID = page.layers[0].id
    page.elements = [
        PageElement(
            id: UUID(),
            layerID: layerID,
            frame: ElementFrame(x: 0, y: 0, width: 612, height: 792),
            zIndex: 0,
            updatedAt: Date(timeIntervalSince1970: 0),
            content: .pdfPage(assetName: assetName, pageIndex: pageIndex)
        )
    ]
    return page
}

private struct NoTextRecognizer: HandwritingRecognizing {
    let recognitionVersion = 1

    func text(for strokes: [StrokeRecord]) async -> String? {
        nil
    }
}

/// Holds a PDF extraction until the test has proved a search can run past it.
private actor ExtractionGate {
    private var runs = 0
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func run() async -> String {
        runs += 1
        started = true
        for waiter in startedWaiters { waiter.resume() }
        startedWaiters.removeAll()
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return "scanned page words"
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        released = true
        for waiter in releaseWaiters { waiter.resume() }
        releaseWaiters.removeAll()
    }

    var runCount: Int { runs }
}

@Test func searchReturnsWhilePDFExtractionIsInProgress() async throws {
    let root = try pdfTestRoot()
    let gate = ExtractionGate()
    let index = SearchIndex(root: root, pdfTextExtractor: { _, _ in await gate.run() })
    let page = pdfTestPage(assetName: "sha256-asset.pdf")
    let notebookID = UUID()

    let update = Task {
        try await index.update(
            page: page,
            in: notebookID,
            using: NoTextRecognizer(),
            assetsDirectory: root
        )
    }
    // A safety release so a regression fails the timing assertion rather than
    // leaving the suite waiting on the gate forever.
    let safety = Task {
        try? await Task.sleep(for: .seconds(3))
        await gate.release()
    }

    await gate.waitUntilStarted()
    let clock = ContinuousClock()
    let start = clock.now
    let hits = await index.search("scanned")
    let elapsed = clock.now - start
    // The record is not stored yet, so there is nothing to find; the point is
    // that the search was not queued behind the extraction.
    #expect(elapsed < .seconds(1))
    #expect(hits.isEmpty)

    await gate.release()
    _ = try await update.value
    safety.cancel()
    #expect(await gate.runCount == 1)
    #expect(await index.search("scanned").count == 1)
}

@Test func cancelledPDFExtractionStoresNothing() async throws {
    let root = try pdfTestRoot()
    let gate = ExtractionGate()
    let index = SearchIndex(root: root, pdfTextExtractor: { _, _ in await gate.run() })
    let page = pdfTestPage(assetName: "sha256-asset.pdf")
    let notebookID = UUID()

    let update = Task {
        try await index.update(
            page: page,
            in: notebookID,
            using: NoTextRecognizer(),
            assetsDirectory: root
        )
    }
    let safety = Task {
        try? await Task.sleep(for: .seconds(3))
        await gate.release()
    }

    await gate.waitUntilStarted()
    update.cancel()
    await gate.release()
    let stored = try await update.value
    safety.cancel()
    #expect(stored == nil)
    #expect(await index.record(for: notebookID, pageID: page.id) == nil)
}

private actor ExtractionCounter {
    private(set) var calls = 0

    func extract(url: URL, pageIndex: Int) async -> String {
        calls += 1
        return "asset \(url.lastPathComponent) page \(pageIndex)"
    }
}

@Test func cachedPDFTextIsReusedAcrossPages() async throws {
    let root = try pdfTestRoot()
    let counter = ExtractionCounter()
    let index = SearchIndex(root: root, pdfTextExtractor: { url, pageIndex in
        await counter.extract(url: url, pageIndex: pageIndex)
    })
    let notebookID = UUID()
    let first = pdfTestPage(assetName: "sha256-asset.pdf", pageIndex: 2)
    let second = pdfTestPage(assetName: "sha256-asset.pdf", pageIndex: 2)

    _ = try await index.update(
        page: first,
        in: notebookID,
        using: NoTextRecognizer(),
        assetsDirectory: root
    )
    _ = try await index.update(
        page: second,
        in: notebookID,
        using: NoTextRecognizer(),
        assetsDirectory: root
    )

    #expect(await counter.calls == 1)
    #expect(await index.search("asset").count == 2)

    // A different page of the same asset is a different cache entry.
    let other = pdfTestPage(assetName: "sha256-asset.pdf", pageIndex: 3)
    _ = try await index.update(
        page: other,
        in: notebookID,
        using: NoTextRecognizer(),
        assetsDirectory: root
    )
    #expect(await counter.calls == 2)
}
