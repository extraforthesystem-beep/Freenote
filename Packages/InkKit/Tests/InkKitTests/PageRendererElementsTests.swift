// Rendering tests for page elements: the page must come out with its PDF
// pages, images, text boxes and shapes drawn in the right place, right way up
// and in `zIndex` order, and a broken asset must cost only that element.

import CoreGraphics
import Foundation
import ImageIO
import NoteCore
import PencilKit
import Testing
@testable import InkKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@Suite("Page renderer elements")
struct PageRendererElementsTests {
    static let paper = PageTemplate(
        kind: "blank",
        spacing: 0,
        lineColor: RGBAColor(r: 0.8, g: 0.8, b: 0.8),
        paperColor: .white
    )

    static let red = RGBAColor(r: 0.9, g: 0.05, b: 0.05)
    static let blue = RGBAColor(r: 0.05, g: 0.05, b: 0.9)
    static let black = RGBAColor(r: 0, g: 0, b: 0)

    // MARK: - Images

    @Test("An image element is drawn aspect-fit inside its frame")
    func drawsImage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = try assetsDirectory(in: directory)
        try writePNG(try #require(solidImage(width: 40, height: 30, color: Self.red)), to: assets.appendingPathComponent("photo.png"))

        let bitmap = try render(
            size: CGSize(width: 160, height: 100),
            elements: [
                element(
                    .image(assetName: "photo.png"),
                    frame: ElementFrame(x: 20, y: 20, width: 100, height: 60)
                )
            ],
            assets: assets
        )

        // 40×30 fits 100×60 at scale 2: 80×60, centred, so x 30…110.
        let centre = bitmap.pixel(70, 50)
        #expect(centre.r > 200)
        #expect(centre.g < 80)
        #expect(centre.b < 80)
        // Aspect fit, not stretch: the frame's left edge stays paper.
        #expect(bitmap.pixel(25, 25).isPaper)
        #expect(bitmap.nonPaperPixels > 1000)
    }

    @Test("A missing image asset is skipped, not fatal")
    func skipsMissingImage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = try assetsDirectory(in: directory)

        let frame = ElementFrame(x: 20, y: 20, width: 100, height: 60)
        let element = element(.image(assetName: "does-not-exist.png"), frame: frame)

        let withAssets = try render(
            size: CGSize(width: 160, height: 100),
            elements: [element],
            assets: assets
        )
        #expect(withAssets.pixel(70, 50).isPaper)

        let withoutAssets = try render(
            size: CGSize(width: 160, height: 100),
            elements: [element]
        )
        #expect(withoutAssets.pixel(70, 50).isPaper)
    }

    // MARK: - Text

    @Test("A text element is drawn, with or without its font installed")
    func drawsText() throws {
        let frame = ElementFrame(x: 20, y: 20, width: 200, height: 60)
        for fontName in ["Helvetica", "InkKitNoSuchFont"] {
            let bitmap = try render(
                size: CGSize(width: 240, height: 120),
                elements: [
                    element(
                        .text("Handwriting test", fontName: fontName, fontSize: 24, color: .black),
                        frame: frame
                    )
                ]
            )
            #expect(bitmap.darkPixels > 100, "text is visible with font \(fontName)")
            #expect(bitmap.nonPaperPixels > 100, "text differs from the paper with font \(fontName)")
            #expect(bitmap.pixel(5, 5).isPaper, "text stays inside its frame with font \(fontName)")
        }
    }

    // MARK: - Shapes

    @Test("Every shape kind draws", arguments: ["rect", "ellipse", "line", "unknown"])
    func drawsShapes(kind: String) throws {
        let frame = ElementFrame(x: 20, y: 20, width: 160, height: 160)
        let bitmap = try render(
            size: CGSize(width: 200, height: 200),
            elements: [
                element(
                    .shape(kind: kind, stroke: .black, fill: Self.blue, lineWidth: 3),
                    frame: frame
                )
            ]
        )

        // A 3 pt line across the frame is about 800 pixels; filled kinds are
        // an order of magnitude more.
        #expect(bitmap.nonPaperPixels > 500, "\(kind) draws something")
        switch kind {
        case "line":
            // A line runs from the frame's top-left to its bottom-right.
            #expect(bitmap.pixel(60, 60).isInk)
            #expect(bitmap.pixel(140, 60).isPaper)
        default:
            #expect(bitmap.pixel(100, 100).b > 180, "\(kind) is filled")
        }
    }

    // MARK: - PDF pages

    @Test("A PDF page element renders page 0 and page 1 upright")
    func drawsPDFPages() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = try assetsDirectory(in: directory)
        try writeTwoPagePDF(to: assets.appendingPathComponent("scan.pdf"))

        let size = CGSize(width: 240, height: 320)
        let frame = ElementFrame(x: 20, y: 20, width: 200, height: 280)

        for pageIndex in 0..<2 {
            let bitmap = try render(
                size: size,
                elements: [element(.pdfPage(assetName: "scan.pdf", pageIndex: pageIndex), frame: frame)],
                assets: assets
            )

            var count = 0
            var rowSum = 0
            var columnSum = 0
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.pixel(x, y).isInk {
                    count += 1
                    rowSum += y
                    columnSum += x
                }
            }

            // The bar is 60×84 pt at scale 1: 5,040 pixels.
            #expect(count > 2000, "page \(pageIndex) draws its bar")
            let meanRow = rowSum / max(count, 1)
            let meanColumn = columnSum / max(count, 1)
            // The bar is in the top half of the PDF page, so it must be in the
            // top half of the rendered page: an upside-down page would fail.
            #expect(meanRow < bitmap.height / 2, "page \(pageIndex) reads upright")
            if pageIndex == 0 {
                #expect(meanColumn < bitmap.width / 2, "page 0 draws page 0")
            } else {
                #expect(meanColumn > bitmap.width / 2, "page 1 draws page 1")
            }
        }
    }

    @Test("A PDF element with a bad asset or page index is skipped")
    func skipsBadPDFs() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = try assetsDirectory(in: directory)
        try writeTwoPagePDF(to: assets.appendingPathComponent("scan.pdf"))
        try writePNG(try #require(solidImage(width: 8, height: 8, color: Self.red)), to: assets.appendingPathComponent("not-a-pdf.pdf"))

        let frame = ElementFrame(x: 20, y: 20, width: 200, height: 280)
        let pageSize = CGSize(width: 240, height: 320)
        for assetName in ["not-a-pdf.pdf", "missing.pdf"] {
            let bitmap = try render(
                size: pageSize,
                elements: [element(.pdfPage(assetName: assetName, pageIndex: 0), frame: frame)],
                assets: assets
            )
            #expect(bitmap.nonPaperPixels == 0, "\(assetName) is skipped")
        }

        let outOfRange = try render(
            size: pageSize,
            elements: [element(.pdfPage(assetName: "scan.pdf", pageIndex: 9), frame: frame)],
            assets: assets
        )
        #expect(outOfRange.nonPaperPixels == 0)
    }

    @Test("Ink is drawn over the elements")
    func drawsInkLast() throws {
        let pageSize = CGSize(width: 200, height: 200)
        let box = element(
            .shape(kind: "rect", stroke: Self.blue, fill: Self.blue, lineWidth: 1),
            frame: ElementFrame(x: 50, y: 50, width: 100, height: 100)
        )
        let ink = StrokeCodec.record(
            from: horizontalStroke(y: 100, color: InkPlatformColor(srgbRed: 0.9, green: 0.05, blue: 0.05, alpha: 1)),
            layerID: UUID()
        )

        let image = try #require(
            PageRenderer.image(
                strokes: [ink],
                pageSize: pageSize,
                template: Self.paper,
                elements: [box],
                scale: 1
            )
        )
        let bitmap = try #require(TestBitmap(image: image))
        let centre = bitmap.pixel(100, 100)
        #expect(centre.r > 150, "the red stroke covers the blue element")
        #expect(centre.b < 100, "the red stroke covers the blue element")
    }

    // MARK: - Sticky notes and tape

    @Test("A sticky note draws its card and its text")
    func drawsStickyNote() throws {
        let pastel = RGBAColor(r: 1, g: 0.93, b: 0.6)
        let bitmap = try render(
            size: CGSize(width: 240, height: 240),
            elements: [
                element(
                    .stickyNote("Remember this", color: pastel),
                    frame: ElementFrame(x: 20, y: 20, width: 200, height: 200)
                )
            ]
        )

        // The card covers most of its 200×200 frame.
        #expect(bitmap.nonPaperPixels > 20_000)
        let card = bitmap.pixel(120, 120)
        #expect(card.r > 200 && card.g > 200 && card.b < 210, "the card is filled with its colour")
        #expect(bitmap.darkPixels > 50, "the note's text is drawn")
        #expect(bitmap.pixel(5, 5).isPaper, "the note stays inside its frame")
        // An empty note is still a card.
        let blank = try render(
            size: CGSize(width: 240, height: 240),
            elements: [
                element(
                    .stickyNote("", color: pastel),
                    frame: ElementFrame(x: 20, y: 20, width: 200, height: 200)
                )
            ]
        )
        #expect(blank.nonPaperPixels > 20_000)
    }

    @Test("Tape draws a band in its colour and nothing outside it")
    func drawsTape() throws {
        let bitmap = try render(
            size: CGSize(width: 300, height: 120),
            elements: [
                element(
                    .tape(color: Self.red),
                    frame: ElementFrame(x: 30, y: 42, width: 240, height: 36)
                )
            ]
        )

        let band = bitmap.pixel(150, 60)
        #expect(band.r > 150, "the band is its colour")
        #expect(band.g < 140)
        #expect(band.b < 140)
        // The stripes are drawn over the colour, so the band is not one flat tone.
        #expect(bitmap.nonPaperPixels > 7_000)
        #expect(bitmap.pixel(150, 10).isPaper, "tape stays inside its frame")
        #expect(bitmap.pixel(10, 60).isPaper)
    }

    // MARK: - Order and placement

    @Test("Higher zIndex paints over lower zIndex")
    func respectsZIndex() throws {
        let frame = ElementFrame(x: 50, y: 50, width: 100, height: 100)
        let redBox = element(
            .shape(kind: "rect", stroke: Self.red, fill: Self.red, lineWidth: 2),
            frame: frame,
            zIndex: 0
        )
        let blueBox = element(
            .shape(kind: "rect", stroke: Self.blue, fill: Self.blue, lineWidth: 2),
            frame: frame,
            zIndex: 1
        )

        // Array order deliberately disagrees with zIndex.
        let bitmap = try render(
            size: CGSize(width: 200, height: 200),
            elements: [blueBox, redBox]
        )
        let centre = bitmap.pixel(100, 100)
        #expect(centre.b > 200)
        #expect(centre.r < 60)
    }

    @Test("Rotation is applied clockwise about the frame's centre")
    func appliesRotation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = try assetsDirectory(in: directory)
        // Red on top, blue at the bottom: an asymmetric marker, because a
        // rectangle or a line looks the same either way a quarter turn is
        // taken.
        try writePNG(
            try #require(twoToneImage(width: 40, height: 40)),
            to: assets.appendingPathComponent("marker.png")
        )

        let bitmap = try render(
            size: CGSize(width: 200, height: 200),
            elements: [
                element(
                    .image(assetName: "marker.png"),
                    frame: ElementFrame(x: 80, y: 80, width: 40, height: 40, rotation: .pi / 2)
                )
            ],
            assets: assets
        )

        // A quarter turn clockwise puts the image's top edge on the right.
        let right = bitmap.pixel(115, 100)
        let left = bitmap.pixel(85, 100)
        #expect(right.r > 200 && right.b < 80, "the red top edge turned right")
        #expect(left.b > 200 && left.r < 80, "the blue bottom edge turned left")
    }

    // MARK: - Helpers

    private func render(
        size: CGSize,
        elements: [PageElement],
        assets: URL? = nil,
        scale: CGFloat = 1
    ) throws -> TestBitmap {
        let image = try #require(
            PageRenderer.image(
                strokes: [],
                pageSize: size,
                template: Self.paper,
                elements: elements,
                assetsDirectory: assets,
                scale: scale
            )
        )
        return try #require(TestBitmap(image: image))
    }

    private func element(
        _ content: ElementContent,
        frame: ElementFrame,
        zIndex: Int = 0
    ) -> PageElement {
        PageElement(
            id: UUID(),
            layerID: UUID(),
            frame: frame,
            zIndex: zIndex,
            updatedAt: Date(timeIntervalSince1970: 0),
            content: content
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkKitElements-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func assetsDirectory(in directory: URL) throws -> URL {
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        return assets
    }

    private func solidImage(width: Int, height: Int, color: RGBAColor) -> CGImage? {
        guard let context = bitmapContext(width: width, height: height) else { return nil }
        context.setFillColor(CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Red top half, blue bottom half, so rotation shows which way is up.
    private func twoToneImage(width: Int, height: Int) -> CGImage? {
        guard let context = bitmapContext(width: width, height: height) else { return nil }
        let half = CGFloat(height) / 2
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.05, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: 0, y: half, width: CGFloat(width), height: half))
        context.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: half))
        return context.makeImage()
    }

    /// A straight, solid stroke across the page at `y`, for checking ink order.
    private func horizontalStroke(y: CGFloat, color: InkPlatformColor) -> PKStroke {
        let points = (0..<9).map { index -> PKStrokePoint in
            let t = Double(index) / 8
            return PKStrokePoint(
                location: CGPoint(x: 60 + 80 * t, y: y),
                timeOffset: t * 0.3,
                size: CGSize(width: 16, height: 16),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2,
                secondaryScale: 1,
                threshold: 0,
                lateralJitter: 0
            )
        }
        let path = PKStrokePath(
            controlPoints: points,
            creationDate: Date(timeIntervalSinceReferenceDate: 780_000_000)
        )
        return PKStroke(
            ink: PKInk(.pen, color: color),
            path: path,
            transform: .identity,
            mask: nil,
            randomSeed: 1
        )
    }

    private func bitmapContext(width: Int, height: Int) -> CGContext? {        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            Issue.record("could not open \(url.lastPathComponent) for writing")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            Issue.record("could not write \(url.lastPathComponent)")
            return
        }
    }

    /// Two 200×280 pages, each with a black bar in its top half: page 0 on the
    /// left, page 1 on the right, so a renderer that always draws page 0 fails.
    private func writeTwoPagePDF(to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 280)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            Issue.record("could not create a PDF context")
            return
        }

        for pageIndex in 0..<2 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(mediaBox)
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            // PDF coordinates grow upwards, so the top half is the larger y.
            let bar = pageIndex == 0
                ? CGRect(x: 20, y: 168, width: 60, height: 84)
                : CGRect(x: 120, y: 168, width: 60, height: 84)
            context.fill(bar)
            context.endPDFPage()
        }
        context.closePDF()
    }
}

// MARK: - Pixel access

/// A rendered page flattened to sRGB, rows numbered from the top of the page.
private struct TestBitmap {
    let width: Int
    let height: Int
    let data: [UInt8]

    init?(image: InkImage) {
        guard let cgImage = Self.cgImage(of: image) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

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
                  )
            else { return false }
            // CG bitmap data starts at the top row, and `draw` places an
            // image's top at the rect's top in this y-up space, so row 0 of
            // `data` is the top of the page without any flip.
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        self.width = width
        self.height = height
        self.data = data
    }

    func pixel(_ x: Int, _ y: Int) -> Pixel {
        let x = min(max(x, 0), width - 1)
        let y = min(max(y, 0), height - 1)
        let index = (y * width + x) * 4
        return Pixel(r: Int(data[index]), g: Int(data[index + 1]), b: Int(data[index + 2]))
    }

    var nonPaperPixels: Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where !pixel(x, y).isPaper {
                count += 1
            }
        }
        return count
    }

    var darkPixels: Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where pixel(x, y).isDark {
                count += 1
            }
        }
        return count
    }

    private static func cgImage(of image: InkImage) -> CGImage? {
        #if os(iOS)
        image.cgImage
        #else
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

private struct Pixel {
    let r: Int
    let g: Int
    let b: Int

    var isPaper: Bool { r > 245 && g > 245 && b > 245 }
    var isInk: Bool { isDark }
    var isDark: Bool { r < 100 && g < 100 && b < 100 }
}
