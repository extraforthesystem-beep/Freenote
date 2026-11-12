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

        TemplateRenderer.draw(template, in: context, pageSize: pageSize)
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


}
