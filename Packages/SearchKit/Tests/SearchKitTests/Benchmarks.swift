import Foundation
import NoteCore
import Testing
@testable import SearchKit

/// Off by default so the suite stays fast:
/// `NOTEAPP_BENCH=1 swift test -c release --filter SearchIndexBenchmarks`.
/// Each benchmark writes its median to `NOTEAPP_BENCH_DIR` (default: the
/// temporary directory) so results can be compared without console logging.
@Suite(
    "SearchIndexBenchmarks",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["NOTEAPP_BENCH"] == "1")
)
struct SearchIndexBenchmarks {
    @Test func BenchmarkContentHash() {
        let page = benchmarkPage(strokeCount: 2_000, pointsPerStroke: 100)
        var samples: [Duration] = []
        for _ in 0..<5 {
            let clock = ContinuousClock()
            let start = clock.now
            _ = SearchIndex.contentHash(of: page)
            samples.append(clock.now - start)
        }
        recordBenchmark("contentHash-2000x100", medianMilliseconds(samples))
    }

    @Test func BenchmarkSearch() async throws {
        let recognizer = BenchmarkRecognizer()
        let index = SearchIndex(root: try benchmarkRoot())
        let notebookID = UUID()
        await index.beginDeferringWrites()
        for offset in 0..<2_000 {
            var page = benchmarkPage(strokeCount: 2, pointsPerStroke: 2)
            let layerID = page.layers[0].id
            page.elements = [
                PageElement(
                    id: UUID(),
                    layerID: layerID,
                    frame: ElementFrame(x: 0, y: 0, width: 600, height: 80),
                    zIndex: 0,
                    updatedAt: Date(timeIntervalSince1970: 0),
                    content: .text(
                        benchmarkText(page: offset, rare: offset % 50 == 0),
                        fontName: "System",
                        fontSize: 14,
                        color: .black
                    )
                )
            ]
            _ = try await index.update(
                page: page,
                in: notebookID,
                pageIndex: offset + 1,
                transcriptText: benchmarkText(page: offset + 1, rare: false),
                using: recognizer
            )
        }
        try await index.endDeferringWrites()

        // `zebrafish` misses every segment and takes the tolerant prefix path
        // on all 6,000. `seminar` is on 40 pages. `lecture` is on every page, so
        // it also builds 6,000 result snippets.
        for query in ["zebrafish", "seminar", "lecture", "lecture notes"] {
            let clock = ContinuousClock()
            let coldStart = clock.now
            _ = await index.search(query)
            let cold = clock.now - coldStart
            var samples: [Duration] = []
            for _ in 0..<5 {
                let start = clock.now
                _ = await index.search(query)
                samples.append(clock.now - start)
            }
            recordBenchmark("search-2000x3-\(query)", medianMilliseconds(samples))
            recordBenchmark("search-2000x3-\(query)-cold", milliseconds(cold))
        }
    }
}

private actor BenchmarkRecognizer: HandwritingRecognizing {
    nonisolated let recognitionVersion = 1

    func text(for strokes: [StrokeRecord]) async -> String? {
        benchmarkText(page: 0, rare: false)
    }
}

private func benchmarkText(page: Int, rare: Bool) -> String {
    let head = rare
        ? "lecture seminar notes about integrals limits and the fundamental theorem "
        : "lecture notes about integrals limits and the fundamental theorem "
    let base = head
        + "with worked examples and a short summary of the reading for page \(page % 97) "
    var text = ""
    while text.count < 500 {
        text += base
    }
    return String(text.prefix(500))
}

private func benchmarkPage(strokeCount: Int, pointsPerStroke: Int) -> Page {
    let layerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    let tool = StrokeTool(engine: "pencilkit", inkType: "pen", color: .black, width: 2.5)
    let points = (0..<pointsPerStroke).map { index in
        StrokePoint(
            x: 40 + Double(index) * 4.5,
            y: 100 + Double(index % 17) * 2.25,
            timeOffset: Double(index) * 0.008,
            width: 2.4,
            height: 2.4,
            opacity: 1,
            force: 0.35 + Double(index % 11) * 0.05,
            azimuth: 0.2,
            altitude: 1.4,
            secondaryScale: 1,
            threshold: 0.1,
            lateralJitter: 0.02
        )
    }
    let strokes = (0..<strokeCount).map { index in
        StrokeRecord(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID(),
            layerID: layerID,
            tool: tool,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index) * 0.01),
            transform: [1, 0, 0, 1, Double(index % 13), Double(index % 7)],
            randomSeed: UInt32(index),
            points: points
        )
    }
    var page = Page(id: UUID(), width: 612, height: 792, template: .blank)
    page.strokes = strokes
    return page
}

private func benchmarkRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SearchKitBench-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}

private func medianMilliseconds(_ samples: [Duration]) -> Double {
    let sorted = samples.sorted()
    return milliseconds(sorted[sorted.count / 2])
}

private func recordBenchmark(_ name: String, _ milliseconds: Double) {
    let directory = ProcessInfo.processInfo.environment["NOTEAPP_BENCH_DIR"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.temporaryDirectory
    let file = directory.appendingPathComponent("searchkit-bench-\(name).txt")
    let line = "BENCH \(name) median_ms \(String(format: "%.3f", milliseconds))\n"
    try? line.write(to: file, atomically: true, encoding: .utf8)
}
