import CoreGraphics
import CoreText
import Foundation
import ImageIO
import NoteCore
import PDFKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Draws the non-ink objects of a page (PDF pages, images, text boxes and
/// shapes) into the same flipped page space `TemplateRenderer` and
/// `PageRenderer` use, so the live page, thumbnails, the Mac reader and PDF
/// export cannot disagree about what a page contains.
enum PageElementRenderer {
    /// Draws `elements` from back to front.
    ///
    /// Order is `zIndex` ascending, ties broken by `id` so that a page renders
    /// identically however its element array happens to be ordered.
    ///
    /// `drawsShadows` is off for vector PDF export: a Quartz shadow in a PDF
    /// context is written as a bitmap, which would rasterise part of the page.
    static func draw(
        _ elements: [PageElement],
        in context: CGContext,
        assetsDirectory: URL?,
        drawsShadows: Bool = true
    ) {
        let ordered = elements.sorted { left, right in
            left.zIndex == right.zIndex
                ? left.id.uuidString < right.id.uuidString
                : left.zIndex < right.zIndex
        }
        for element in ordered {
            draw(element, in: context, assetsDirectory: assetsDirectory, drawsShadows: drawsShadows)
        }
    }

    // MARK: - One element

    private static func draw(
        _ element: PageElement,
        in context: CGContext,
        assetsDirectory: URL?,
        drawsShadows: Bool
    ) {
        let frame = element.frame
        let rect = CGRect(
            x: frame.x,
            y: frame.y,
            width: frame.width,
            height: frame.height
        )
        guard rect.minX.isFinite, rect.minY.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0
        else { return }

        context.saveGState()
        defer { context.restoreGState() }

        // `ElementFrame.rotation` is in radians, clockwise about the centre. In
        // this y-down page space a positive `rotate(by:)` turns clockwise on
        // screen, so the angle is used as stored.
        let rotation = CGFloat(frame.rotation)
        if rotation.isFinite, rotation != 0 {
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: rotation)
            context.translateBy(x: -centre.x, y: -centre.y)
        }

        // Nothing may paint outside its own frame.
        context.clip(to: rect)

        // Content is drawn in an unflipped space: origin at the frame's
        // bottom-left corner, y growing up, which is what CoreText and PDF
        // expect. Text and PDF pages read upright because this flip cancels the
        // page's own flip.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        let box = CGRect(origin: .zero, size: rect.size)

        switch element.content {
        case let .pdfPage(assetName, pageIndex):
            drawPDFPage(
                assetName: assetName,
                pageIndex: pageIndex,
                in: context,
                box: box,
                assetsDirectory: assetsDirectory
            )
        case let .image(assetName):
            drawImage(
                assetName: assetName,
                in: context,
                box: box,
                assetsDirectory: assetsDirectory
            )
        case let .text(text, fontName, fontSize, color):
            drawText(
                text,
                fontName: fontName,
                fontSize: fontSize,
                color: color,
                style: element.textStyle,
                in: context,
                box: box
            )
        case let .shape(kind, stroke, fill, lineWidth):
            drawShape(
                kind: kind,
                stroke: stroke,
                fill: fill,
                lineWidth: lineWidth,
                in: context,
                box: box
            )
        case let .stickyNote(text, color):
            drawStickyNote(text, color: color, in: context, box: box, drawsShadow: drawsShadows)
        case let .tape(color):
            drawTape(color: color, in: context, box: box)
        }
    }

    // MARK: - PDF pages

    /// Draws one page of a PDF asset, aspect-fit into `box`.
    ///
    /// A missing file, a missing page or an asset that is not a PDF is skipped:
    /// a page must still render when one of its elements is broken.
    private static func drawPDFPage(
        assetName: String,
        pageIndex: Int,
        in context: CGContext,
        box: CGRect,
        assetsDirectory: URL?
    ) {
        guard let assetsDirectory, pageIndex >= 0 else { return }
        let url = assetsDirectory.appendingPathComponent(assetName)
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex)
        else { return }

        // A page reference draws the real vector content, and
        // `getDrawingTransform` applies the page's own /Rotate and centres it in
        // `box`, so rotated and scanned pages read upright.
        if let pageRef = page.pageRef {
            let pageBox = pageRef.getBoxRect(.mediaBox)
            guard pageBox.width > 0, pageBox.height > 0 else { return }
            let transform = pageRef.getDrawingTransform(
                .mediaBox,
                rect: box,
                rotate: 0,
                preserveAspectRatio: true
            )
            context.saveGState()
            context.concatenate(transform)
            context.drawPDFPage(pageRef)
            context.restoreGState()
            return
        }

        // A page PDFKit can describe but not hand to CoreGraphics: fall back to
        // its thumbnail rather than losing the page.
        guard let thumbnail = PageRenderer.cgImage(of: page.thumbnail(of: box.size, for: .mediaBox))
        else { return }
        context.draw(thumbnail, in: box)
    }

    // MARK: - Images

    /// Draws an image asset, aspect-fit into `box`.
    ///
    /// A missing or corrupt file is skipped.
    private static func drawImage(
        assetName: String,
        in context: CGContext,
        box: CGRect,
        assetsDirectory: URL?
    ) {
        guard let assetsDirectory else { return }
        let url = assetsDirectory.appendingPathComponent(assetName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0
        else { return }

        let size = CGSize(width: image.width, height: image.height)
        context.draw(image, in: aspectFit(size, in: box))
    }

    // MARK: - Text

    /// Draws wrapped, multi-line text inside `box`.
    ///
    /// An unavailable font falls back to the system font, so text is never lost
    /// because a notebook was written on a device that had a font this one does
    /// not.
    private static func drawText(
        _ text: String,
        fontName: String,
        fontSize: Double,
        color: RGBAColor,
        style: TextStyle?,
        in context: CGContext,
        box: CGRect
    ) {
        guard !text.isEmpty else { return }
        let size = CGFloat(fontSize) > 0 ? CGFloat(fontSize) : 12
        let font = styledFont(named: fontName, size: size, style: style)

        let paragraph = NSMutableParagraphStyle()
        switch style?.alignment {
        case .center: paragraph.alignment = .center
        case .trailing: paragraph.alignment = .right
        case .justified: paragraph.alignment = .justified
        default: paragraph.alignment = .left
        }
        paragraph.lineSpacing = CGFloat(style?.lineSpacing ?? 0)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: cgColor(color),
            .paragraphStyle: paragraph,
        ]
        if style?.isUnderline == true {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: box, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )

        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func textFont(named name: String, size: CGFloat) -> CTFont {
        if !name.isEmpty, platformFontExists(named: name) {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func styledFont(named name: String, size: CGFloat, style: TextStyle?) -> CTFont {
        let base = textFont(named: name, size: size)
        guard style?.isBold == true || style?.isItalic == true else { return base }

        var traits: CTFontSymbolicTraits = []
        if style?.isBold == true { traits.insert(.boldTrait) }
        if style?.isItalic == true { traits.insert(.italicTrait) }
        return CTFontCreateCopyWithSymbolicTraits(base, 0, nil, traits, traits) ?? base
    }

    private static func platformFontExists(named name: String) -> Bool {
        #if os(iOS)
        UIFont(name: name, size: 12) != nil
        #else
        NSFont(name: name, size: 12) != nil
        #endif
    }

    // MARK: - Shapes

    /// Draws a shape. `"rect"`, `"ellipse"` and `"line"` are understood; any
    /// other kind draws a stroked rectangle so an unknown shape still marks its
    /// frame instead of vanishing.
    ///
    /// A `"line"` runs from the frame's top-left to its bottom-right corner.
    private static func drawShape(
        kind: String,
        stroke: RGBAColor,
        fill: RGBAColor?,
        lineWidth: Double,
        in context: CGContext,
        box: CGRect
    ) {
        let width = CGFloat(lineWidth) > 0 ? CGFloat(lineWidth) : 1
        // Inset so a stroke on the frame's edge is not half clipped away.
        let inset = width / 2
        let rect = box.insetBy(dx: inset, dy: inset)
        let stroked = rect.width > 0 && rect.height > 0 ? rect : box

        let path = CGMutablePath()
        switch kind {
        case "ellipse":
            path.addEllipse(in: stroked)
        case "line":
            path.move(to: CGPoint(x: box.minX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
        default:
            path.addRect(stroked)
        }

        if let fill {
            context.addPath(path)
            context.setFillColor(cgColor(fill))
            context.fillPath()
        }
        context.addPath(path)
        context.setStrokeColor(cgColor(stroke))
        context.setLineWidth(width)
        context.strokePath()
    }

    // MARK: - Sticky notes

    /// Draws a sticky note: a rounded, filled card with a slight drop shadow and
    /// wrapped text inside a padding.
    ///
    /// The card is inset inside the frame so the shadow falls on the page rather
    /// than being clipped away by the frame's clip.
    private static func drawStickyNote(
        _ text: String,
        color: RGBAColor,
        in context: CGContext,
        box: CGRect,
        drawsShadow: Bool
    ) {
        let inset = min(6, min(box.width, box.height) / 4)
        let card = box.insetBy(dx: inset, dy: inset)
        guard card.width > 1, card.height > 1 else { return }
        let radius = min(10, min(card.width, card.height) / 6)
        let path = CGPath(
            roundedRect: card,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.saveGState()
        if drawsShadow {
            context.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 4,
                color: cgColor(RGBAColor(r: 0, g: 0, b: 0, a: 0.18))
            )
        }
        context.addPath(path)
        context.setFillColor(cgColor(color))
        context.fillPath()
        context.restoreGState()

        // A hairline edge keeps a white or very pale note readable on white paper.
        context.addPath(path)
        context.setStrokeColor(cgColor(RGBAColor(r: 0, g: 0, b: 0, a: 0.07)))
        context.setLineWidth(1)
        context.strokePath()

        let padding = min(12, min(card.width, card.height) / 6)
        let textBox = card.insetBy(dx: padding, dy: padding)
        guard textBox.width > 1, textBox.height > 1 else { return }
        drawText(
            text,
            fontName: "System",
            fontSize: 15,
            color: RGBAColor(r: 0.12, g: 0.12, b: 0.14),
            style: .regular,
            in: context,
            box: textBox
        )
    }

    // MARK: - Tape

    /// Draws a piece of tape: a rounded band in its colour with faint diagonal
    /// stripes, so it reads as tape rather than as a filled shape.
    private static func drawTape(
        color: RGBAColor,
        in context: CGContext,
        box: CGRect
    ) {
        guard box.width > 1, box.height > 1 else { return }
        let radius = min(6, box.height / 2)
        let path = CGPath(
            roundedRect: box,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.saveGState()
        context.addPath(path)
        context.setFillColor(cgColor(color))
        // Semi-opaque: tape is nearly, but not entirely, solid in export and
        // thumbnails so it still reads as tape.
        context.setAlpha(0.9 * color.a)
        context.fillPath()
        context.setAlpha(1)

        context.addPath(path)
        context.clip()
        let spacing: CGFloat = 9
        let stripe = RGBAColor(r: 0, g: 0, b: 0, a: 0.06)
        context.setStrokeColor(cgColor(stripe))
        context.setLineWidth(3)
        var x = box.minX - box.height
        while x < box.maxX + box.height {
            context.move(to: CGPoint(x: x, y: box.minY))
            context.addLine(to: CGPoint(x: x + box.height, y: box.maxY))
            x += spacing
        }
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Helpers

    private static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(
            x: box.minX + (box.width - width) / 2,
            y: box.minY + (box.height - height) / 2,
            width: width,
            height: height
        )
    }

    private static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a)
    }
}
