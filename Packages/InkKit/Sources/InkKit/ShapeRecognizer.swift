import CoreGraphics
import Foundation

/// A clean shape that a hand-drawn stroke was recognised as.
public enum RecognizedShape: Equatable, Sendable {
    /// A straight line from the first point to the second.
    case line(CGPoint, CGPoint)
    /// An open path of two to four straight segments through these vertices.
    case polyline([CGPoint])
    /// A closed triangle through three corners.
    case triangle(CGPoint, CGPoint, CGPoint)
    /// A closed four-sided shape, corners in drawing order. A rectangle (axis
    /// aligned or rotated) when the drawn corners were close to right angles,
    /// otherwise the drawn quadrilateral with straightened sides.
    case rectangle([CGPoint])
    /// An ellipse; a circle when the radii are equal. `rotation` is the angle
    /// of the x radius in radians.
    case ellipse(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, rotation: CGFloat)
}

/// Recognises lines, polylines, triangles, rectangles and ellipses in a
/// hand-drawn stroke, for "draw and hold to straighten".
///
/// Pure geometry with no platform dependencies. Every tolerance is relative to
/// the stroke's size, so a shape is recognised the same way at any scale.
/// When nothing fits well the result is nil and the stroke stays freehand.
public struct ShapeRecognizer: Sendable {
    /// Strokes whose bounding box diagonal is shorter than this are never
    /// replaced: a dot or a tiny tick is not a shape.
    public var minimumSize: CGFloat = 12
    /// A line is snapped to a multiple of 45° when within this many degrees.
    public var lineSnapDegrees: CGFloat = 5
    /// A rectangle or ellipse is made axis aligned when within this many degrees.
    public var axisSnapDegrees: CGFloat = 10
    /// An ellipse becomes a circle when its radii differ by less than this fraction.
    public var circleTolerance: CGFloat = 0.1

    public init() {}

    // MARK: - Recognition

    public func recognize(_ input: [CGPoint]) -> RecognizedShape? {
        let points = Self.deduplicated(input)
        guard points.count >= 2 else { return nil }
        let box = Self.bounds(of: points)
        let diagonal = hypot(box.width, box.height)
        guard diagonal >= minimumSize else { return nil }
        // Measured on a lightly simplified path, so jitter does not add length.
        let length = Self.pathLength(Self.simplify(points, epsilon: max(1.5, 0.015 * diagonal)))
        guard length > 0 else { return nil }

        if let line = recognizeLine(points, length: length) { return line }

        let gap = Self.distance(points[0], points[points.count - 1])
        if gap <= max(0.18 * length, 0.25 * diagonal), length > 2 * diagonal * 0.9 {
            if let closed = recognizeClosed(points, diagonal: diagonal) { return closed }
        }
        return recognizeOpenPolyline(points, diagonal: diagonal)
    }

    // MARK: Line

    private func recognizeLine(_ points: [CGPoint], length: CGFloat) -> RecognizedShape? {
        let a = points[0], b = points[points.count - 1]
        let chord = Self.distance(a, b)
        guard chord >= minimumSize, chord / length > 0.92 else { return nil }
        let deviation = points.map { Self.distance($0, toSegment: a, b) }.max() ?? 0
        guard deviation <= max(2, 0.06 * chord) else { return nil }
        return .line(a, snappedLineEnd(from: a, to: b))
    }

    /// Rotates `b` about `a` onto the nearest multiple of 45° when close to it.
    private func snappedLineEnd(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let step = CGFloat.pi / 4
        let snapped = (angle / step).rounded() * step
        guard abs(angle - snapped) <= lineSnapDegrees * .pi / 180 else { return b }
        let length = Self.distance(a, b)
        return CGPoint(x: a.x + cos(snapped) * length, y: a.y + sin(snapped) * length)
    }

    // MARK: Open polyline

    private func recognizeOpenPolyline(_ points: [CGPoint], diagonal: CGFloat) -> RecognizedShape? {
        let tolerance = max(2, 0.045 * diagonal)
        var vertices = Self.simplify(points, epsilon: tolerance)
        vertices = Self.mergeCollinear(vertices, closed: false, minimumTurn: 20 * .pi / 180)
        vertices = Self.dropShortSegments(vertices, closed: false, minimumLength: 0.08 * Self.pathLength(points))
        let segments = vertices.count - 1
        guard (2...4).contains(segments) else { return nil }
        guard Self.maxDeviation(points, from: vertices, closed: false) <= tolerance * 1.5 else { return nil }

        // A smooth curve also simplifies to a few segments. They all turn the
        // same way by moderate angles; real corners are sharper or zigzag.
        let turns = (1..<segments).map { Self.turn(vertices[$0 - 1], vertices[$0], vertices[$0 + 1]) }
        let sameSign = turns.allSatisfy { $0 > 0 } || turns.allSatisfy { $0 < 0 }
        if segments >= 3, sameSign, turns.allSatisfy({ abs($0) < 55 * .pi / 180 }) { return nil }
        if segments == 2, abs(turns[0]) < 30 * .pi / 180 { return nil }
        return .polyline(vertices)
    }

    // MARK: Closed shapes

    private func recognizeClosed(_ input: [CGPoint], diagonal: CGFloat) -> RecognizedShape? {
        let points = Self.trimmedOvershoot(input)
        guard points.count >= 4 else { return nil }
        let tolerance = max(2, 0.05 * diagonal)

        // Split at the point farthest from the start so both halves are open
        // paths, simplify them, then join into one loop.
        let far = points.indices.max { Self.distance(points[0], points[$0]) < Self.distance(points[0], points[$1]) } ?? 0
        if far > 0 {
            let first = Self.simplify(Array(points[0...far]), epsilon: tolerance)
            let second = Self.simplify(Array(points[far...]) + [points[0]], epsilon: tolerance)
            var loop = first + second.dropFirst().dropLast()
            loop = Self.mergeCollinear(loop, closed: true, minimumTurn: 28 * .pi / 180)
            loop = Self.dropShortSegments(loop, closed: true, minimumLength: 0.07 * Self.pathLength(points))
            loop = Self.mergeCollinear(loop, closed: true, minimumTurn: 28 * .pi / 180)
            if (3...4).contains(loop.count),
               Self.maxDeviation(points, from: loop, closed: true) <= tolerance * 1.6 {
                if loop.count == 3 { return .triangle(loop[0], loop[1], loop[2]) }
                return .rectangle(regularizedQuad(loop))
            }
        }
        return fitEllipse(points)
    }

    /// A quad whose corners are all near 90° becomes an exact rectangle,
    /// axis aligned when its sides are close to horizontal and vertical.
    private func regularizedQuad(_ quad: [CGPoint]) -> [CGPoint] {
        let nearRight = (0..<4).allSatisfy { i in
            let turn = abs(Self.turn(quad[(i + 3) % 4], quad[i], quad[(i + 1) % 4]))
            return abs(turn - .pi / 2) < 22 * .pi / 180
        }
        guard nearRight else { return quad }

        // Average side direction, folded into [-45°, 45°).
        var sumX: CGFloat = 0, sumY: CGFloat = 0
        for i in 0..<4 {
            let a = quad[i], b = quad[(i + 1) % 4]
            let angle = atan2(b.y - a.y, b.x - a.x) * 4
            let weight = Self.distance(a, b)
            sumX += cos(angle) * weight
            sumY += sin(angle) * weight
        }
        var angle = atan2(sumY, sumX) / 4
        if abs(angle) <= axisSnapDegrees * .pi / 180 { angle = 0 }

        // In the rectangle's own frame, each side sits at the mean of its two corners.
        let local = quad.map { Self.rotate($0, by: -angle) }
        let xs = local.map(\.x).sorted(), ys = local.map(\.y).sorted()
        let minX = (xs[0] + xs[1]) / 2, maxX = (xs[2] + xs[3]) / 2
        let minY = (ys[0] + ys[1]) / 2, maxY = (ys[2] + ys[3]) / 2
        // Keep the drawing's starting corner and direction.
        let corners = local.map { p in
            CGPoint(x: abs(p.x - minX) < abs(p.x - maxX) ? minX : maxX,
                    y: abs(p.y - minY) < abs(p.y - maxY) ? minY : maxY)
        }
        let distinct = corners.indices.allSatisfy { i in
            corners.indices.allSatisfy { j in i == j || corners[i] != corners[j] }
        }
        guard distinct else {
            return [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
                    CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
                .map { Self.rotate($0, by: angle) }
        }
        return corners.map { Self.rotate($0, by: angle) }
    }

    private func fitEllipse(_ points: [CGPoint]) -> RecognizedShape? {
        // Principal axes from the covariance of evenly spaced samples, so a
        // slowly drawn stretch does not weigh more than a fast one.
        let samples = Self.resample(points, closed: true, count: 64)
        let n = CGFloat(samples.count)
        let mean = CGPoint(x: samples.map(\.x).reduce(0, +) / n, y: samples.map(\.y).reduce(0, +) / n)
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in samples {
            let dx = p.x - mean.x, dy = p.y - mean.y
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        var rotation = 0.5 * atan2(2 * sxy, sxx - syy)

        let local = samples.map { Self.rotate(CGPoint(x: $0.x - mean.x, y: $0.y - mean.y), by: -rotation) }
        let xs = local.map(\.x), ys = local.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        var rx = (maxX - minX) / 2, ry = (maxY - minY) / 2
        guard rx > 0, ry > 0, min(rx, ry) / max(rx, ry) > 0.12 else { return nil }
        let localCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let offset = Self.rotate(localCenter, by: rotation)
        let center = CGPoint(x: mean.x + offset.x, y: mean.y + offset.y)

        var errors: [CGFloat] = []
        for p in local {
            let x = (p.x - localCenter.x) / rx, y = (p.y - localCenter.y) / ry
            errors.append(abs(hypot(x, y) - 1))
        }
        let meanError = errors.reduce(0, +) / CGFloat(errors.count)
        guard meanError < 0.08, (errors.max() ?? 1) < 0.25 else { return nil }

        // The loop must actually go round the centre, not double back.
        var swept: CGFloat = 0
        for i in 1..<local.count {
            let a = atan2(local[i - 1].y - localCenter.y, local[i - 1].x - localCenter.x)
            let b = atan2(local[i].y - localCenter.y, local[i].x - localCenter.x)
            var d = b - a
            if d > .pi { d -= 2 * .pi }
            if d < -.pi { d += 2 * .pi }
            swept += d
        }
        guard abs(swept) > 1.6 * .pi else { return nil }

        if abs(rx - ry) / max(rx, ry) < circleTolerance {
            let r = (rx + ry) / 2
            return .ellipse(center: center, radiusX: r, radiusY: r, rotation: 0)
        }
        // Fold the rotation into (-90°, 90°] and snap it to the axes.
        let snap = axisSnapDegrees * .pi / 180
        if abs(rotation) <= snap {
            rotation = 0
        } else if abs(abs(rotation) - .pi / 2) <= snap {
            rotation = 0
            swap(&rx, &ry)
        }
        return .ellipse(center: center, radiusX: rx, radiusY: ry, rotation: rotation)
    }

    // MARK: - Resampling a shape

    /// Evenly spaced points along `shape`, for building a stroke. Corners are
    /// always included, and a closed shape ends where it starts.
    public static func points(for shape: RecognizedShape, spacing: CGFloat) -> [CGPoint] {
        let spacing = max(spacing, 0.1)
        switch shape {
        case let .line(a, b):
            return resample(polyline: [a, b], spacing: spacing)
        case let .polyline(vertices):
            return resample(polyline: vertices, spacing: spacing)
        case let .triangle(a, b, c):
            return resample(polyline: [a, b, c, a], spacing: spacing)
        case let .rectangle(corners):
            guard let first = corners.first else { return [] }
            return resample(polyline: corners + [first], spacing: spacing)
        case let .ellipse(center, rx, ry, rotation):
            let dense = 360
            let outline = (0...dense).map { i -> CGPoint in
                let t = CGFloat(i) / CGFloat(dense) * 2 * .pi
                let p = rotate(CGPoint(x: rx * cos(t), y: ry * sin(t)), by: rotation)
                return CGPoint(x: center.x + p.x, y: center.y + p.y)
            }
            var points: [CGPoint] = [outline[0]]
            var carried: CGFloat = 0
            for i in 1..<outline.count {
                carried += distance(outline[i - 1], outline[i])
                if carried >= spacing {
                    points.append(outline[i])
                    carried = 0
                }
            }
            if let last = points.last, distance(last, outline[0]) > 0.01 { points.append(outline[0]) }
            return points
        }
    }

    /// Points every `spacing` along each segment, keeping every vertex.
    static func resample(polyline vertices: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard let first = vertices.first else { return [] }
        var points = [first]
        for i in 1..<max(vertices.count, 1) {
            let a = vertices[i - 1], b = vertices[i]
            let length = distance(a, b)
            let steps = max(1, Int((length / spacing).rounded()))
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return points
    }

    // MARK: - Geometry helpers

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(p, a) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    static func rotate(_ p: CGPoint, by angle: CGFloat) -> CGPoint {
        CGPoint(x: p.x * cos(angle) - p.y * sin(angle), y: p.x * sin(angle) + p.y * cos(angle))
    }

    /// Signed change of direction at `b`, in radians.
    static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        let first = atan2(b.y - a.y, b.x - a.x)
        let second = atan2(c.y - b.y, c.x - b.x)
        var d = second - first
        while d > .pi { d -= 2 * .pi }
        while d <= -.pi { d += 2 * .pi }
        return d
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return (1..<points.count).reduce(0) { $0 + distance(points[$1 - 1], points[$1]) }
    }

    static func deduplicated(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for p in points where p.x.isFinite && p.y.isFinite {
            if let last = result.last, distance(last, p) < 0.01 { continue }
            result.append(p)
        }
        return result
    }

    /// Ramer–Douglas–Peucker simplification of an open path.
    static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var farthest = start, maxDistance: CGFloat = 0
            for i in (start + 1)..<end {
                let d = distance(points[i], toSegment: points[start], points[end])
                if d > maxDistance { maxDistance = d; farthest = i }
            }
            if maxDistance > epsilon {
                keep[farthest] = true
                stack.append((start, farthest))
                stack.append((farthest, end))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// Removes vertices where the path barely turns, gentlest first.
    static func mergeCollinear(_ input: [CGPoint], closed: Bool, minimumTurn: CGFloat) -> [CGPoint] {
        var vertices = input
        while vertices.count > (closed ? 3 : 2) {
            let candidates = closed ? Array(vertices.indices) : Array(1..<(vertices.count - 1))
            let n = vertices.count
            let gentlest = candidates.min {
                abs(turn(vertices[($0 + n - 1) % n], vertices[$0], vertices[($0 + 1) % n]))
                    < abs(turn(vertices[($1 + n - 1) % n], vertices[$1], vertices[($1 + 1) % n]))
            }
            guard let index = gentlest,
                  abs(turn(vertices[(index + n - 1) % n], vertices[index], vertices[(index + 1) % n])) < minimumTurn
            else { break }
            vertices.remove(at: index)
        }
        return vertices
    }

    /// Collapses segments shorter than `minimumLength` (hooks at the ends,
    /// jitter at a corner) into a single vertex.
    static func dropShortSegments(_ input: [CGPoint], closed: Bool, minimumLength: CGFloat) -> [CGPoint] {
        var vertices = input
        while vertices.count > (closed ? 3 : 2) {
            let n = vertices.count
            let segmentCount = closed ? n : n - 1
            guard let shortest = (0..<segmentCount).min(by: {
                distance(vertices[$0], vertices[($0 + 1) % n]) < distance(vertices[$1], vertices[($1 + 1) % n])
            }), distance(vertices[shortest], vertices[(shortest + 1) % n]) < minimumLength
            else { break }
            let next = (shortest + 1) % n
            if !closed, shortest == 0 {
                vertices.remove(at: 1) // keep the true start
            } else if !closed, next == n - 1 {
                vertices.remove(at: shortest) // keep the true end
            } else {
                let a = vertices[shortest], b = vertices[next]
                vertices[shortest] = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                vertices.remove(at: next)
            }
        }
        return vertices
    }

    /// The largest distance from any of `points` to the path through `vertices`.
    static func maxDeviation(_ points: [CGPoint], from vertices: [CGPoint], closed: Bool) -> CGFloat {
        let segments = closed ? vertices.count : vertices.count - 1
        guard segments > 0 else { return .infinity }
        var worst: CGFloat = 0
        for p in points {
            var best = CGFloat.infinity
            for i in 0..<segments {
                best = min(best, distance(p, toSegment: vertices[i], vertices[(i + 1) % vertices.count]))
            }
            worst = max(worst, best)
        }
        return worst
    }

    /// Cuts a closed stroke where it comes back nearest its start, dropping
    /// the overshoot past the starting point.
    static func trimmedOvershoot(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 8 else { return points }
        let tailStart = points.count * 3 / 4
        let start = points[0]
        guard let nearest = (tailStart..<points.count).min(by: {
            distance(points[$0], start) < distance(points[$1], start)
        }) else { return points }
        return Array(points[...nearest])
    }

    /// `count` points evenly spaced along the path (closed back to its start).
    static func resample(_ points: [CGPoint], closed: Bool, count: Int) -> [CGPoint] {
        let path = closed ? points + [points[0]] : points
        let total = pathLength(path)
        guard total > 0, count > 1 else { return points }
        let step = total / CGFloat(closed ? count : count - 1)
        var result: [CGPoint] = [path[0]]
        var target = step
        var walked: CGFloat = 0
        for i in 1..<path.count where result.count < count {
            let a = path[i - 1], b = path[i]
            let length = distance(a, b)
            while length > 0, walked + length >= target, result.count < count {
                let t = (target - walked) / length
                result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                target += step
            }
            walked += length
        }
        return result
    }
}
