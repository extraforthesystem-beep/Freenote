import CoreGraphics
import Foundation

/// Turns a stroke's centre line into a filled outline, for vector export.
///
/// Pure geometry: no PencilKit, UIKit or AppKit, so it is testable anywhere.
///
/// The outline is a variable-width envelope. Each sample is a disc of the
/// stroke's half-width; the stroke is the union of those discs and the tangent
/// hulls between neighbours. It is built as one `CGPath` of closed subpaths
/// that all wind the same way, so filling with the nonzero rule paints their
/// union exactly once (no darker overlaps for translucent ink):
///
/// - The centre line is split into *runs* at every vertex whose local radius
///   of curvature is smaller than the stroke's half-width. Within a run the
///   inner side cannot fold back on itself, so the run's envelope is a simple
///   closed curve.
/// - Each run is its left side (Catmull-Rom smoothed into cubics), a round
///   cap, its right side back, and a round cap. Neighbouring runs share their
///   end sample, so their caps overlap and the join reads round.
/// - A run of one sample (a dot) is a disc.
public enum StrokeOutline {
    /// One centre-line sample: where it is and the half-width of ink there.
    public struct Sample: Equatable, Sendable {
        public var point: CGPoint
        public var radius: CGFloat

        public init(point: CGPoint, radius: CGFloat) {
            self.point = point
            self.radius = radius
        }

        public init(x: CGFloat, y: CGFloat, radius: CGFloat) {
            self.init(point: CGPoint(x: x, y: y), radius: radius)
        }
    }

    /// The smallest half-width an outline is built with, so hairline strokes
    /// still show up in print.
    public static let minimumRadius: CGFloat = 0.1

    /// The filled outline of the stroke through `samples`. Empty when there is
    /// no finite sample.
    public static func path(for samples: [Sample], tolerance: CGFloat = 0.25) -> CGPath {
        let path = CGMutablePath()
        let cleaned = simplify(prune(samples), tolerance: tolerance)
        guard !cleaned.isEmpty else { return path }
        if cleaned.count == 1 {
            addDisc(cleaned[0], to: path)
            return path
        }
        for run in runs(of: cleaned) {
            if run.count == 1 {
                addDisc(run[0], to: path)
            } else {
                addEnvelope(of: run, to: path)
            }
        }
        return path
    }

    // MARK: - Preparation

    /// Drops non-finite samples, clamps radii, and removes samples whose disc
    /// lies inside a neighbour's: such a sample adds no ink and would give the
    /// envelope a tangent that does not exist.
    static func prune(_ samples: [Sample]) -> [Sample] {
        var result: [Sample] = []
        result.reserveCapacity(samples.count)
        for sample in samples {
            guard sample.point.x.isFinite, sample.point.y.isFinite, sample.radius.isFinite else { continue }
            let current = Sample(point: sample.point, radius: max(sample.radius, minimumRadius))
            // Pop earlier samples the new disc swallows.
            while let last = result.last, distance(last.point, current.point) + last.radius <= current.radius {
                result.removeLast()
            }
            if let last = result.last, distance(last.point, current.point) + current.radius <= last.radius {
                continue
            }
            result.append(current)
        }
        return result
    }

    /// Drops samples that lie within `tolerance` of the straight run between
    /// their kept neighbours, in both position and half-width
    /// (Douglas-Peucker). Dense samples along straight or gently curving ink
    /// collapse to a few, which keeps exported files small; the Catmull-Rom
    /// sides then curve smoothly through what is left.
    static func simplify(_ samples: [Sample], tolerance: CGFloat) -> [Sample] {
        guard samples.count > 2, tolerance > 0 else { return samples }
        var keep = [Bool](repeating: false, count: samples.count)
        keep[0] = true
        keep[samples.count - 1] = true
        var stack: [(Int, Int)] = [(0, samples.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }
            let a = samples[first], b = samples[last]
            let chord = vector(a.point, b.point)
            let chordLength = length(chord)
            var worst = -CGFloat.infinity
            var worstIndex = first
            for index in (first + 1)..<last {
                let sample = samples[index]
                let offset = vector(a.point, sample.point)
                let t: CGFloat
                let off: CGFloat
                if chordLength > 1e-9 {
                    t = max(0, min(1, dot(offset, chord) / (chordLength * chordLength)))
                    off = abs(offset.x * chord.y - offset.y * chord.x) / chordLength
                } else {
                    t = 0
                    off = length(offset)
                }
                let radiusError = abs(sample.radius - (a.radius + (b.radius - a.radius) * t))
                // Also measure along the chord, so a stroke that doubles back on
                // a straight line keeps its turning point.
                let along = chordLength > 1e-9 ? dot(offset, chord) / chordLength : 0
                let overshoot = max(0, -along, along - chordLength)
                let error = max(off, radiusError, overshoot)
                if error > worst {
                    worst = error
                    worstIndex = index
                }
            }
            if worst > tolerance {
                keep[worstIndex] = true
                stack.append((first, worstIndex))
                stack.append((worstIndex, last))
            }
        }
        return samples.indices.filter { keep[$0] }.map { samples[$0] }
    }

    /// Splits `samples` at vertices sharp enough to fold the envelope. The
    /// split vertex ends one run and starts the next.
    static func runs(of samples: [Sample]) -> [[Sample]] {
        guard samples.count > 2 else { return [samples] }
        var runs: [[Sample]] = []
        var current: [Sample] = [samples[0]]
        for index in 1..<(samples.count - 1) {
            let previous = samples[index - 1]
            let sample = samples[index]
            let next = samples[index + 1]
            current.append(sample)

            let incoming = vector(previous.point, sample.point)
            let outgoing = vector(sample.point, next.point)
            let turn = abs(angle(between: incoming, and: outgoing))
            guard turn > 1e-6 else { continue }
            // Radius of the circle through the corner: the mean of the two
            // segment lengths spread over the turn.
            let curvatureRadius = (length(incoming) + length(outgoing)) / 2 / turn
            if curvatureRadius < sample.radius * 1.05 || turn > .pi / 3 {
                runs.append(current)
                current = [sample]
            }
        }
        current.append(samples[samples.count - 1])
        runs.append(current)
        return runs
    }

    // MARK: - Building

    private static func addDisc(_ sample: Sample, to path: CGMutablePath) {
        // Decreasing angle (clockwise in a y-up frame), the same winding as
        // every envelope below.
        path.addArc(
            center: sample.point,
            radius: sample.radius,
            startAngle: 0,
            endAngle: -2 * .pi,
            clockwise: true
        )
        path.closeSubpath()
    }

    /// Adds the closed envelope of a run of at least two samples.
    private static func addEnvelope(of run: [Sample], to path: CGMutablePath) {
        let count = run.count
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(count)
        right.reserveCapacity(count)

        for index in 0..<count {
            let normal = vertexNormal(in: run, at: index)
            let sample = run[index]
            left.append(rounded(sample.point + normal * sample.radius))
            right.append(rounded(sample.point - normal * sample.radius))
        }

        let startDirection = unit(vector(run[0].point, run[1].point))
        let endDirection = unit(vector(run[count - 2].point, run[count - 1].point))

        // With `left` = direction rotated +90°, going round the start, forward
        // on the left, round the end and back on the right winds clockwise in
        // a y-up frame (decreasing angle) for every run.
        path.move(to: right[0])
        addCap(
            around: run[0],
            from: angleOf(right[0] - run[0].point),
            sweepingVia: startDirection * -1,
            to: path
        )
        addSmoothed(left, to: path)
        addCap(
            around: run[count - 1],
            from: angleOf(left[count - 1] - run[count - 1].point),
            sweepingVia: endDirection,
            to: path
        )
        addSmoothed(Array(right.reversed()), to: path)
        path.closeSubpath()
    }

    /// Adds a half-circle around `sample`, starting at angle `start` and
    /// bulging out along `bulge`.
    private static func addCap(
        around sample: Sample,
        from start: CGFloat,
        sweepingVia bulge: CGPoint,
        to path: CGMutablePath
    ) {
        // Choose the sweep direction whose midpoint faces `bulge`.
        let midCounterClockwise = CGPoint(x: cos(start + .pi / 2), y: sin(start + .pi / 2))
        let clockwise = dot(midCounterClockwise, bulge) < 0
        path.addArc(
            center: sample.point,
            radius: sample.radius,
            startAngle: start,
            endAngle: start + (clockwise ? -.pi : .pi),
            clockwise: clockwise
        )
    }

    /// Continues `path` (whose current point is `points[0]`) through `points`
    /// as a Catmull-Rom spline converted to cubics, so curves are not faceted.
    private static func addSmoothed(_ points: [CGPoint], to path: CGMutablePath) {
        guard points.count > 1 else { return }
        if path.currentPoint != points[0] {
            path.addLine(to: points[0])
        }
        guard points.count > 2 else {
            path.addLine(to: points[1])
            return
        }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let control1 = p1 + (p2 - p0) * (1.0 / 6.0)
            let control2 = p2 - (p3 - p1) * (1.0 / 6.0)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
    }

    /// The unit normal (direction rotated +90°) at a run vertex: the mean of
    /// the adjacent segments' normals.
    private static func vertexNormal(in run: [Sample], at index: Int) -> CGPoint {
        let count = run.count
        let incoming = index > 0 ? unit(vector(run[index - 1].point, run[index].point)) : nil
        let outgoing = index < count - 1 ? unit(vector(run[index].point, run[index + 1].point)) : nil
        let direction: CGPoint
        switch (incoming, outgoing) {
        case let (incoming?, outgoing?):
            let sum = incoming + outgoing
            direction = length(sum) > 1e-9 ? unit(sum) : outgoing
        case let (incoming?, nil): direction = incoming
        case let (nil, outgoing?): direction = outgoing
        case (nil, nil): direction = CGPoint(x: 1, y: 0)
        }
        return CGPoint(x: -direction.y, y: direction.x)
    }

    /// A polyline with points closer than `tolerance` to the straight line
    /// between their kept neighbours removed, for ink annotation paths.
    public static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        simplify(points.map { Sample(point: $0, radius: 0) }, tolerance: tolerance).map(\.point)
    }

    /// Snaps to 1/100 pt: invisible in print, and PDF numbers stay short.
    private static func rounded(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x * 100).rounded() / 100, y: (point.y * 100).rounded() / 100)
    }

    // MARK: - Vector maths

    private static func vector(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
        CGPoint(x: to.x - from.x, y: to.y - from.y)
    }

    private static func length(_ v: CGPoint) -> CGFloat {
        (v.x * v.x + v.y * v.y).squareRoot()
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        length(vector(a, b))
    }

    private static func unit(_ v: CGPoint) -> CGPoint {
        let l = length(v)
        return l > 1e-12 ? CGPoint(x: v.x / l, y: v.y / l) : CGPoint(x: 1, y: 0)
    }

    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.x + a.y * b.y
    }

    private static func angle(between a: CGPoint, and b: CGPoint) -> CGFloat {
        atan2(a.x * b.y - a.y * b.x, dot(a, b))
    }

    private static func angleOf(_ v: CGPoint) -> CGFloat {
        atan2(v.y, v.x)
    }
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }
}
