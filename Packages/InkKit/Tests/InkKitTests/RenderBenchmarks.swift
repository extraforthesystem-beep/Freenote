// Timing benchmarks for the page render paths. They are off by default so
// the suite stays fast; run them with:
//
//     NOTEAPP_BENCH=1 swift test --filter RenderBenchmarks
//
// Numbers are reported with `Issue`-free prints to the test log only when
// enabled; nothing here asserts on time, so a slow machine cannot fail CI.

import CoreGraphics
import CoreText
import Foundation
import NoteCore
import PDFKit
import Testing
@testable import InkKit

@Suite("Render benchmarks", .enabled(if: ProcessInfo.processInfo.environment["NOTEAPP_BENCH"] != nil))
struct RenderBenchmarks {
    /// A text-heavy PDF, like an imported lecture deck or a scanned book.
    static func makeTextPDF(pages: Int, at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        for page in 0..<pages {
            context.beginPDFPage(nil)
            for line in 0..<70 {
                let text = "Page \(page + 1) line \(line + 1): the quick brown fox jumps over the lazy dog, 0123456789."
                let attributed = NSAttributedString(
                    string: text,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
                )
                let ctLine = CTLineCreateWithAttributedString(attributed)
                context.textPosition = CGPoint(x: 36, y: 806 - CGFloat(line) * 11)
                CTLineDraw(ctLine, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    static func page(assetName: String, pageIndex: Int) -> Page {
        var page = Page(id: UUID(), width: 595, height: 842, template: .blank)
        page.elements = [
            PageElement(
                id: UUID(),
                layerID: page.layers[0].id,
                frame: ElementFrame(x: 0, y: 0, width: 595, height: 842, rotation: 0),
                zIndex: 0,
                updatedAt: Date(),
                content: .pdfPage(assetName: assetName, pageIndex: pageIndex)
            ),
        ]
        return page
    }

    @Test func pdfPageImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-bench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageCount = 400
        try Self.makeTextPDF(pages: pageCount, at: directory.appendingPathComponent("book.pdf"))

        let clock = ContinuousClock()
        // Thumbnail-sized renders of 40 pages spread through the document:
        // what the page strip and the seamless scroll ask for.
        let indices = stride(from: 0, to: pageCount, by: pageCount / 40).map { $0 }
        let elapsed = clock.measure {
            for index in indices {
                _ = PageRenderer.image(
                    page: Self.page(assetName: "book.pdf", pageIndex: index),
                    assetsDirectory: directory,
                    scale: 0.3
                )
            }
        }
        print("BENCH pdfPageImages: \(indices.count) thumbnails of a \(pageCount)-page PDF in \(elapsed)")

        let url = directory.appendingPathComponent("book.pdf")
        let opening = clock.measure {
            for index in indices {
                _ = PDFDocument(url: url)?.page(at: index)?.annotations
            }
        }
        print("BENCH pdfOpenOnly: \(indices.count) opens + page lookups in \(opening)")
    }

    /// The same pass over a real document: set NOTEAPP_BENCH_PDF to a PDF's
    /// path. Real-world PDFs (scans, books with damaged cross-reference
    /// tables) cost far more to open than the clean synthetic one.
    @Test func realPDFPageImages() throws {
        guard let path = ProcessInfo.processInfo.environment["NOTEAPP_BENCH_PDF"] else { return }
        let source = URL(fileURLWithPath: path)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-bench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("real.pdf"))
        let url = directory.appendingPathComponent("real.pdf")
        let pageCount = PDFDocument(url: url)?.pageCount ?? 0
        guard pageCount > 0 else { return }

        let clock = ContinuousClock()
        let indices = stride(from: 0, to: pageCount, by: max(1, pageCount / 40)).map { $0 }
        let opening = clock.measure {
            for index in indices {
                _ = PDFDocument(url: url)?.page(at: index)?.annotations
            }
        }
        let rendering = clock.measure {
            for index in indices {
                _ = PageRenderer.image(
                    page: Self.page(assetName: "real.pdf", pageIndex: index),
                    assetsDirectory: directory,
                    scale: 0.3
                )
            }
        }
        print("BENCH realPDF (\(pageCount) pages): \(indices.count) opens \(opening), \(indices.count) thumbnails \(rendering)")

        // The live page's paper is drawn at 2x on the main actor when it is
        // not cached (PaperBackground): what activating a page costs.
        let sample = Array(indices.prefix(10))
        let paper = clock.measure {
            for index in sample {
                _ = PageRenderer.image(
                    page: Self.page(assetName: "real.pdf", pageIndex: index),
                    assetsDirectory: directory,
                    scale: 2
                )
            }
        }
        print("BENCH realPDF 2x paper: \(sample.count) pages \(paper)")
    }

    /// The median of five runs, so one scheduler hiccup does not decide the
    /// number.
    static func median(_ values: [Duration]) -> Duration {
        values.sorted()[values.count / 2]
    }

    /// One stroke appended to a page that already has `strokeCount` strokes,
    /// through the converter's change check. The converter is prepared outside
    /// the measurement.
    static func oneStrokeAppend(
        strokeCount: Int,
        appendOnly: Bool,
        appendedPointCount: Int = 64,
        clock: ContinuousClock
    ) -> Duration {
        let layerID = UUID()
        var strokes = (0..<strokeCount).map {
            SampleStroke.stroke(style: .pen, index: $0, pointCount: 64)
        }
        let converter = IncrementalStrokeConverter()
        let records = converter.records(from: strokes) { _ in layerID }
        converter.seed(strokes: strokes, records: records)
        strokes.append(SampleStroke.stroke(style: .pen, index: 1, pointCount: appendedPointCount))
        return clock.measure {
            _ = converter.changedRecords(
                from: strokes,
                layerID: { _ in layerID },
                appendOnly: appendOnly
            )
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }

    @Test func inkOneStrokeAppend() throws {
        let clock = ContinuousClock()
        for strokeCount in [200, 2_000] {
            for appendOnly in [false, true] {
                let elapsed = Self.median((0..<5).map { _ in
                    Self.oneStrokeAppend(
                        strokeCount: strokeCount,
                        appendOnly: appendOnly,
                        clock: clock
                    )
                })
                let path = appendOnly ? "append fast path" : "full path"
                print("BENCH inkAppend \(strokeCount) strokes, \(path): median \(elapsed)")
            }
        }
    }

    /// The fast path must cost the size of the change, not the page: appending
    /// one stroke to 2,000 must not take twice as long as to 200.
    @Test func inkAppendScalesWithTheChange() throws {
        let clock = ContinuousClock()
        // About four seconds of handwriting: the added stroke's own encoding
        // is a constant cost, as it must be, and the page must not add to it.
        let appendedPoints = 1_000
        let small = Self.median((0..<7).map { _ in
            Self.oneStrokeAppend(
                strokeCount: 200,
                appendOnly: true,
                appendedPointCount: appendedPoints,
                clock: clock
            )
        })
        let large = Self.median((0..<7).map { _ in
            Self.oneStrokeAppend(
                strokeCount: 2_000,
                appendOnly: true,
                appendedPointCount: appendedPoints,
                clock: clock
            )
        })
        print(
            "BENCH inkAppendScaling: N=200 median \(small) "
                + "(\(Self.seconds(small)) s), N=2000 median \(large) "
                + "(\(Self.seconds(large)) s), ratio "
                + String(format: "%.2f", Self.seconds(large) / Self.seconds(small))
        )
        #expect(large <= small * 2)
    }

    /// What one finished stroke costs on a busy page: the converter's change
    /// check and conversion, then the session's merge into the page.
    @Test func inkRoundTrip() throws {
        let strokeCount = 2_000
        let layerID = UUID()
        var strokes = (0..<strokeCount).map { SampleStroke.stroke(style: .pen, index: $0, pointCount: 64) }
        let converter = IncrementalStrokeConverter()
        let records = converter.records(from: strokes) { _ in layerID }
        converter.seed(strokes: strokes, records: records)
        strokes.append(SampleStroke.stroke(style: .pen, index: 1, pointCount: 64))

        let clock = ContinuousClock()
        var changed: [StrokeRecord] = []
        let converting = clock.measure {
            changed = converter.changedRecords(from: strokes) { _ in layerID } ?? []
        }
        let merging = clock.measure {
            _ = StrokeOrder.merge(existing: records, canvas: changed, hiddenLayerIDs: [], layerOrder: [layerID])
        }
        let encoding = try clock.measure {
            var page = Page(width: 595, height: 842, template: .blank)
            page.strokes = changed
            _ = try PageCodec.encode(page)
        }
        print("BENCH inkRoundTrip \(strokeCount) strokes: converter \(converting), merge \(merging), page encode (off main) \(encoding)")
    }
}
