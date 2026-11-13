import CoreGraphics
import Foundation
import NoteCore
import Testing
@testable import AudioKit

@Suite("Replay targeting")
struct ReplayTargetTests {
    private func stroke(
        id: UUID = UUID(),
        createdAt: Date = testStart,
        transform: [Double] = StrokeRecord.identityTransform,
        points: [(Double, Double)]
    ) -> StrokeRecord {
        StrokeRecord(
            id: id,
            layerID: UUID(),
            tool: StrokeTool(
                engine: "metal",
                inkType: "pen",
                color: RGBAColor(r: 0, g: 0, b: 0),
                width: 2
            ),
            createdAt: createdAt,
            transform: transform,
            randomSeed: 1,
            points: points.map {
                StrokePoint(
                    x: $0.0,
                    y: $0.1,
                    timeOffset: 0,
                    width: 2,
                    height: 2,
                    opacity: 1,
                    force: 1,
                    azimuth: 0,
                    altitude: 1,
                    secondaryScale: 1
                )
            }
        )
    }

    @Test("A tap on the line between two points finds the stroke")
    func hitsBetweenPoints() {
        let line = stroke(points: [(0, 0), (200, 0)])

        #expect(ReplayTarget.nearestStroke(to: CGPoint(x: 100, y: 3), in: [line])?.id == line.id)
        #expect(ReplayTarget.nearestStroke(to: CGPoint(x: 0, y: 0), in: [line])?.id == line.id)
        #expect(ReplayTarget.nearestStroke(to: CGPoint(x: 200, y: 0), in: [line])?.id == line.id)
    }

    @Test("A tap beyond the tolerance misses, and empty ink never matches")
    func missesFarAway() {
        let line = stroke(points: [(0, 0), (200, 0)])

        #expect(ReplayTarget.nearestStroke(to: CGPoint(x: 100, y: 30), in: [line]) == nil)
        #expect(ReplayTarget.nearestStroke(to: CGPoint(x: 100, y: 30), in: []) == nil)
        #expect(ReplayTarget.nearestStroke(to: CGPoint(x: 100, y: 30), in: [stroke(points: [])]) == nil)
        #expect(
            ReplayTarget.nearestStroke(
                to: CGPoint(x: CGFloat.nan, y: 0),
                in: [line]
            ) == nil
        )
    }

    @Test("The stroke transform is applied before measuring")
    func appliesTransform() {
        let shifted = stroke(transform: [1, 0, 0, 1, 300, 40], points: [(0, 0), (100, 0)])

        #expect(
            ReplayTarget.nearestStroke(to: CGPoint(x: 350, y: 42), in: [shifted])?.id
                == shifted.id
        )
        // The untransformed position is empty.
        #expect(ReplayTarget.nearestStroke(to: CGPoint(x: 50, y: 0), in: [shifted]) == nil)
    }

    @Test("Overlapping ink picks the nearest, then the newest")
    func nearestThenNewest() {
        let older = stroke(
            createdAt: testStart,
            points: [(0, 0), (200, 0)]
        )
        let newer = stroke(
            createdAt: testStart.addingTimeInterval(10),
            points: [(0, 0), (200, 0)]
        )
        let nearer = stroke(
            createdAt: testStart.addingTimeInterval(-10),
            points: [(0, 40), (200, 40)]
        )

        #expect(
            ReplayTarget.nearestStroke(to: CGPoint(x: 100, y: 1), in: [older, newer])?.id
                == newer.id
        )
        #expect(
            ReplayTarget.nearestStroke(to: CGPoint(x: 100, y: 25), in: [older, newer, nearer])?.id
                == nearer.id
        )
    }
}
