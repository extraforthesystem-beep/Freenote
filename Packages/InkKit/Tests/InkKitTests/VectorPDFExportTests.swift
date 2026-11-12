// End-to-end checks of the vector PDF export: an imported PDF page with text,
// a typed text box, pen strokes and a highlighter go in; PDFKit reads back
// selectable text, no ink bitmaps, and (in editable mode) one ink annotation
// per stroke.

import CoreGraphics
import CoreText
import Foundation
import NoteCore
import PDFKit
import PencilKit
import Testing
@testable import InkKit

@Suite("Vector PDF export")
struct VectorPDFExportTests {
    static let pageSize = CGSize(width: 612, height: 792)
    static let importedText = "Quarterly imported report"
    static let typedText = "Typed note about vectors"

    // MARK: - Fixture

    struct Fixture {
        var directory: URL
        var page: Page
        var strokeCount: Int
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VectorPDFExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeTextPDF(Self.importedText, to: directory.appendingPathComponent("import.pdf"))

        let layerID = UUID()
        var page = Page(
            id: UUID(),
            width: Self.pageSize.width,
            height: Self.pageSize.height,
            template: PageTemplate(
                kind: "ruled",
                spacing: 24,
                lineColor: RGBAColor(r: 0.7, g: 0.75, b: 0.85),
                paperColor: .white
            ),
            layers: [Page.Layer(id: layerID, name: "Layer 1")]
        )
        page.elements = [
            PageElement(
                id: UUID(),
                layerID: layerID,
                frame: ElementFrame(x: 0, y: 0, width: Self.pageSize.width, height: Self.pageSize.height),
                zIndex: 0,
                updatedAt: Date(),
                content: .pdfPage(assetName: "import.pdf", pageIndex: 0)
            ),
            PageElement(
                id: UUID(),
                layerID: layerID,
                frame: ElementFrame(x: 60, y: 500, width: 400, height: 80),
                zIndex: 1,
                updatedAt: Date(),
                content: .text(Self.typedText, fontName: "Helvetica", fontSize: 18, color: .black),
                textStyle: TextStyle(isBold: true, alignment: .leading)
            ),
        ]
        let strokes = [
            SampleStroke.stroke(style: .pen, index: 0),
            SampleStroke.stroke(style: .pen, index: 3),
            SampleStroke.stroke(style: .monoline, index: 0, pointCount: 64),
            SampleStroke.stroke(style: .marker, index: 1),
        ]
        page.strokes = strokes.map { StrokeCodec.record(from: $0, layerID: layerID) }
        #expect(page.strokes.last?.tool.isHighlighter == true)
        return Fixture(directory: directory, page: page, strokeCount: strokes.count)
    }

    private func writeTextPDF(_ text: String, to url: URL) throws {
        var box = CGRect(origin: .zero, size: Self.pageSize)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
    }

    private func export(
        _ fixture: Fixture,
        includeInk: Bool,
        name: String
    ) throws -> URL {
        let url = fixture.directory.appendingPathComponent(name)
        let writer = try #require(VectorPDFWriter(url: url, title: "Test Notebook", creator: "NoteApp"))
        writer.addPage(fixture.page, assetsDirectory: fixture.directory, includeInk: includeInk)
        writer.setOutline([(0, "Intro")])
        writer.close()
        return url
    }

    // MARK: - Tests

    @Test("Flattened export keeps text selectable and ink as vectors")
    func flattened() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let url = try export(fixture, includeInk: true, name: "flat.pdf")

        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 1)
        let page = try #require(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        #expect(bounds.size == Self.pageSize)
        let text = page.string ?? ""
        #expect(text.contains(Self.importedText))
        #expect(text.contains(Self.typedText))
        #expect(page.annotations.isEmpty)

        let ref = try #require(page.pageRef)
        #expect(imageXObjectCount(in: ref) == 0)
        #expect((document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) == "Test Notebook")
        #expect((document.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String) == "NoteApp")
    }

    @Test("Editable export writes one ink annotation per stroke")
    func editable() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let url = try export(fixture, includeInk: false, name: "editable-base.pdf")

        let document = try #require(PDFDocument(url: url))
        let pdfPage = try #require(document.page(at: 0))
        let added = VectorPDFAnnotations.addInkAnnotations(
            for: fixture.page.renderStrokes,
            to: pdfPage,
            pageHeight: Self.pageSize.height
        )
        #expect(added == fixture.strokeCount)
        let data = try #require(document.dataRepresentation())

        let reread = try #require(PDFDocument(data: data))
        let page = try #require(reread.page(at: 0))
        let inks = page.annotations.filter { $0.type == "Ink" }
        #expect(inks.count == fixture.strokeCount)
        for ink in inks {
            #expect(!(ink.paths ?? []).isEmpty)
            #expect(ink.border?.lineWidth ?? 0 > 0)
        }
        // The highlighter's translucency survives in its appearance stream.
        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.contains("/CA 0."))
        // No author name stamped on the annotations.
        #expect(!raw.contains("/T ("))
        #expect((reread.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) == "Test Notebook")
        // Paths land on the strokes: every annotation's path, offset by its
        // origin, lies inside the page and inside its own bounds.
        for ink in inks {
            let box = ink.paths?.first.map { $0.cgPath.boundingBoxOfPath } ?? .null
            let placed = box.offsetBy(dx: ink.bounds.minX, dy: ink.bounds.minY)
            #expect(ink.bounds.insetBy(dx: -1, dy: -1).contains(placed))
        }
        let text = page.string ?? ""
        #expect(text.contains(Self.importedText))
        #expect(text.contains(Self.typedText))
        #expect(reread.outlineRoot?.numberOfChildren == 1)
        #expect(reread.outlineRoot?.child(at: 0)?.label == "Intro")
    }

    @Test("Vector ink matches PencilKit's bitmap closely")
    func inkFidelity() throws {
        for style in [PenStyle.pen, .monoline, .marker] {
            let record = StrokeCodec.record(from: handwritten(style), layerID: UUID())
            let size = CGSize(width: 400, height: 300)
            let reference = try #require(PageRenderer.cgImage(
                of: StrokeCodec.drawing(from: [record]).image(from: CGRect(origin: .zero, size: size), scale: 1)
            ))
            let referenceMask = try coverage(of: reference, size: size)

            let vectorMask = try coverage(size: size) { context in
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                if var outline = VectorPageRenderer.inkOutline(for: record) {
                    outline.color.a = 1
                    outline.isHighlighter = false
                    VectorPageRenderer.fill(outline, in: context)
                }
            }

            var both = 0, either = 0
            for i in 0..<referenceMask.count {
                if referenceMask[i] || vectorMask[i] { either += 1 }
                if referenceMask[i] && vectorMask[i] { both += 1 }
            }
            let iou = Double(both) / Double(max(either, 1))
            // PencilKit's marker has a chisel nib; the export draws it round.
            #expect(iou > (style == .marker ? 0.7 : 0.8), "\(style) IoU \(iou)")
        }
    }

    @Test("A partly erased, moved stroke is clipped where PencilKit clips it")
    func maskedAndTransformed() throws {
        let original = handwritten(.pen)
        let mask = SamplePath(rect: CGRect(x: 0, y: 0, width: 200, height: 300))
        let stroke = PKStroke(
            ink: original.ink,
            path: original.path,
            transform: CGAffineTransform(translationX: -40, y: 15),
            mask: mask
        )
        let record = StrokeCodec.record(from: stroke, layerID: UUID())
        #expect(record.mask != nil)
        let size = CGSize(width: 400, height: 300)
        let reference = try #require(PageRenderer.cgImage(
            of: StrokeCodec.drawing(from: [record]).image(from: CGRect(origin: .zero, size: size), scale: 1)
        ))
        let referenceMask = try coverage(of: reference, size: size)
        let vectorMask = try coverage(size: size) { context in
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            if var outline = VectorPageRenderer.inkOutline(for: record) {
                outline.color.a = 1
                VectorPageRenderer.fill(outline, in: context)
            }
        }
        var both = 0, either = 0
        for i in 0..<referenceMask.count {
            if referenceMask[i] || vectorMask[i] { either += 1 }
            if referenceMask[i] && vectorMask[i] { both += 1 }
        }
        let iou = Double(both) / Double(max(either, 1))
        #expect(iou > 0.8, "IoU \(iou)")
        // The mask lives in the stroke's own space and moves with it: nothing
        // is left right of x = 200 - 40.
        let rightmost = { (mask: [Bool]) in
            mask.indices.filter { mask[$0] }.map { $0 % Int(size.width) }.max() ?? 0
        }
        #expect(rightmost(referenceMask) <= 161)
        #expect(rightmost(vectorMask) <= 161)
        #expect(rightmost(vectorMask) >= 155)
    }

    // MARK: - Helpers

    /// A realistic stroke: a smooth loop-and-wave at Pencil sample density,
    /// full opacity, pressure easing in and out.
    private func handwritten(_ style: PenStyle) -> PKStroke {
        let count = 120
        let base = CGFloat(style == .marker ? 12 : 4)
        let points = (0..<count).map { i -> PKStrokePoint in
            let t = CGFloat(i) / CGFloat(count - 1)
            let pressure = 0.6 + 0.4 * sin(t * .pi)
            return PKStrokePoint(
                location: CGPoint(x: 40 + t * 320, y: 150 + 60 * sin(t * 3 * .pi) + 25 * cos(t * 7 * .pi)),
                timeOffset: Double(t) * 0.8,
                size: CGSize(width: base * pressure, height: base * pressure),
                opacity: 1,
                force: pressure,
                azimuth: 0.8,
                altitude: 1.0,
                secondaryScale: 1
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 0))
        return PKStroke(ink: PKInk(style.inkType, color: .black), path: path)
    }

    /// Image XObjects on the page, including inside nested form XObjects.
    private func imageXObjectCount(in page: CGPDFPage) -> Int {
        guard let dictionary = page.dictionary else { return 0 }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return 0 }
        return imageXObjectCount(resources: resources, depth: 0)
    }

    private func imageXObjectCount(resources: CGPDFDictionaryRef, depth: Int) -> Int {
        guard depth < 8 else { return 0 }
        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects else { return 0 }
        final class Box { var count = 0; var nested: [CGPDFDictionaryRef] = [] }
        let box = Box()
        CGPDFDictionaryApplyBlock(xObjects, { _, object, info in
            let box = Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue()
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let streamDictionary = CGPDFStreamGetDictionary(stream)
            else { return true }
            var subtype: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(streamDictionary, "Subtype", &subtype), let subtype {
                let name = String(cString: subtype)
                if name == "Image" { box.count += 1 }
                if name == "Form" {
                    var nested: CGPDFDictionaryRef?
                    if CGPDFDictionaryGetDictionary(streamDictionary, "Resources", &nested), let nested {
                        box.nested.append(nested)
                    }
                }
            }
            return true
        }, Unmanaged.passUnretained(box).toOpaque())
        return box.count + box.nested.reduce(0) { $0 + imageXObjectCount(resources: $1, depth: depth + 1) }
    }

    private func coverage(of image: CGImage, size: CGSize) throws -> [Bool] {
        try coverage(size: size) { context in
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
    }

    /// Alpha coverage (> 30%) of what `draw` paints into a 1× bitmap.
    private func coverage(size: CGSize, draw: (CGContext) -> Void) throws -> [Bool] {
        let width = Int(size.width), height = Int(size.height)
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        draw(context)
        let data = try #require(context.data)
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return (0..<(width * height)).map { bytes[$0 * 4 + 3] > 77 }
    }
}
