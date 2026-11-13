import CoreGraphics
import Foundation
import PencilKit

#if os(iOS)
import UIKit
private typealias PlatformBezierPath = UIBezierPath
#else
import AppKit
private typealias PlatformBezierPath = NSBezierPath
#endif

/// Turns a stroke into a dashed or dotted one by clipping it with a mask made
/// of short caps along its centre line.
///
/// The clip reuses the format's per-stroke mask (the field the pixel eraser
/// already writes), so a dashed stroke stays one `StrokeRecord`: it erases,
/// lassos and undoes as one stroke, and the dashes survive a reopen, a
/// thumbnail and a PDF export with no new on-disk field.
public enum StrokeDash {
    /// Lengths in points along the stroke, derived from its drawn width.
    struct Pattern: Equatable {
        var dash: CGFloat
        var gap: CGFloat
    }

    static func pattern(for style: PenLineStyle, width: CGFloat) -> Pattern {
        switch style {
        case .solid:
            Pattern(dash: 0, gap: 0)
        case .dashed:
            Pattern(dash: max(4, width * 3), gap: max(3, width * 2.5))
        case .dotted:
            Pattern(dash: max(1.2, width * 0.8), gap: max(2.5, width * 2))
        }
    }

    /// One dash as a capsule of `halfWidth` ink, from `start` to `end`.
    struct Segment: Equatable {
        var start: CGPoint
        var end: CGPoint
    }

    /// The dash segments along `points` at `style`'s pattern.
    static func segments(along points: [CGPoint], style: PenLineStyle, width: CGFloat) -> [Segment] {
        let pattern = pattern(for: style, width: width)
        guard pattern.dash > 0, pattern.gap > 0, points.count >= 2 else { return [] }
        let walk = PolylineWalk(points)
        guard walk.length > 0 else { return [] }

        var segments: [Segment] = []
        var start: CGFloat = 0
        while start < walk.length {
            let end = min(start + pattern.dash, walk.length)
            if end - start > 0.01 {
                segments.append(Segment(start: walk.point(at: start), end: walk.point(at: end)))
            }
            start += pattern.dash + pattern.gap
        }
        return segments
    }

    /// `stroke` clipped to the dash pattern, or nil for solid ink, a stroke
    /// with no length, or one that already carries a clip.
    public static func masked(_ stroke: PKStroke, style: PenLineStyle) -> PKStroke? {
        guard style != .solid, stroke.mask == nil else { return nil }
        let path = stroke.path
        guard path.count >= 2 else { return nil }

        let points = densified(path)
        guard points.count >= 2 else { return nil }
        // The cap length follows the ink actually drawn, not the nominal nib
        // size: a pencil nib draws nearly twice its size.
        let nominalWidth = path.map { $0.size.width }.max() ?? 0
        let drawnWidth = VectorPageRenderer.drawnWidth(
            forNibSize: CGFloat(max(nominalWidth, 0)),
            curve: VectorPageRenderer.nibCurve(for: stroke.ink.inkType)
        )
        let segments = segments(along: points, style: style, width: drawnWidth)
        guard !segments.isEmpty else { return nil }

        let halfWidth = max(1.5, drawnWidth / 2 + 1)
        let mask = maskPath(for: segments, halfWidth: halfWidth)
        guard !mask.isEmpty else { return nil }

        return PKStroke(
            ink: stroke.ink,
            path: path,
            transform: stroke.transform,
            mask: mask,
            randomSeed: stroke.randomSeed,
            id: stroke.id,
            renderGroupID: stroke.renderGroupID,
            renderState: stroke.renderState
        )
    }

    /// The stroke's control points, densified so a dash boundary can follow a
    /// curve rather than jump between sparse control points.
    static func densified(_ path: PKStrokePath) -> [CGPoint] {
        var points = path.interpolatedPoints(by: .distance(1.5)).map(\.location)
        if points.isEmpty {
            points = (0..<path.count).map { path[$0].location }
        }
        if let first = path.first?.location, points.first != first {
            points.insert(first, at: 0)
        }
        if let last = path.last?.location, points.last != last {
            points.append(last)
        }
        return points
    }

    /// One closed rectangle per dash, all wound the same way so their fill is
    /// the union rather than a cancellation.
    private static func maskPath(for segments: [Segment], halfWidth: CGFloat) -> PlatformBezierPath {
        let path = CGMutablePath()
        for segment in segments {
            let dx = segment.end.x - segment.start.x
            let dy = segment.end.y - segment.start.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            let unit = CGPoint(x: dx / length, y: dy / length)
            let normal = CGPoint(x: -unit.y * halfWidth, y: unit.x * halfWidth)
            // A little overlap at each end keeps the dash from looking clipped
            // by its own mask.
            let overshoot = min(0.5, length / 4)
            let start = CGPoint(
                x: segment.start.x - unit.x * overshoot,
                y: segment.start.y - unit.y * overshoot
            )
            let end = CGPoint(
                x: segment.end.x + unit.x * overshoot,
                y: segment.end.y + unit.y * overshoot
            )
            path.move(to: CGPoint(x: start.x + normal.x, y: start.y + normal.y))
            path.addLine(to: CGPoint(x: end.x + normal.x, y: end.y + normal.y))
            path.addLine(to: CGPoint(x: end.x - normal.x, y: end.y - normal.y))
            path.addLine(to: CGPoint(x: start.x - normal.x, y: start.y - normal.y))
            path.closeSubpath()
        }
        return PlatformBezierPath(cgPath: path)
    }
}

/// Distance-walking along a polyline, for cutting dashes at exact arc lengths.
struct PolylineWalk {
    private let points: [CGPoint]
    private let distances: [CGFloat]

    /// Total length in points.
    let length: CGFloat

    init(_ points: [CGPoint]) {
        self.points = points
        var walked: [CGFloat] = [0]
        walked.reserveCapacity(points.count)
        for index in 1..<max(points.count, 1) {
            walked.append(walked[index - 1] + hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y
            ))
        }
        distances = walked
        length = walked.last ?? 0
    }

    /// The point at `distance` along the path.
    func point(at distance: CGFloat) -> CGPoint {
        guard let first = points.first else { return .zero }
        guard distance > 0 else { return first }
        guard distance < length else { return points.last ?? first }
        var low = 0, high = distances.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if distances[middle] <= distance {
                low = middle
            } else {
                high = middle
            }
        }
        let span = distances[high] - distances[low]
        guard span > 0 else { return points[low] }
        let t = (distance - distances[low]) / span
        let a = points[low], b = points[high]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
