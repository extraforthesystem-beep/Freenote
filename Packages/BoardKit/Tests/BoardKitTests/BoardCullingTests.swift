import BoardKit
import CoreGraphics
import Foundation
import Testing

/// Culling: which items a viewport or a thumbnail crop has to draw.
struct BoardCullingTests {
    private let epoch = Date(timeIntervalSince1970: 100)

    private func frameBackedItem(_ rng: inout SplitMix64) -> BoardItem {
        let frame = randomFrame(&rng)
        let content: BoardItemContent = switch rng.int(in: 0...3) {
        case 0: .image(assetName: "asset-\(rng.int(in: 0...9))", frame: frame)
        case 1: .text("text", frame: frame, fontSize: 12, color: .black)
        case 2: .sticky("note", frame: frame, color: .black)
        default: .shape(
            kind: .rectangle,
            frame: frame,
            strokeColor: .black,
            fillColor: nil,
            lineWidth: 2
        )
        }
        return BoardItem(
            id: randomUUID(&rng),
            zIndex: rng.int(in: -5...20),
            createdAt: randomDate(&rng),
            content: content
        )
    }

    private func randomRect(_ rng: inout SplitMix64) -> CGRect {
        CGRect(
            x: rng.double(in: -1_500...1_500),
            y: rng.double(in: -1_500...1_500),
            width: rng.double(in: 0...900),
            height: rng.double(in: 0...900)
        )
    }

    // MARK: - items(in:)

    /// 400 seeded boards of frame-backed objects and random rectangles.
    /// `items(in:)` must return exactly the items whose frames intersect the
    /// rectangle, in draw order.
    ///
    /// Ink and connectors are left out of the generated boards on purpose:
    /// they have no frame, so `items(in:)` decides them from stroke bounds and
    /// connector endpoints instead. That behaviour is covered below.
    @Test func itemsInRectReturnsExactlyTheIntersectingFramesInDrawOrder() {
        var rng = SplitMix64(seed: 0xA4_11_0001)
        var nonEmptyCases = 0

        for _ in 0..<400 {
            var items: [BoardItem] = []
            for _ in 0..<rng.int(in: 0...20) {
                items.append(frameBackedItem(&rng))
            }
            // A tombstoned payload must never come back.
            var deleted = Set<UUID>()
            if let hidden = items.randomElement(using: &rng), rng.chance(0.4) {
                deleted.insert(hidden.id)
            }
            let board = Board(items: items, deletedItemIDs: deleted, createdAt: epoch)
            let rect = randomRect(&rng)

            let expected = board.normalizedZOrder()
                .filter { $0.frame?.intersects(rect) == true }
            let actual = board.items(in: rect)

            #expect(actual.map(\.id) == expected.map(\.id))
            if !actual.isEmpty {
                nonEmptyCases += 1
            }
        }

        #expect(nonEmptyCases > 25)
    }

    @Test func itemsInRectIncludesInkWhoseStrokesReachIt() {
        var rng = SplitMix64(seed: 11)
        let stroke = makeStroke(&rng)
        let ink = BoardItem(id: randomUUID(&rng), createdAt: epoch, content: .ink(strokes: [stroke]))
        let board = Board(items: [ink], createdAt: epoch)
        guard let inkBounds = ink.bounds else {
            Issue.record("The generated stroke has no bounds")
            return
        }

        #expect(board.items(in: inkBounds).map(\.id) == [ink.id])
        #expect(board.items(in: inkBounds.offsetBy(dx: 10_000, dy: 10_000)).isEmpty)
    }

    @Test func itemsInRectKeepsAConnectorWhoseEndpointIsVisible() {
        var rng = SplitMix64(seed: 12)
        let a = BoardItem(
            id: randomUUID(&rng),
            zIndex: 0,
            createdAt: epoch,
            content: .sticky("A", frame: CGRect(x: 0, y: 0, width: 50, height: 50), color: .black)
        )
        let b = BoardItem(
            id: randomUUID(&rng),
            zIndex: 1,
            createdAt: epoch,
            content: .sticky("B", frame: CGRect(x: 5_000, y: 5_000, width: 50, height: 50), color: .black)
        )
        let connector = BoardItem(
            id: randomUUID(&rng),
            zIndex: 2,
            createdAt: epoch,
            content: .connector(fromItemID: a.id, toItemID: b.id, style: .straight)
        )
        let board = Board(items: [a, b, connector], createdAt: epoch)

        let nearA = board.items(in: CGRect(x: -10, y: -10, width: 100, height: 100))
        #expect(nearA.map(\.id) == [a.id, connector.id])

        let nowhere = board.items(in: CGRect(x: 20_000, y: 20_000, width: 10, height: 10))
        #expect(nowhere.isEmpty)
    }

    // MARK: - frameBackedItems(in:)

    /// The viewport query must agree with `items(in:)` on frame-backed
    /// objects, never pay for ink bounds, and always keep the objects it is
    /// told to keep.
    @Test func frameBackedItemsMatchesItemsInAndKeepsTheSelection() {
        var rng = SplitMix64(seed: 0xA4_11_0002)
        var keptFromOutside = 0

        for _ in 0..<400 {
            var items: [BoardItem] = []
            for _ in 0..<rng.int(in: 0...20) {
                items.append(frameBackedItem(&rng))
            }
            let board = Board(items: items, createdAt: epoch)
            let rect = randomRect(&rng)

            let plain = board.frameBackedItems(in: rect)
            #expect(plain.map(\.id) == board.items(in: rect).map(\.id))

            guard let selected = items.randomElement(using: &rng) else { continue }
            let kept = board.frameBackedItems(in: rect, alwaysIncluding: [selected.id])

            // Draw order is preserved, whatever was added.
            let order = board.normalizedZOrder().map(\.id)
            let positions = kept.map { item in order.firstIndex(of: item.id) ?? -1 }
            #expect(positions == positions.sorted())
            #expect(kept.contains { $0.id == selected.id })
            if !plain.contains(where: { $0.id == selected.id }) {
                keptFromOutside += 1
            }
        }

        #expect(keptFromOutside > 50)
    }
}
