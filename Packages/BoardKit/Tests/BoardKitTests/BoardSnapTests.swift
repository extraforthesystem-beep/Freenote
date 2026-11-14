import BoardKit
import CoreGraphics
import Foundation
import Testing

/// The snapping the board editor used before the maths moved into `BoardKit`:
/// build the edge arrays from every item on each call, then look for the
/// nearest edge on each axis independently.
///
/// Kept here as the oracle for the property test, so the precomputed targets
/// are compared against the frame-by-frame implementation they replaced.
private enum ReferenceSnapping {
    static func snap(
        _ frame: CGRect,
        items: [BoardItem],
        ignoring itemID: UUID,
        tolerance: CGFloat
    ) -> BoardSnapResult {
        let frames = items.compactMap { item -> CGRect? in
            guard item.id != itemID else { return nil }
            return item.frame
        }
        guard !frames.isEmpty else {
            return BoardSnapResult(frame: frame, guides: [])
        }

        let xTargets = frames.flatMap { [$0.minX, $0.midX, $0.maxX] }
        let yTargets = frames.flatMap { [$0.minY, $0.midY, $0.maxY] }
        var result = frame
        var guides: [BoardSnapGuide] = []

        if let snap = nearestSnap(
            edges: [frame.minX, frame.midX, frame.maxX],
            targets: xTargets,
            tolerance: tolerance
        ) {
            result.origin.x += snap.delta
            guides.append(BoardSnapGuide(axis: .vertical, position: snap.line))
        }
        if let snap = nearestSnap(
            edges: [frame.minY, frame.midY, frame.maxY],
            targets: yTargets,
            tolerance: tolerance
        ) {
            result.origin.y += snap.delta
            guides.append(BoardSnapGuide(axis: .horizontal, position: snap.line))
        }
        return BoardSnapResult(frame: result, guides: guides)
    }

    private static func nearestSnap(
        edges: [CGFloat],
        targets: [CGFloat],
        tolerance: CGFloat
    ) -> (delta: CGFloat, line: CGFloat)? {
        var best: (delta: CGFloat, line: CGFloat)?
        for edge in edges {
            for target in targets {
                let delta = target - edge
                guard abs(delta) <= tolerance else { continue }
                if abs(delta) < abs(best?.delta ?? .infinity) {
                    best = (delta, target)
                }
            }
        }
        return best
    }
}

struct BoardSnapTests {
    private let epoch = Date(timeIntervalSince1970: 100)

    private func item(_ frame: CGRect, id: UUID = UUID()) -> BoardItem {
        BoardItem(
            id: id,
            zIndex: 0,
            createdAt: epoch,
            updatedAt: epoch,
            content: .sticky("Note", frame: frame, color: .black)
        )
    }

    // MARK: - Behaviour

    @Test func snapsLeftEdgeToNeighbour() {
        let neighbour = item(CGRect(x: 100, y: 500, width: 50, height: 50))
        let frame = CGRect(x: 103, y: 900, width: 10, height: 10)
        let targets = BoardSnapTargets(items: [neighbour])

        let result = targets.snap(frame, tolerance: 6)

        #expect(result.frame.origin.x == 100)
        #expect(result.frame.origin.y == 900)
        #expect(result.guides == [BoardSnapGuide(axis: .vertical, position: 100)])
    }

    @Test func snapsBothAxesIndependently() {
        let neighbour = item(CGRect(x: 100, y: 200, width: 50, height: 50))
        // Left edge 3 from 100, top edge 2 from 200.
        let frame = CGRect(x: 103, y: 202, width: 10, height: 10)

        let result = BoardSnapTargets(items: [neighbour]).snap(frame, tolerance: 6)

        #expect(result.frame.origin == CGPoint(x: 100, y: 200))
        #expect(result.guides == [
            BoardSnapGuide(axis: .vertical, position: 100),
            BoardSnapGuide(axis: .horizontal, position: 200),
        ])
    }

    @Test func leavesAFrameAloneBeyondTheTolerance() {
        let neighbour = item(CGRect(x: 100, y: 100, width: 50, height: 50))
        let frame = CGRect(x: 400, y: 400, width: 10, height: 10)

        let result = BoardSnapTargets(items: [neighbour]).snap(frame, tolerance: 6)

        #expect(result.frame == frame)
        #expect(result.guides.isEmpty)
    }

    @Test func ignoringTheDraggedItemRemovesItsOwnEdges() {
        let dragged = item(CGRect(x: 0, y: 0, width: 10, height: 10))
        let frame = CGRect(x: 1, y: 1, width: 10, height: 10)

        let targets = BoardSnapTargets(items: [dragged], ignoring: dragged.id)

        #expect(targets.isEmpty)
        #expect(targets.snap(frame, tolerance: 6).frame == frame)
    }

    @Test func snapsCentreToNeighbourCentre() {
        let neighbour = item(CGRect(x: 0, y: 0, width: 100, height: 100))
        // midX 48 is 2 from the neighbour's centre at 50.
        let frame = CGRect(x: 43, y: 900, width: 10, height: 10)

        let result = BoardSnapTargets(items: [neighbour]).snap(frame, tolerance: 6)

        #expect(result.frame.origin.x == 45)
        #expect(result.frame.origin.y == 900)
        #expect(result.guides == [BoardSnapGuide(axis: .vertical, position: 50)])
    }

    // MARK: - Property: precomputed targets == the per-frame reference

    /// 500 seeded cases of item sets, dragged frames and tolerances. The
    /// precomputed targets must give exactly the result the old
    /// rebuild-every-frame code gave, frame and guides both.
    @Test func precomputedTargetsMatchTheReferenceForRandomDrags() {
        var rng = SplitMix64(seed: 0xA4_02_0001)
        var snappedCases = 0

        for _ in 0..<500 {
            let count = rng.int(in: 0...12)
            var items: [BoardItem] = []
            for _ in 0..<count {
                items.append(randomItem(&rng))
            }

            // Half the time the dragged item is really on the board, so its
            // own edges have to be excluded.
            let ignored: UUID
            if let first = items.first, rng.chance(0.5) {
                ignored = first.id
            } else {
                ignored = randomUUID(&rng)
            }

            let frame = randomFrame(&rng)
            let tolerance = rng.double(in: 0...120)
            let expected = ReferenceSnapping.snap(
                frame,
                items: items,
                ignoring: ignored,
                tolerance: tolerance
            )
            let actual = BoardSnapTargets(items: items, ignoring: ignored)
                .snap(frame, tolerance: tolerance)

            #expect(actual.frame == expected.frame)
            #expect(actual.guides == expected.guides)
            if !actual.guides.isEmpty {
                snappedCases += 1
            }
        }

        // The generator has to reach the snapping paths, or the property says
        // nothing. A tenth of the cases is a loose floor well above zero.
        #expect(snappedCases > 50)
    }
}
