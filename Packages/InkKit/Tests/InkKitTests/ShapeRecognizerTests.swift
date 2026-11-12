import CoreGraphics
import Foundation
import InkKit
import PencilKit
import Testing

@Suite("Shape recognizer")
struct ShapeRecognizerTests {
    let recognizer = ShapeRecognizer()

    // MARK: - Synthetic hand-drawn input

    /// Deterministic wobble, so a test never depends on a random seed.
    private func wobble(_ i: Int, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: sin(CGFloat(i) * 1.7) * amount, y: cos(CGFloat(i) * 2.3) * amount)
    }

    /// Points along `vertices`, about every 2 pt, with a small wobble.
    private func drawn(_ vertices: [CGPoint], noise: CGFloat = 1.2) -> [CGPoint] {
        var points: [CGPoint] = []
        var i = 0
        for s in 1..<vertices.count {
            let a = vertices[s - 1], b = vertices[s]
            let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 2))
            for k in 0..<steps {
                let t = CGFloat(k) / CGFloat(steps)
                let w = wobble(i, noise)
                points.append(CGPoint(x: a.x + (b.x - a.x) * t + w.x, y: a.y + (b.y - a.y) * t + w.y))
                i += 1
            }
        }
        if let last = vertices.last { points.append(last) }
        return points
    }

    private func drawnEllipse(center: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat = 0,
                              turns: CGFloat = 1.04, noise: CGFloat = 1.0) -> [CGPoint] {
        let count = 180
        return (0...count).map { i in
            let t = CGFloat(i) / CGFloat(count) * 2 * .pi * turns + 0.3
            let x = rx * cos(t), y = ry * sin(t)
            let w = wobble(i, noise)
            return CGPoint(x: center.x + x * cos(rotation) - y * sin(rotation) + w.x,
                           y: center.y + x * sin(rotation) + y * cos(rotation) + w.y)
        }
    }

    private func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 6) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= tolerance
    }

    // MARK: - Lines

    @Test func horizontalLineSnapsFlat() {
        let points = drawn([CGPoint(x: 10, y: 100), CGPoint(x: 210, y: 104)])
        guard case let .line(a, b)? = recognizer.recognize(points) else {
            Issue.record("expected a line"); return
        }
        #expect(close(a, CGPoint(x: 10, y: 100), 2))
        #expect(abs(b.y - a.y) < 0.001)
        #expect(abs(b.x - 210) < 2)
    }

    @Test func slantedLineKeepsItsAngle() {
        let points = drawn([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 60)])
        guard case let .line(a, b)? = recognizer.recognize(points) else {
            Issue.record("expected a line"); return
        }
        let angle = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
        #expect(abs(angle - 16.7) < 1.5)
    }

    @Test func nearDiagonalLineSnapsTo45Degrees() {
        let points = drawn([CGPoint(x: 0, y: 0), CGPoint(x: 150, y: 140)])
        guard case let .line(a, b)? = recognizer.recognize(points) else {
            Issue.record("expected a line"); return
        }
        let angle = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
        #expect(abs(angle - 45) < 0.001)
    }

    @Test func nearVerticalLineSnapsUpright() {
        let points = drawn([CGPoint(x: 50, y: 300), CGPoint(x: 58, y: 100)])
        guard case let .line(a, b)? = recognizer.recognize(points) else {
            Issue.record("expected a line"); return
        }
        #expect(abs(a.x - b.x) < 0.001)
    }

    // MARK: - Polylines

    @Test func openTwoSegmentCorner() {
        let points = drawn([CGPoint(x: 0, y: 0), CGPoint(x: 150, y: 0), CGPoint(x: 150, y: 120)])
        guard case let .polyline(vertices)? = recognizer.recognize(points) else {
            Issue.record("expected a polyline"); return
        }
        #expect(vertices.count == 3)
        #expect(close(vertices[1], CGPoint(x: 150, y: 0)))
    }

    @Test func zigzagIsAPolyline() {
        let points = drawn([CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 100), CGPoint(x: 120, y: 0), CGPoint(x: 180, y: 100)])
        guard case let .polyline(vertices)? = recognizer.recognize(points) else {
            Issue.record("expected a polyline"); return
        }
        #expect(vertices.count == 4)
    }

    @Test func openArcStaysFreehand() {
        let arc = (0...90).map { i -> CGPoint in
            let t = CGFloat(i) / 90 * .pi
            return CGPoint(x: 100 - cos(t) * 100, y: 100 - sin(t) * 100)
        }
        #expect(recognizer.recognize(arc) == nil)
    }

    // MARK: - Closed polygons

    @Test func axisAlignedRectangle() {
        let corners = [CGPoint(x: 20, y: 20), CGPoint(x: 220, y: 24), CGPoint(x: 218, y: 140),
                       CGPoint(x: 22, y: 138), CGPoint(x: 21, y: 26)]
        guard case let .rectangle(result)? = recognizer.recognize(drawn(corners)) else {
            Issue.record("expected a rectangle"); return
        }
        #expect(result.count == 4)
        let xs = Set(result.map { ($0.x * 1000).rounded() }), ys = Set(result.map { ($0.y * 1000).rounded() })
        #expect(xs.count == 2 && ys.count == 2, "axis aligned rectangle has two distinct xs and ys")
        #expect(abs((result.map(\.x).max() ?? 0) - (result.map(\.x).min() ?? 0) - 198) < 8)
        #expect(abs((result.map(\.y).max() ?? 0) - (result.map(\.y).min() ?? 0) - 116) < 8)
    }

    @Test func rotatedRectangleStaysRotated() {
        let angle: CGFloat = 30 * .pi / 180
        let base = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 100), CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 4)]
        let corners = base.map { CGPoint(x: 300 + $0.x * cos(angle) - $0.y * sin(angle),
                                         y: 100 + $0.x * sin(angle) + $0.y * cos(angle)) }
        guard case let .rectangle(result)? = recognizer.recognize(drawn(corners)) else {
            Issue.record("expected a rectangle"); return
        }
        #expect(result.count == 4)
        let side = atan2(result[1].y - result[0].y, result[1].x - result[0].x) * 180 / .pi
        let folded = (side + 360).truncatingRemainder(dividingBy: 90)
        #expect(abs(folded - 30) < 3)
        // Right angles at every corner.
        for i in 0..<4 {
            let a = result[i], b = result[(i + 1) % 4], c = result[(i + 2) % 4]
            let dot = (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y)
            #expect(abs(dot) < 0.01)
        }
    }

    @Test func triangle() {
        let corners = [CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 170), CGPoint(x: 0, y: 170), CGPoint(x: 98, y: 4)]
        guard case let .triangle(a, b, c)? = recognizer.recognize(drawn(corners)) else {
            Issue.record("expected a triangle"); return
        }
        for expected in corners.dropLast() {
            #expect([a, b, c].contains { close($0, expected, 10) })
        }
    }

    // MARK: - Ellipses

    @Test func circle() {
        let points = drawnEllipse(center: CGPoint(x: 200, y: 200), rx: 80, ry: 76)
        guard case let .ellipse(center, rx, ry, _)? = recognizer.recognize(points) else {
            Issue.record("expected a circle"); return
        }
        #expect(close(center, CGPoint(x: 200, y: 200), 4))
        #expect(rx == ry)
        #expect(abs(rx - 78) < 5)
    }

    @Test func axisAlignedEllipse() {
        let points = drawnEllipse(center: CGPoint(x: 200, y: 150), rx: 120, ry: 50)
        guard case let .ellipse(center, rx, ry, rotation)? = recognizer.recognize(points) else {
            Issue.record("expected an ellipse"); return
        }
        #expect(close(center, CGPoint(x: 200, y: 150), 4))
        #expect(rotation == 0)
        #expect(abs(rx - 120) < 6 && abs(ry - 50) < 6)
    }

    @Test func rotatedEllipse() {
        let points = drawnEllipse(center: CGPoint(x: 200, y: 150), rx: 120, ry: 50, rotation: .pi / 6)
        guard case let .ellipse(_, rx, ry, rotation)? = recognizer.recognize(points) else {
            Issue.record("expected an ellipse"); return
        }
        #expect(abs(rotation - .pi / 6) < 0.06)
        #expect(abs(rx - 120) < 6 && abs(ry - 50) < 6)
    }

    // MARK: - Real-world untidiness

    @Test func rectangleWithOvershootPastTheStart() {
        let corners = [CGPoint(x: 20, y: 20), CGPoint(x: 220, y: 22), CGPoint(x: 219, y: 140),
                       CGPoint(x: 20, y: 139), CGPoint(x: 21, y: 20), CGPoint(x: 70, y: 21)]
        guard case let .rectangle(result)? = recognizer.recognize(drawn(corners)) else {
            Issue.record("expected a rectangle"); return
        }
        #expect(result.count == 4)
    }

    @Test func circleWithAGap() {
        let points = drawnEllipse(center: CGPoint(x: 100, y: 100), rx: 60, ry: 60, turns: 0.93)
        guard case .ellipse? = recognizer.recognize(points) else {
            Issue.record("expected a circle"); return
        }
    }

    @Test func lineWithHoldJitterAtTheEnd() {
        var points = drawn([CGPoint(x: 0, y: 0), CGPoint(x: 180, y: 2)])
        for i in 0..<40 { points.append(CGPoint(x: 180 + wobble(i, 1).x, y: 2 + wobble(i, 1).y)) }
        guard case .line? = recognizer.recognize(points) else {
            Issue.record("expected a line"); return
        }
    }

    @Test func lineDrawnBackOnItselfIsNotALine() {
        let points = drawn([CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 20, y: 3)])
        if case .line? = recognizer.recognize(points) { Issue.record("a doubled-back stroke is not a line") }
    }

    // MARK: - Nothing

    @Test func scribbleStaysFreehand() {
        let points = (0..<200).map { i -> CGPoint in
            let t = CGFloat(i) * 0.31
            return CGPoint(x: 100 + sin(t * 1.3) * 60 + sin(t * 4.1) * 25, y: 100 + cos(t * 0.7) * 50 + cos(t * 3.3) * 30)
        }
        #expect(recognizer.recognize(points) == nil)
    }

    @Test func handwritingStaysFreehand() {
        // A cursive "e"-like loop followed by a tail.
        let points = (0..<120).map { i -> CGPoint in
            let t = CGFloat(i) / 119 * 3 * .pi
            return CGPoint(x: t * 12 + cos(t * 2) * 10, y: 50 + sin(t * 2) * 12)
        }
        #expect(recognizer.recognize(points) == nil)
    }

    @Test func tinyStrokeStaysFreehand() {
        let points = drawn([CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 3)], noise: 0.2)
        #expect(recognizer.recognize(points) == nil)
        #expect(recognizer.recognize([CGPoint(x: 5, y: 5)]) == nil)
        #expect(recognizer.recognize([]) == nil)
    }

    // MARK: - Resampling

    @Test func resampledRectangleIsClosedAndEven() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 50), CGPoint(x: 0, y: 50)]
        let points = ShapeRecognizer.points(for: .rectangle(corners), spacing: 2)
        #expect(points.first == points.last)
        for corner in corners { #expect(points.contains(corner)) }
        for i in 1..<points.count {
            let d = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            #expect(d <= 2.01 && d > 1.5)
        }
    }

    @Test func resampledEllipseFollowsTheOutline() {
        let shape = RecognizedShape.ellipse(center: CGPoint(x: 10, y: 10), radiusX: 40, radiusY: 20, rotation: 0.4)
        let points = ShapeRecognizer.points(for: shape, spacing: 3)
        #expect(points.count > 40)
        #expect(points.first == points.last)
        for p in points {
            let local = CGPoint(x: (p.x - 10) * cos(-0.4) - (p.y - 10) * sin(-0.4),
                                y: (p.x - 10) * sin(-0.4) + (p.y - 10) * cos(-0.4))
            #expect(abs(hypot(local.x / 40, local.y / 20) - 1) < 0.01)
        }
    }

    @Test func resampledLine() {
        let points = ShapeRecognizer.points(for: .line(.zero, CGPoint(x: 10, y: 0)), spacing: 2)
        #expect(points.count == 6)
        #expect(points.last == CGPoint(x: 10, y: 0))
    }
}

@Suite("Shape stroke builder")
struct ShapeStrokeBuilderTests {
    private func stroke(_ locations: [CGPoint]) -> PKStroke {
        let points = locations.enumerated().map { i, location in
            PKStrokePoint(location: location, timeOffset: Double(i) / 240, size: CGSize(width: 3 + Double(i % 3), height: 3),
                          opacity: 1, force: 0.5, azimuth: 0.2, altitude: 1.0)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 1000))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }

    @Test func heldLineBecomesAStraightStrokeWithTheSameIdentity() throws {
        let freehand = stroke((0...100).map { CGPoint(x: CGFloat($0) * 2, y: 50 + sin(CGFloat($0)) * 0.8) })
        let shape = try #require(ShapeStrokeBuilder.shapeStroke(replacing: freehand))
        #expect(shape.id == freehand.id)
        #expect(shape.ink.inkType == freehand.ink.inkType)
        #expect(shape.path.creationDate == freehand.path.creationDate)
        #expect(shape.path.count != freehand.path.count)
        let ys = Set(shape.path.map { ($0.location.y * 1000).rounded() })
        #expect(ys.count == 1, "a snapped horizontal line has one y")
        let middle = freehand.path[freehand.path.count / 2]
        #expect(shape.path.allSatisfy { $0.size == middle.size })
    }

    @Test func scribbleIsNotReplaced() {
        let freehand = stroke((0..<150).map { i in
            let t = CGFloat(i) * 0.31
            return CGPoint(x: 100 + sin(t * 1.3) * 60 + sin(t * 4.1) * 25, y: 100 + cos(t * 0.7) * 50 + cos(t * 3.3) * 30)
        })
        #expect(ShapeStrokeBuilder.shapeStroke(replacing: freehand) == nil)
    }
}
