import BoardKit
import CoreGraphics
import NoteCore
import XCTest

final class BoardLayoutTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 100)
    private let layoutDate = Date(timeIntervalSince1970: 500)

    private func item(
        id: UUID = UUID(),
        frame: CGRect,
        locked: Bool = false
    ) -> BoardItem {
        BoardItem(
            id: id,
            zIndex: 0,
            isLocked: locked,
            createdAt: epoch,
            updatedAt: epoch,
            content: .text("Item", frame: frame, fontSize: 12, color: .black)
        )
    }

    private func threeItemBoard() -> (Board, [BoardItem]) {
        let a = item(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = item(frame: CGRect(x: 100, y: 50, width: 20, height: 20))
        let c = item(frame: CGRect(x: 200, y: 100, width: 30, height: 30))
        let board = Board(items: [a, b, c], createdAt: epoch, updatedAt: epoch)
        return (board, [a, b, c])
    }

    private func frames(_ board: Board, _ items: [BoardItem]) -> [CGRect] {
        items.map { board.item($0.id)?.frame ?? .null }
    }

    func testHorizontalAlignmentsPreserveSizes() {
        let expectations: [(BoardAlignment, [CGRect])] = [
            (.left, [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 0, y: 50, width: 20, height: 20),
                CGRect(x: 0, y: 100, width: 30, height: 30),
            ]),
            (.center, [
                CGRect(x: 110, y: 0, width: 10, height: 10),
                CGRect(x: 105, y: 50, width: 20, height: 20),
                CGRect(x: 100, y: 100, width: 30, height: 30),
            ]),
            (.right, [
                CGRect(x: 220, y: 0, width: 10, height: 10),
                CGRect(x: 210, y: 50, width: 20, height: 20),
                CGRect(x: 200, y: 100, width: 30, height: 30),
            ]),
        ]

        for (alignment, expected) in expectations {
            let (initial, items) = threeItemBoard()
            var board = initial
            BoardLayout.align(
                alignment,
                itemIDs: Set(items.map(\.id)),
                in: &board,
                at: layoutDate
            )
            XCTAssertEqual(frames(board, items), expected, "alignment \(alignment)")
        }
    }

    func testVerticalAlignmentsPreserveSizes() {
        let expectations: [(BoardAlignment, [CGRect])] = [
            (.top, [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 100, y: 0, width: 20, height: 20),
                CGRect(x: 200, y: 0, width: 30, height: 30),
            ]),
            (.middle, [
                CGRect(x: 0, y: 60, width: 10, height: 10),
                CGRect(x: 100, y: 55, width: 20, height: 20),
                CGRect(x: 200, y: 50, width: 30, height: 30),
            ]),
            (.bottom, [
                CGRect(x: 0, y: 120, width: 10, height: 10),
                CGRect(x: 100, y: 110, width: 20, height: 20),
                CGRect(x: 200, y: 100, width: 30, height: 30),
            ]),
        ]

        for (alignment, expected) in expectations {
            let (initial, items) = threeItemBoard()
            var board = initial
            BoardLayout.align(
                alignment,
                itemIDs: Set(items.map(\.id)),
                in: &board,
                at: layoutDate
            )
            XCTAssertEqual(frames(board, items), expected, "alignment \(alignment)")
        }
    }

    func testDistributeHorizontallyUsesEqualGapsAndKeepsEndsFixed() {
        let a = item(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = item(frame: CGRect(x: 100, y: 0, width: 20, height: 20))
        let c = item(frame: CGRect(x: 200, y: 0, width: 30, height: 30))
        var board = Board(items: [a, b, c], createdAt: epoch, updatedAt: epoch)

        BoardLayout.distribute(
            .horizontal,
            itemIDs: [a.id, b.id, c.id],
            in: &board,
            at: layoutDate
        )

        XCTAssertEqual(
            frames(board, [a, b, c]),
            [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 95, y: 0, width: 20, height: 20),
                CGRect(x: 200, y: 0, width: 30, height: 30),
            ]
        )
    }

    func testDistributeVerticallyUsesEqualGapsAndKeepsEndsFixed() {
        let a = item(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = item(frame: CGRect(x: 0, y: 100, width: 20, height: 20))
        let c = item(frame: CGRect(x: 0, y: 200, width: 30, height: 30))
        var board = Board(items: [a, b, c], createdAt: epoch, updatedAt: epoch)

        BoardLayout.distribute(
            .vertical,
            itemIDs: [a.id, b.id, c.id],
            in: &board,
            at: layoutDate
        )

        XCTAssertEqual(
            frames(board, [a, b, c]),
            [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 0, y: 95, width: 20, height: 20),
                CGRect(x: 0, y: 200, width: 30, height: 30),
            ]
        )
    }

    func testDistributeNeedsAtLeastThreeItems() {
        let a = item(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = item(frame: CGRect(x: 100, y: 0, width: 20, height: 20))
        var board = Board(items: [a, b], createdAt: epoch, updatedAt: epoch)

        BoardLayout.distribute(
            .horizontal,
            itemIDs: [a.id, b.id],
            in: &board,
            at: layoutDate
        )

        XCTAssertEqual(frames(board, [a, b]), [
            CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 100, y: 0, width: 20, height: 20),
        ])
    }

    func testLockedItemsAreIgnored() {
        let a = item(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let locked = item(frame: CGRect(x: 100, y: 50, width: 20, height: 20), locked: true)
        let c = item(frame: CGRect(x: 200, y: 100, width: 30, height: 30))
        var board = Board(items: [a, locked, c], createdAt: epoch, updatedAt: epoch)

        BoardLayout.align(
            .left,
            itemIDs: [a.id, locked.id, c.id],
            in: &board,
            at: layoutDate
        )

        XCTAssertEqual(
            frames(board, [a, locked, c]),
            [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 100, y: 50, width: 20, height: 20),
                CGRect(x: 0, y: 100, width: 30, height: 30),
            ]
        )
    }

    func testOnlySelectedItemsMove() {
        let a = item(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = item(frame: CGRect(x: 100, y: 50, width: 20, height: 20))
        let c = item(frame: CGRect(x: 200, y: 100, width: 30, height: 30))
        var board = Board(items: [a, b, c], createdAt: epoch, updatedAt: epoch)

        BoardLayout.align(
            .right,
            itemIDs: [a.id, b.id],
            in: &board,
            at: layoutDate
        )

        XCTAssertEqual(
            frames(board, [a, b, c]),
            [
                CGRect(x: 110, y: 0, width: 10, height: 10),
                CGRect(x: 100, y: 50, width: 20, height: 20),
                CGRect(x: 200, y: 100, width: 30, height: 30),
            ]
        )
    }

    func testTombstonedAndNonFrameItemsAreIgnored() {
        let a = item(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let c = item(frame: CGRect(x: 200, y: 100, width: 30, height: 30))
        let stroke = StrokeRecord(
            id: UUID(),
            layerID: UUID(),
            tool: StrokeTool(engine: "metal", inkType: "pen", color: .black, width: 2),
            createdAt: epoch,
            randomSeed: 1,
            points: [
                StrokePoint(
                    x: 50,
                    y: 50,
                    timeOffset: 0,
                    width: 1,
                    height: 1,
                    opacity: 1,
                    force: 0.5,
                    azimuth: 0,
                    altitude: 1,
                    secondaryScale: 1
                )
            ]
        )
        let ink = BoardItem(content: .ink(strokes: [stroke]))
        var board = Board(
            items: [a, c, ink],
            deletedItemIDs: [c.id],
            createdAt: epoch,
            updatedAt: epoch
        )

        BoardLayout.align(
            .left,
            itemIDs: [a.id, c.id, ink.id],
            in: &board,
            at: layoutDate
        )

        XCTAssertEqual(
            frames(board, [a, c, ink]),
            [
                CGRect(x: 0, y: 0, width: 10, height: 10),
                CGRect(x: 200, y: 100, width: 30, height: 30),
                .null,
            ]
        )
    }

    func testLayoutUpdatesItemAndBoardDates() {
        let a = item(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = item(frame: CGRect(x: 100, y: 50, width: 20, height: 20))
        var board = Board(items: [a, b], createdAt: epoch, updatedAt: epoch)

        BoardLayout.align(
            .left,
            itemIDs: [a.id, b.id],
            in: &board,
            at: layoutDate
        )

        XCTAssertEqual(board.item(b.id)?.updatedAt, layoutDate)
        XCTAssertEqual(board.updatedAt, layoutDate)
    }
}
