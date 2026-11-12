import CoreGraphics
import Foundation
import NoteCore
import PencilKit

#if os(iOS)
import UIKit
/// A rendered page: `UIImage` on iOS, `NSImage` on macOS.
public typealias InkImage = UIImage
#else
import AppKit
/// A rendered page: `UIImage` on iOS, `NSImage` on macOS.
public typealias InkImage = NSImage
#endif

/// Renders a page's strokes onto its paper, for thumbnails and the read-only Mac view.
public enum PageRenderer {
    /// Draws `template` and then the strokes of `strokes`, at `scale`.
    ///
    /// Returns `nil` for an empty page size or when a bitmap cannot be created.
    public static func image(
        strokes: [StrokeRecord],
        pageSize: CGSize,
        template: PageTemplate,
        scale: CGFloat = 2
    ) -> InkImage? {
        guard pageSize.width > 0, pageSize.height > 0, scale > 0 else { return nil }
        let pixelWidth = Int((pageSize.width * scale).rounded(.up))
        let pixelHeight = Int((pageSize.height * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // One flip, so everything below is drawn in page points with y growing down.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)

        drawPaper(in: context, pageSize: pageSize, template: template)
        drawInk(in: context, strokes: strokes, pageSize: pageSize, scale: scale)

        guard let cgImage = context.makeImage() else { return nil }
        return platformImage(cgImage, pageSize: pageSize, scale: scale)
    }

    private static func platformImage(_ cgImage: CGImage, pageSize: CGSize, scale: CGFloat) -> InkImage {
        #if os(iOS)
        UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        #else
        NSImage(cgImage: cgImage, size: pageSize)
        #endif
    }

    private static func drawPaper(in context: CGContext, pageSize: CGSize, template: PageTemplate) {
        let page = CGRect(origin: .zero, size: pageSize)
        context.setFillColor(cgColor(template.paperColor))
        context.fill(page)

        guard template.spacing > 0 else { return }
        context.setStrokeColor(cgColor(template.lineColor))
        context.setLineWidth(1)
        let lines = CGMutablePath()

        switch template.kind {
        case "ruled":
            var y = template.spacing
            while y < pageSize.height {
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: pageSize.width, y: y))
                y += template.spacing
            }
        case "grid":
            var y = template.spacing
            while y < pageSize.height {
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: pageSize.width, y: y))
                y += template.spacing
            }
            var x = template.spacing
            while x < pageSize.width {
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: pageSize.height))
                x += template.spacing
            }
        case "dotted":
            context.setFillColor(cgColor(template.lineColor))
            var y = template.spacing
            while y < pageSize.height {
                var x = template.spacing
                while x < pageSize.width {
                    context.fillEllipse(
                        in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)
                    )
                    x += template.spacing
                }
                y += template.spacing
            }
        default:
            break
        }

        context.addPath(lines)
        context.strokePath()
    }

    private static func drawInk(
        in context: CGContext,
        strokes: [StrokeRecord],
        pageSize: CGSize,
        scale: CGFloat
    ) {
        let drawing = StrokeCodec.drawing(from: strokes)
        guard !drawing.strokes.isEmpty else { return }
        let inkImage = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: scale)
        guard let ink = inkCGImage(inkImage) else { return }

        // The context is flipped for page coordinates, so undo the flip locally
        // or the ink would land upside down relative to the paper.
        context.saveGState()
        context.translateBy(x: 0, y: pageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(ink, in: CGRect(origin: .zero, size: pageSize))
        context.restoreGState()
    }

    private static func inkCGImage(_ image: InkImage) -> CGImage? {
        #if os(iOS)
        image.cgImage
        #else
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }

    private static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a)
    }
}
