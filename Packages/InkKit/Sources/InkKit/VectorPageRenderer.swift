import CoreGraphics
import Foundation
import NoteCore
import PencilKit

/// Draws a page as vector content into a PDF context, for export.
///
/// Same z-order as `PageRenderer`: paper and template, then elements by
/// `zIndex` (an imported PDF page is a full-page element, drawn with
/// `drawPDFPage` so its text stays text), then ink in `Page.renderStrokes`
/// order (highlighters under pen ink within a layer). Only image elements end
/// up as bitmaps; ink is a filled outline per stroke (see `StrokeOutline`).
///
/// Exports always use the stored paper colour (light), never a display theme.
public enum VectorPageRenderer {
    /// Spacing, in points, between the samples taken along each stroke.
    static let sampleSpacing: CGFloat = 1.5

    /// One stroke's ink as a fillable outline, in page points (y down).
    public struct InkOutline {
        /// Filled with the nonzero rule.
        public var path: CGPath
        /// Colour with the stroke's effective opacity folded into alpha.
        public var color: RGBAColor
        /// Highlighters multiply onto what is under them.
        public var isHighlighter: Bool
        /// Clip, in page points, from a partially erased stroke.
        public var mask: CGPath?
    }

    /// Draws `page` into `context`, whose user space is the PDF page: origin
    /// at the bottom-left, y up, one unit per page point.
    ///
    /// `includeTemplate` off paints plain white paper instead of the template.
    /// `includeInk` off skips the strokes (they are written as annotations
    /// instead).
    public static func draw(
        page: Page,
        in context: CGContext,
        assetsDirectory: URL?,
        includeTemplate: Bool = true,
        includeInk: Bool = true
    ) {
        let size = CGSize(width: page.width, height: page.height)
        guard size.width > 0, size.height > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }
        // The same single flip `PageRenderer` uses, so the shared template and
        // element drawing code works in page points with y growing down.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        if includeTemplate {
            context.saveGState()
            TemplateRenderer.draw(page.template, in: context, pageSize: size)
            context.restoreGState()
        } else {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }

        PageElementRenderer.draw(
            page.visibleElements,
            in: context,
            assetsDirectory: assetsDirectory,
            drawsShadows: false
        )

        guard includeInk else { return }
        for record in page.renderStrokes {
            guard let outline = inkOutline(for: record) else { continue }
            fill(outline, in: context)
        }
    }

    /// Fills one stroke's outline into a y-down page context.
    static func fill(_ outline: InkOutline, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        if let mask = outline.mask {
            context.addPath(mask)
            context.clip()
        }
        if outline.isHighlighter {
            context.setBlendMode(.multiply)
        }
        context.setFillColor(
            CGColor(
                srgbRed: outline.color.r,
                green: outline.color.g,
                blue: outline.color.b,
                alpha: outline.color.a
            )
        )
        context.addPath(outline.path)
        context.fillPath(using: .winding)
    }

    /// The filled outline of `record` in page points, or `nil` for a stroke
    /// PencilKit cannot decode.
    ///
    /// Samples come from PencilKit's own spline (`interpolatedPoints`), so the
    /// curve and width follow what the canvas draws. Pencil, crayon and
    /// watercolour textures are approximated as solid ink at the stroke's mean
    /// opacity.
    public static func inkOutline(for record: StrokeRecord) -> InkOutline? {
        guard let stroke = try? StrokeCodec.stroke(from: record) else { return nil }
        let samples = centreLine(of: stroke)
        guard !samples.isEmpty else { return nil }

        let outline = StrokeOutline.path(for: samples.map {
            StrokeOutline.Sample(point: $0.location, radius: $0.radius)
        })
        var transform = stroke.transform
        let path = outline.copy(using: &transform) ?? outline

        var mask: CGPath?
        if let platformMask = stroke.mask {
            mask = platformMask.cgPath.copy(using: &transform)
        }

        let meanOpacity = samples.map(\.opacity).reduce(0, +) / CGFloat(samples.count)
        var color = record.tool.color
        color.a = min(1, max(0, color.a * Double(meanOpacity)))
        return InkOutline(
            path: path,
            color: color,
            isHighlighter: record.tool.isHighlighter,
            mask: mask
        )
    }

    /// The stroke's centre line in page points (transform applied), the
    /// median ink width scaled by the transform, and the effective colour.
    /// Used for editable PDF ink annotations.
    public static func centreLine(for record: StrokeRecord) -> (points: [CGPoint], width: CGFloat, color: RGBAColor)? {
        guard let stroke = try? StrokeCodec.stroke(from: record) else { return nil }
        let samples = centreLine(of: stroke)
        guard !samples.isEmpty else { return nil }
        let transform = stroke.transform
        let points = samples.map { $0.location.applying(transform) }
        let widths = samples.map { $0.radius * 2 }.sorted()
        let scale = (abs(transform.a * transform.d - transform.b * transform.c)).squareRoot()
        let width = widths[widths.count / 2] * (scale > 0 ? scale : 1)
        let meanOpacity = samples.map(\.opacity).reduce(0, +) / CGFloat(samples.count)
        var color = record.tool.color
        color.a = min(1, max(0, color.a * Double(meanOpacity)))
        return (points, width, color)
    }

    struct CentreSample {
        var location: CGPoint
        var radius: CGFloat
        var opacity: CGFloat
    }

    /// Samples PencilKit's interpolated stroke path at `sampleSpacing`, in the
    /// stroke's own (untransformed) coordinates.
    static func centreLine(of stroke: PKStroke) -> [CentreSample] {
        let path = stroke.path
        guard path.count > 0 else { return [] }
        let curve = nibCurve(for: stroke.ink.inkType)
        func sample(_ point: PKStrokePoint) -> CentreSample {
            CentreSample(
                location: point.location,
                radius: drawnWidth(forNibSize: point.size.width, curve: curve) / 2,
                opacity: max(0, min(1, point.opacity))
            )
        }

        var samples: [CentreSample] = []
        for point in path.interpolatedPoints(by: .distance(sampleSpacing)) {
            samples.append(sample(point))
        }
        // `interpolatedPoints` can stop short of the last control point; keep
        // the stroke's real end so caps land where the canvas puts them.
        if let last = path.last, let end = samples.last?.location,
           hypot(end.x - last.location.x, end.y - last.location.y) > 0.01
        {
            samples.append(sample(path.interpolatedPoint(at: CGFloat(path.count - 1))))
        }
        if samples.isEmpty {
            samples = path.map(sample)
        }
        return samples
    }

    // MARK: - Nib width

    /// How wide PencilKit actually draws a point of a given `size.width`, per
    /// ink, as `(size, drawn width)` pairs in points.
    ///
    /// PencilKit does not draw a point at its nominal size: a pen point of
    /// size 4 is 4 pt wide, but size 8 is 12 pt and size 2 is invisible.
    /// These curves were measured from `PKDrawing.image` (horizontal and
    /// vertical strokes, force and speed varied: neither changed the width).
    /// Chisel nibs (marker, fountain pen) are thinner or thicker depending on
    /// direction; the table holds their width at 45°, the round nib that puts
    /// down the same amount of ink.
    static func nibCurve(for inkType: PKInk.InkType) -> [(size: CGFloat, width: CGFloat)] {
        switch inkType {
        case .pen, .monoline:
            [(0, 0), (2, 0), (32, 60)]
        case .fountainPen:
            [(0, 0), (2, 0), (32, 44.4)]
        case .marker:
            [(0, 0), (1, 0.74), (2, 1.54), (4, 3.11), (8, 6.42), (12, 10.07), (16, 14.06), (24, 23.02), (32, 32.67)]
        case .pencil:
            [(0, 0), (1, 0.87), (2, 3.11), (3, 4.77), (4, 6.66), (6, 11), (8, 14.55), (12, 20.82), (16, 27.9), (24, 43.68), (32, 50.13)]
        case .watercolor:
            [(0, 0), (1, 1.49), (2, 3.23), (4, 6.46), (8, 12.97), (16, 26.11), (32, 50.47)]
        case .crayon:
            [(0, 0), (1, 1.9), (4, 4.5), (8, 9), (16, 24), (32, 40)]
        case .reed:
            [(0, 0), (1, 1.3), (2, 2.84), (4, 5.1), (8, 10.13), (16, 21.67), (32, 42.99)]
        default:
            [(0, 0), (1, 1)]
        }
    }

    /// The drawn width for a nib size, interpolated along `curve` and
    /// extended along its last segment.
    static func drawnWidth(forNibSize size: CGFloat, curve: [(size: CGFloat, width: CGFloat)]) -> CGFloat {
        guard size.isFinite, size > 0, curve.count > 1 else { return 0 }
        var index = 1
        while index < curve.count - 1, curve[index].size < size {
            index += 1
        }
        let a = curve[index - 1], b = curve[index]
        let t = (size - a.size) / max(b.size - a.size, 1e-9)
        return max(0, a.width + (b.width - a.width) * t)
    }
}
