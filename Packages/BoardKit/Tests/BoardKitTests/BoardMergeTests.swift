import BoardKit
import CoreGraphics
import NoteCore
import XCTest

final class BoardMergeTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 100)

    private func textItem(
        id: UUID,
        text: String,
        updatedAt: Date,
        zIndex: Int = 0
    ) -> BoardItem {
        BoardItem(
            id: id,
            zIndex: zIndex,
            createdAt: epoch,
            updatedAt: updatedAt,
            content: .text(
                text,
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                fontSize: 12,
                color: .black
            )
        )
    }

    func testMergeUsesNewerItemAndUnionsTombstones() {
        let boardID = UUID()
        let sharedID = UUID()
        let deletedID = UUID()
        let old = textItem(id: sharedID, text: "old", updatedAt: epoch)
        let new = textItem(
            id: sharedID,
            text: "new",
            updatedAt: epoch.addingTimeInterval(10)
        )

        let a = Board(
            id: boardID,
            title: "A",
            items: [old],
            createdAt: epoch,
            updatedAt: epoch
        )
        var b = Board(
            id: boardID,
            title: "B",
            items: [new],
            createdAt: epoch,
            updatedAt: epoch.addingTimeInterval(10)
        )
        b.deletedItemIDs = [deletedID]

        let merged = BoardMerge.merge(a, b)

        XCTAssertEqual(merged.item(sharedID), new)
        XCTAssertEqual(merged.title, "B")
        XCTAssertEqual(merged.updatedAt, epoch.addingTimeInterval(10))
        XCTAssertEqual(merged.deletedItemIDs, [deletedID])
        XCTAssertEqual(merged.items.count, 1)
    }

    func testTombstoneWinsButRetainsThePayloadForFutureMerges() {
        let boardID = UUID()
        let sharedID = UUID()
        let item = textItem(id: sharedID, text: "kept", updatedAt: epoch)

        let a = Board(id: boardID, items: [item], createdAt: epoch, updatedAt: epoch)
        var b = Board(id: boardID, createdAt: epoch, updatedAt: epoch.addingTimeInterval(1))
        b.deletedItemIDs = [sharedID]

        let merged = BoardMerge.merge(a, b)

        XCTAssertTrue(merged.items.contains { $0.id == sharedID })
        XCTAssertTrue(merged.deletedItemIDs.contains(sharedID))
        XCTAssertTrue(merged.visibleItems.isEmpty)
        XCTAssertTrue(merged.normalizedZOrder().isEmpty)
    }

    func testEqualUpdatedAtTieBreakIsCommutative() {
        let boardID = UUID()
        let sharedID = UUID()
        let left = textItem(id: sharedID, text: "left", updatedAt: epoch)
        let right = textItem(id: sharedID, text: "right", updatedAt: epoch)
        let a = Board(id: boardID, items: [left], createdAt: epoch, updatedAt: epoch)
        let b = Board(id: boardID, items: [right], createdAt: epoch, updatedAt: epoch)

        let ab = BoardMerge.merge(a, b)
        let ba = BoardMerge.merge(b, a)

        XCTAssertEqual(ab, ba)
        XCTAssertNotNil(ab.item(sharedID))
    }

    func testMergeIsCommutativeOnGeneratedBoards() {
        var rng = SplitMix64(seed: 0xB0A2D_0001)
        for _ in 0..<100 {
            let boardID = randomUUID(&rng)
            let pool = (0..<12).map { _ in randomUUID(&rng) }
            let a = randomBoard(&rng, boardID: boardID, pool: pool)
            let b = randomBoard(&rng, boardID: boardID, pool: pool)

            XCTAssertEqual(BoardMerge.merge(a, b), BoardMerge.merge(b, a))
        }
    }

    func testMergeIsAssociativeOnGeneratedBoards() {
        var rng = SplitMix64(seed: 0xB0A2D_0002)
        for _ in 0..<100 {
            let boardID = randomUUID(&rng)
            let pool = (0..<12).map { _ in randomUUID(&rng) }
            let a = randomBoard(&rng, boardID: boardID, pool: pool)
            let b = randomBoard(&rng, boardID: boardID, pool: pool)
            let c = randomBoard(&rng, boardID: boardID, pool: pool)

            let left = BoardMerge.merge(BoardMerge.merge(a, b), c)
            let right = BoardMerge.merge(a, BoardMerge.merge(b, c))
            XCTAssertEqual(left, right)
        }
    }

    func testMergeIsIdempotentAndAbsorbing() {
        var rng = SplitMix64(seed: 0xB0A2D_0003)
        for _ in 0..<100 {
            let boardID = randomUUID(&rng)
            let pool = (0..<12).map { _ in randomUUID(&rng) }
            let a = randomBoard(&rng, boardID: boardID, pool: pool)
            let b = randomBoard(&rng, boardID: boardID, pool: pool)
            let merged = BoardMerge.merge(a, b)

            XCTAssertEqual(BoardMerge.merge(merged, merged), merged)
            XCTAssertEqual(BoardMerge.merge(a, merged), merged)
            XCTAssertEqual(BoardMerge.merge(merged, a), merged)
        }
    }
}
