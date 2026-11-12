// The PDF import conversions: outline flattening, ink annotation geometry
// (including the flipped y axis and page rotation) and the stored copy that
// no longer carries the annotations which became strokes.

import CoreGraphics
import Foundation
import NoteCore
import PDFKit
import PencilKit
import Testing
@testable import InkKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@Suite("PDF import conversion")
struct PDFImportConversionTests {
    static let pageSize = CGSize(width: 200, height: 300)

    // MARK: - Outline

    @Test("The outline is flattened depth first with its pages and depths")
    func flattensOutline() throws {
        let document = try makeDocument()
        _ = try addOutline(to: document)

        let items = PDFImportConversion.outlineItems(in: document)

        #expect(items.count == 3)
        #expect(items.map(\.title) == ["Chapter A", "Section A.1", "Chapter B"])
        #expect(items.map(\.depth) == [0, 1, 0])
        #expect(items.map(\.pageIndex) == [0, 1, 1])
    }

    @Test("A document without an outline has no items")
    func emptyOutline() throws {
        let document = try makeDocument()
        #expect(PDFImportConversion.outlineItems(in: document).isEmpty)
    }

    // MARK: - Ink annotations

    @Test("An ink annotation becomes a stroke in page space with the flipped y axis")
    func convertsInkAnnotation() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        addInk(to: page, subpaths: [[CGPoint(x: 30, y: 60), CGPoint(x: 120, y: 200)]])

        let strokes = PDFImportConversion.inkStrokes(in: page, pageSize: Self.pageSize)

        #expect(strokes.count == 1)
        let stroke = try #require(strokes.first)
        // A PDF point 60 pt from the bottom is 240 pt from the top.
        #expect(stroke.points.count == 2)
        #expect(abs(stroke.points[0].x - 30) < 0.01)
        #expect(abs(stroke.points[0].y - 240) < 0.01)
        #expect(abs(stroke.points[1].x - 120) < 0.01)
        #expect(abs(stroke.points[1].y - 100) < 0.01)
        #expect(stroke.color.r > 0.9)
        #expect(stroke.color.g < 0.1)
        #expect(stroke.color.b < 0.1)
        #expect(abs(stroke.width - 3) < 0.01)
    }

    @Test("Each subpath of one annotation is its own stroke")
    func keepsSubpathsApart() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        addInk(
            to: page,
            subpaths: [
                [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 10)],
                [CGPoint(x: 10, y: 100), CGPoint(x: 40, y: 100)],
            ]
        )

        let strokes = PDFImportConversion.inkStrokes(in: page, pageSize: Self.pageSize)

        #expect(strokes.count == 2)
        #expect(strokes.first?.points.first?.y == 290)
        #expect(strokes.last?.points.first?.y == 200)
    }

    @Test("A border-less annotation keeps PDFKit's default width")
    func defaultWidth() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        addInk(to: page, subpaths: [[CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 10)]], lineWidth: nil)

        let stroke = try #require(
            PDFImportConversion.inkStrokes(in: page, pageSize: Self.pageSize).first
        )
        // PDFKit reports the PDF default border of 1 pt for a stored width of none.
        #expect(abs(stroke.width - 1) < 0.01)
    }

    @Test("A zero border width falls back to the import default")
    func zeroWidthFallsBack() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        addInk(to: page, subpaths: [[CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 10)]], lineWidth: 0)

        let stroke = try #require(
            PDFImportConversion.inkStrokes(in: page, pageSize: Self.pageSize).first
        )
        #expect(abs(stroke.width - PDFImportConversion.defaultInkWidth) < 0.01)
    }

    @Test("A rotated page maps its centre to the centre of the page box")
    func rotatedPage() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        page.rotation = 90

        let transform = PDFImportConversion.drawingTransform(for: page, pageSize: Self.pageSize)
        let centre = try #require(
            PDFImportConversion.pagePoint(
                CGPoint(x: 100, y: 150),
                transform: transform,
                pageHeight: Double(Self.pageSize.height)
            )
        )

        #expect(abs(centre.x - 100) < 0.5)
        #expect(abs(centre.y - 150) < 0.5)
    }

    // MARK: - Strokes

    @Test("Strokes become editable pen records on the given layer")
    func buildsStrokeRecords() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        addInk(to: page, subpaths: [[CGPoint(x: 30, y: 60), CGPoint(x: 120, y: 200)]])
        let layerID = UUID()

        let strokes = PDFImportConversion.inkStrokes(in: page, pageSize: Self.pageSize)
        let records = PDFImportConversion.strokeRecords(for: strokes, layerID: layerID)

        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.layerID == layerID)
        #expect(record.tool.engine == PDFImportConversion.engine)
        #expect(record.tool.inkType == PKInk.InkType.pen.rawValue)
        #expect(record.transform == StrokeRecord.identityTransform)
        #expect(abs(record.tool.width - 3) < 0.01)
        #expect(record.points.count == 2)
        #expect(abs(record.points[0].y - 240) < 0.01)
        #expect(record.points[0].width == record.tool.width)
        #expect(PageItemKind.of(record) == .pen)
    }

    @Test("A single-point path still produces a drawable stroke")
    func dotStroke() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        addInk(to: page, subpaths: [[CGPoint(x: 50, y: 50)]])

        let strokes = PDFImportConversion.inkStrokes(in: page, pageSize: Self.pageSize)
        let records = PDFImportConversion.strokeRecords(for: strokes, layerID: UUID())

        #expect(records.count == 1)
        #expect(records.first?.points.count == 2)
    }

    @Test("Imported ink draws where it was mapped on the page")
    func rendersAtMappedPosition() throws {
        let document = try makeDocument()
        let page = try #require(document.page(at: 0))
        addInk(to: page, subpaths: [[CGPoint(x: 30, y: 60), CGPoint(x: 120, y: 200)]])

        let strokes = PDFImportConversion.inkStrokes(in: page, pageSize: Self.pageSize)
        let records = PDFImportConversion.strokeRecords(for: strokes, layerID: UUID())
        let drawing = StrokeCodec.drawing(from: records)

        #expect(drawing.strokes.count == 1)
        // Page-space midpoint of (30, 240)…(120, 100). The PDF y-up midpoint
        // would be 130 instead, so this also proves the flip.
        let bounds = drawing.bounds
        #expect(abs(bounds.midX - 75) < 3)
        #expect(abs(bounds.midY - 170) < 3)
    }

    @Test("A record survives a file round trip with its imported geometry")
    func recordRoundTrip() throws {
        let record = StrokeRecord(
            id: UUID(),
            layerID: UUID(),
            tool: StrokeTool(
                engine: PDFImportConversion.engine,
                inkType: PKInk.InkType.pen.rawValue,
                color: RGBAColor(r: 0.2, g: 0.4, b: 0.6),
                width: 2.5
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            randomSeed: 42,
            points: [
                StrokePoint(
                    x: 12,
                    y: 34,
                    timeOffset: 0,
                    width: 2.5,
                    height: 2.5,
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: .pi / 2,
                    secondaryScale: 1
                )
            ]
        )

        let data = try PageCodec.encode(Page(
            id: UUID(),
            width: 200,
            height: 300,
            template: .blank,
            layers: [Page.Layer(id: record.layerID, name: "Layer 1")],
            strokes: [record]
        ))
        let decoded = try PageCodec.decode(data)

        #expect(decoded.strokes == [record])
    }

    // MARK: - Stored copy

    @Test("The stored copy drops converted ink but keeps other annotations")
    func stripsConvertedInk() throws {
        let document = try makeDocument()
        let first = try #require(document.page(at: 0))
        let second = try #require(document.page(at: 1))
        addInk(to: first, subpaths: [[CGPoint(x: 30, y: 60), CGPoint(x: 120, y: 200)]])
        addHighlight(to: second)

        let data = try #require(
            PDFImportConversion.data(removingInkAnnotationsOn: [0], from: document)
        )
        let reopened = try #require(PDFDocument(data: data))

        #expect(reopened.pageCount == 2)
        #expect(reopened.page(at: 0)?.annotations.isEmpty == true)
        // A highlight is not converted, so it stays part of the page.
        #expect(reopened.page(at: 1)?.annotations.count == 1)
        // Rewriting must not cost the page its drawing.
        let page = try #require(reopened.page(at: 0))
        #expect(drawnPixels(of: page, size: Self.pageSize) > 100)
    }

    @Test("A locked document can be stored without its password")
    func stripsEncryption() throws {
        let data = try makeEncryptedDocument()
        let document = try #require(PDFDocument(data: data))
        #expect(document.isLocked)
        #expect(document.unlock(withPassword: "secret"))

        let page = try #require(document.page(at: 0))
        addInk(to: page, subpaths: [[CGPoint(x: 30, y: 60), CGPoint(x: 90, y: 120)]])

        let stored = try #require(PDFImportConversion.data(removingInkAnnotationsOn: [0], from: document))
        let reopened = try #require(PDFDocument(data: stored))

        #expect(!reopened.isLocked)
        #expect(!reopened.isEncrypted)
        #expect(reopened.pageCount == 1)
        // An unlocked document keeps its pages readable without the password.
        let unlockedPage = try #require(reopened.page(at: 0))
        #expect(unlockedPage.annotations.isEmpty)
        #expect(drawnPixels(of: unlockedPage, size: Self.pageSize) > 100)
    }

    // MARK: - Fixtures

    private func makeDocument() throws -> PDFDocument {
        let data = try makePDF(pageCount: 2, size: Self.pageSize, userPassword: nil)
        return try #require(PDFDocument(data: data))
    }

    @discardableResult
    private func addOutline(to document: PDFDocument) throws -> PDFOutline {
        let root = PDFOutline()
        let chapterA = PDFOutline()
        chapterA.label = "Chapter A"
        chapterA.destination = PDFDestination(
            page: try #require(document.page(at: 0)),
            at: .zero
        )
        let section = PDFOutline()
        section.label = "Section A.1"
        section.destination = PDFDestination(
            page: try #require(document.page(at: 1)),
            at: .zero
        )
        let chapterB = PDFOutline()
        chapterB.label = "Chapter B"
        chapterB.destination = PDFDestination(
            page: try #require(document.page(at: 1)),
            at: .zero
        )
        root.insertChild(chapterA, at: 0)
        root.insertChild(chapterB, at: 1)
        chapterA.insertChild(section, at: 0)
        document.outlineRoot = root
        return root
    }

    private func makePDF(pageCount: Int, size: CGSize, userPassword: String?) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var options: [CFString: Any] = [:]
        if let userPassword {
            options[kCGPDFContextUserPassword] = userPassword
            options[kCGPDFContextOwnerPassword] = userPassword
        }
        let context = try #require(
            CGContext(
                consumer: consumer,
                mediaBox: &box,
                options.isEmpty ? nil : options as CFDictionary
            )
        )
        for index in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 10, y: 10 + Double(index) * 20, width: 40, height: 40))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private func makeEncryptedDocument() throws -> Data {
        try makePDF(pageCount: 1, size: Self.pageSize, userPassword: "secret")
    }

    private func addInk(
        to page: PDFPage,
        subpaths: [[CGPoint]],
        lineWidth: CGFloat? = 3
    ) {
        let path = platformPath(subpaths)
        let annotation = PDFAnnotation(
            bounds: path.bounds,
            forType: .ink,
            withProperties: nil
        )
        annotation.color = platformRed
        if let lineWidth {
            let border = PDFBorder()
            border.lineWidth = lineWidth
            annotation.border = border
        }
        annotation.add(path)
        page.addAnnotation(annotation)
    }

    private func addHighlight(to page: PDFPage) {
        let annotation = PDFAnnotation(
            bounds: CGRect(x: 20, y: 20, width: 80, height: 12),
            forType: .highlight,
            withProperties: nil
        )
        page.addAnnotation(annotation)
    }

    private func platformPath(_ subpaths: [[CGPoint]]) -> PlatformBezierPath {
        let path = PlatformBezierPath()
        for subpath in subpaths {
            guard let first = subpath.first else { continue }
            path.move(to: first)
            for point in subpath.dropFirst() {
                #if os(iOS)
                path.addLine(to: point)
                #else
                path.line(to: point)
                #endif
            }
        }
        return path
    }

    private var platformRed: PlatformColor {
        #if os(iOS)
        UIColor.red
        #else
        NSColor.red
        #endif
    }

    /// How many of the page's own pixels are not paper, drawn the way the app
    /// draws a PDF page.
    private func drawnPixels(of page: PDFPage, size: CGSize) -> Int {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return 0 }

        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let pageRef = page.pageRef
            else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let transform = pageRef.getDrawingTransform(
                .mediaBox,
                rect: CGRect(origin: .zero, size: size),
                rotate: 0,
                preserveAspectRatio: true
            )
            context.concatenate(transform)
            context.drawPDFPage(pageRef)
            return true
        }
        guard drawn else { return 0 }
        return stride(from: 0, to: data.count, by: 4).reduce(into: 0) { count, index in
            if data[index] < 240 { count += 1 }
        }
    }
}

#if os(iOS)
private typealias PlatformBezierPath = UIBezierPath
private typealias PlatformColor = UIColor
#else
private typealias PlatformBezierPath = NSBezierPath
private typealias PlatformColor = NSColor
#endif
