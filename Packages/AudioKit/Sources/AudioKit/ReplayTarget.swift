import CoreGraphics
import Foundation
import NoteCore

/// Finds the stroke under a tap, so tapping ink can replay the audio from the
/// moment that ink was written.
public enum ReplayTarget {
    /// The stroke nearest to `point`, in page points, when it comes within
    /// `tolerance`. A stroke point counts, and so does the line between two
    /// neighbouring points, so tapping the middle of a long stroke finds it.
    ///
    /// Overlapping ink ties resolve to the newest stroke: the later moment is the
    /// one the reader was looking at.
    public static func nearestStroke(
        to point: CGPoint,
        in strokes: [StrokeRecord],
        within tolerance: CGFloat = 22
    ) -> StrokeRecord? {
        guard point.x.isFinite, point.y.isFinite, tolerance >= 0 else { return nil }
        let limit = Double(tolerance * tolerance)

        var best: (stroke: StrokeRecord, distance: Double)?
        for stroke in strokes {
            guard let distance = squaredDistance(from: point, to: stroke), distance <= limit else {
                continue
            }
            if let current = best {
                if distance < current.distance
                    || (distance == current.distance
                        && stroke.createdAt > current.stroke.createdAt) {
                    best = (stroke, distance)
                }
            } else {
                best = (stroke, distance)
            }
        }
        return best?.stroke
    }

    /// Squared distance from `point` to a stroke's polyline, or nil when the
    /// stroke has no usable points.
    static func squaredDistance(from point: CGPoint, to stroke: StrokeRecord) -> Double? {
        let transform = stroke.transform.count == StrokeRecord.transformElementCount
            ? stroke.transform
            : StrokeRecord.identityTransform
        var previous: CGPoint?
        var best: Double?
        for sample in stroke.points {
            let current = CGPoint(
                x: transform[0] * sample.x + transform[2] * sample.y + transform[4],
                y: transform[1] * sample.x + transform[3] * sample.y + transform[5]
            )
            guard current.x.isFinite, current.y.isFinite else {
                previous = nil
                continue
            }
            let distance: Double
            if let previous {
                distance = squaredDistance(from: point, toSegment: previous, current)
            } else {
                distance = squaredDistance(from: point, to: current)
            }
            if let currentBest = best {
                if distance < currentBest { best = distance }
            } else {
                best = distance
            }
            previous = current
        }
        return best
    }

    private static func squaredDistance(from point: CGPoint, to other: CGPoint) -> Double {
        let dx = Double(point.x - other.x)
        let dy = Double(point.y - other.y)
        return dx * dx + dy * dy
    }

    private static func squaredDistance(
        from point: CGPoint,
        toSegment start: CGPoint,
        _ end: CGPoint
    ) -> Double {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return squaredDistance(from: point, to: start) }
        let projection = (Double(point.x - start.x) * dx + Double(point.y - start.y) * dy)
            / lengthSquared
        let t = min(max(projection, 0), 1)
        let closest = CGPoint(
            x: CGFloat(Double(start.x) + t * dx),
            y: CGFloat(Double(start.y) + t * dy)
        )
        return squaredDistance(from: point, to: closest)
    }
}
