// Geometry tests for the vector ink outline: no PencilKit, only points in and
// a fillable path out.

import CoreGraphics
import Foundation
import Testing
@testable import InkKit

@Suite("Stroke outline")
struct StrokeOutlineTests {
    typealias Sample = StrokeOutline.Sample

    private func inside(_ path: CGPath, _ x: CGFloat, _ y: CGFloat) -> Bool {
        path.contains(CGPoint(x: x, y: y), using: .winding)
    }

    @Test("A straight line is a capsule of its half-width")
    func straightLine() {
        let samples = stride(from: 0.0, through: 100.0, by: 2.0).map { Sample(x: $0, y: 0, radius: 5) }
        let path = StrokeOutline.path(for: samples)

        #expect(inside(path, 50, 4.5))
        #expect(inside(path, 50, -4.5))
        #expect(!inside(path, 50, 5.5))
        #expect(!inside(path, 50, -5.5))
        // Round caps past both ends.
        #expect(inside(path, -4.5, 0))
        #expect(inside(path, 104.5, 0))
        #expect(!inside(path, -5.5, 0))
        #expect(!inside(path, -4, 4))

        let box = path.boundingBoxOfPath
        #expect(abs(box.minX + 5) < 0.6 && abs(box.maxX - 105) < 0.6)
        #expect(abs(box.minY + 5) < 0.6 && abs(box.maxY - 5) < 0.6)
    }

    @Test("A curve follows its centre line without facets or gaps")
    func curve() {
        // A half circle of radius 50, sampled every ~1.5 pt like the exporter.
        let samples = stride(from: 0.0, through: Double.pi, by: 0.03).map {
            Sample(x: 50 * cos($0), y: 50 * sin($0), radius: 3)
        }
        let path = StrokeOutline.path(for: samples)

        for angle in stride(from: 0.05, through: Double.pi - 0.05, by: 0.013) {
            let c = CGFloat(cos(angle)), s = CGFloat(sin(angle))
            #expect(inside(path, 50 * c, 50 * s))
            #expect(inside(path, 52.5 * c, 52.5 * s))
            #expect(inside(path, 47.5 * c, 47.5 * s))
            #expect(!inside(path, 53.5 * c, 53.5 * s))
            #expect(!inside(path, 46.5 * c, 46.5 * s))
        }
    }

    @Test("A zero-length stroke is a dot")
    func dot() {
        let path = StrokeOutline.path(for: Array(repeating: Sample(x: 10, y: 20, radius: 4), count: 3))
        #expect(inside(path, 10, 20))
        #expect(inside(path, 13.5, 20))
        #expect(inside(path, 10, 16.5))
        #expect(!inside(path, 14.5, 20))
        #expect(!inside(path, 10, 24.5))

        let single = StrokeOutline.path(for: [Sample(x: 0, y: 0, radius: 2)])
        #expect(inside(single, 1.5, 0))
        #expect(!inside(single, 2.5, 0))
    }

    @Test("Width follows the samples")
    func widthVariation() {
        // Half-width grows linearly from 1 to 11 over 100 pt.
        let samples = stride(from: 0.0, through: 100.0, by: 1.5).map {
            Sample(x: $0, y: 0, radius: 1 + $0 / 10)
        }
        let path = StrokeOutline.path(for: samples)
        for x in stride(from: 5.0, through: 95.0, by: 10.0) {
            let r = 1 + x / 10
            #expect(inside(path, x, r * 0.9))
            #expect(inside(path, x, -r * 0.9))
            #expect(!inside(path, x, r + 0.6))
            #expect(!inside(path, x, -(r + 0.6)))
        }
    }

    @Test("A sharp turn is filled at the corner, with no hole")
    func sharpTurn() {
        var samples = stride(from: 0.0, through: 50.0, by: 1.5).map { Sample(x: $0, y: 0, radius: 6) }
        samples += stride(from: 1.5, through: 50.0, by: 1.5).map { Sample(x: 50 - $0, y: $0 * 0.2, radius: 6) }
        let path = StrokeOutline.path(for: samples)
        for x in stride(from: 30.0, through: 55.5, by: 0.5) {
            #expect(inside(path, x, 0), "hole at \(x)")
        }
        #expect(inside(path, 50, 5))
        #expect(inside(path, 55.5, 0))
    }

    @Test("Every subpath is closed and winds the same way")
    func closedOutlineIsValid() {
        let wiggle = stride(from: 0.0, through: 200.0, by: 1.5).map {
            Sample(x: $0, y: 20 * sin($0 / 7), radius: 2 + 1.5 * sin($0 / 13))
        }
        let path = StrokeOutline.path(for: wiggle)
        #expect(!path.isEmpty)

        var areas: [CGFloat] = []
        var polygon: [CGPoint] = []
        var closed = 0
        var start = CGPoint.zero
        func finish() {
            guard polygon.count > 2 else { polygon = []; return }
            var area: CGFloat = 0
            for i in 0..<polygon.count {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                area += a.x * b.y - b.x * a.y
            }
            areas.append(area / 2)
            polygon = []
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                finish()
                start = element.points[0]
                polygon = [start]
            case .addLineToPoint:
                polygon.append(element.points[0])
            case .addQuadCurveToPoint:
                polygon.append(element.points[1])
            case .addCurveToPoint:
                polygon.append(element.points[2])
            case .closeSubpath:
                closed += 1
                finish()
            @unknown default:
                break
            }
        }
        finish()

        #expect(!areas.isEmpty)
        #expect(closed == areas.count)
        #expect(areas.allSatisfy { $0 < 0 }, "mixed winding: \(areas)")
        for x in stride(from: 3.0, through: 197.0, by: 2.0) {
            #expect(inside(path, x, 20 * sin(x / 7)))
        }
    }

    @Test("Non-finite samples are ignored")
    func nonFinite() {
        let path = StrokeOutline.path(for: [
            Sample(x: .nan, y: 0, radius: 1),
            Sample(x: 0, y: 0, radius: .infinity),
        ])
        #expect(path.isEmpty)
    }
}
