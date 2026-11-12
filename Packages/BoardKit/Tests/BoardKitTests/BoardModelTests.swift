import BoardKit
import CoreGraphics
import NoteCore
import XCTest

final class BoardModelTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)

    private func textItem(
        id: UUID = UUID(),
        frame: CGRect = CGRect(x: 10, y: 20, width: 100, height: 40),
        zIndex: Int = 0,
        createdAt: Date? = nil
    ) -> BoardItem {
        BoardItem(
            id: id,
            zIndex: zIndex,
            createdAt: createdAt ?? epoch,
            content: .text("Hello", frame: frame, fontSize: 16, color: .black)
        )
    }

    func testAddRemoveTombstoneAndReAdd() {
        var board = Board(id: UUID(), title: "Test", createdAt: epoch, updatedAt: epoch)
        let item = textItem()

        board.add(item, at: epoch.addingTimeInterval(1))
        XCTAssertEqual(board.items.count, 1)
        XCTAssertEqual(board.item(item.id), item)
        XCTAssertEqual(board.visibleItems, [item])
        XCTAssertEqual(board.updatedAt, epoch.addingTimeInterval(1))

        let removed = board.remove(item.id, at: epoch.addingTimeInterval(2))
        XCTAssertEqual(removed, item)
        XCTAssertTrue(board.items.isEmpty)
        XCTAssertTrue(board.deletedItemIDs.contains(item.id))
        XCTAssertNil(board.item(item.id))
        XCTAssertTrue(board.visibleItems.isEmpty)

        board.add(item, at: epoch.addingTimeInterval(3))
        XCTAssertFalse(board.deletedItemIDs.contains(item.id))
        XCTAssertEqual(board.visibleItems, [item])
        XCTAssertEqual(board.updatedAt, epoch.addingTimeInterval(3))
    }

    func testAddReplacesAnItemWithTheSameID() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let item = textItem(zIndex: 2)
        board.add(item, at: epoch.addingTimeInterval(1))

        var replacement = item
        replacement.zIndex = 9
        replacement.content = .text(
            "Replaced",
            frame: CGRect(x: 1, y: 2, width: 3, height: 4),
            fontSize: 20,
            color: .black
        )
        board.add(replacement, at: epoch.addingTimeInterval(2))

        XCTAssertEqual(board.items.count, 1)
        XCTAssertEqual(board.item(item.id), replacement)
    }

    func testMoveResizeAndLock() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let item = BoardItem(
            id: UUID(),
            createdAt: epoch,
            content: .image(assetName: "photo", frame: CGRect(x: 10, y: 20, width: 100, height: 40))
        )
        board.add(item, at: epoch.addingTimeInterval(1))

        XCTAssertTrue(
            board.move(item.id, to: CGPoint(x: 50, y: 60), at: epoch.addingTimeInterval(2))
        )
        XCTAssertEqual(
            board.item(item.id)?.frame,
            CGRect(x: 50, y: 60, width: 100, height: 40)
        )
        XCTAssertEqual(board.item(item.id)?.updatedAt, epoch.addingTimeInterval(2))

        XCTAssertTrue(
            board.resize(item.id, to: CGSize(width: 200, height: 80), at: epoch.addingTimeInterval(3))
        )
        XCTAssertEqual(
            board.item(item.id)?.frame,
            CGRect(x: 50, y: 60, width: 200, height: 80)
        )

        XCTAssertTrue(board.lock(item.id, at: epoch.addingTimeInterval(4)))
        XCTAssertTrue(board.item(item.id)?.isLocked == true)
        XCTAssertFalse(
            board.move(item.id, to: CGPoint(x: 0, y: 0), at: epoch.addingTimeInterval(5))
        )
        XCTAssertFalse(
            board.resize(item.id, to: CGSize(width: 1, height: 1), at: epoch.addingTimeInterval(6))
        )
        XCTAssertEqual(
            board.item(item.id)?.frame,
            CGRect(x: 50, y: 60, width: 200, height: 80)
        )
        XCTAssertFalse(board.lock(item.id, true, at: epoch.addingTimeInterval(7)))

        XCTAssertTrue(board.lock(item.id, false, at: epoch.addingTimeInterval(8)))
        XCTAssertTrue(
            board.move(item.id, to: CGPoint(x: 7, y: 8), at: epoch.addingTimeInterval(9))
        )
        XCTAssertEqual(board.updatedAt, epoch.addingTimeInterval(9))
    }

    func testResizeClampsNegativeSizes() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let item = textItem()
        board.add(item)

        XCTAssertTrue(board.resize(item.id, to: CGSize(width: -5, height: -10)))
        XCTAssertEqual(
            board.item(item.id)?.frame,
            CGRect(x: 10, y: 20, width: 0, height: 0)
        )
    }

    func testInkAndConnectorsCannotBeMovedOrResized() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let stroke = StrokeRecord(
            id: UUID(),
            layerID: UUID(),
            tool: StrokeTool(engine: "metal", inkType: "pen", color: .black, width: 2),
            createdAt: epoch,
            randomSeed: 1,
            points: [
                StrokePoint(
                    x: 0,
                    y: 0,
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
        let connector = BoardItem(
            content: .connector(fromItemID: ink.id, toItemID: UUID(), style: .straight)
        )
        board.add(ink)
        board.add(connector)

        XCTAssertFalse(board.move(ink.id, to: .zero))
        XCTAssertFalse(board.resize(ink.id, to: CGSize(width: 10, height: 10)))
        XCTAssertFalse(board.move(connector.id, to: .zero))
        XCTAssertFalse(board.resize(connector.id, to: CGSize(width: 10, height: 10)))
        XCTAssertNil(ink.frame)
        XCTAssertNil(connector.frame)
    }

    func testNormalizedZOrderIsDeterministic() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let low = textItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, zIndex: 5)
        let firstMiddle = textItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            zIndex: 3,
            createdAt: epoch.addingTimeInterval(1)
        )
        let secondMiddle = textItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            zIndex: 3,
            createdAt: epoch.addingTimeInterval(1)
        )
        let first = textItem(zIndex: 1)

        board.add(low)
        board.add(secondMiddle)
        board.add(first)
        board.add(firstMiddle)

        XCTAssertEqual(board.normalizedZOrder().map(\.zIndex), [1, 3, 3, 5])
        XCTAssertEqual(
            board.normalizedZOrder().map(\.id),
            [first.id, firstMiddle.id, secondMiddle.id, low.id]
        )
    }

    func testBoundsUnionAndEmptyBoard() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        XCTAssertNil(board.bounds())

        let a = textItem(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = textItem(frame: CGRect(x: 20, y: 20, width: 5, height: 5))
        board.add(a)
        board.add(b)

        XCTAssertEqual(board.bounds(), CGRect(x: 0, y: 0, width: 25, height: 25))
    }

    func testItemsInRectCullsAndReturnsDrawOrder() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let a = textItem(frame: CGRect(x: 0, y: 0, width: 10, height: 10), zIndex: 1)
        let b = textItem(frame: CGRect(x: 100, y: 100, width: 10, height: 10), zIndex: 0)
        board.add(a)
        board.add(b)

        let hit = board.items(in: CGRect(x: 5, y: 5, width: 10, height: 10))
        XCTAssertEqual(hit.map(\.id), [a.id])

        let both = board.items(in: CGRect(x: -10, y: -10, width: 200, height: 200))
        XCTAssertEqual(both.map(\.id), [b.id, a.id])

        XCTAssertTrue(board.items(in: CGRect(x: 50, y: 50, width: 5, height: 5)).isEmpty)
    }

    func testItemsInRectUsesInkBounds() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let stroke = StrokeRecord(
            id: UUID(),
            layerID: UUID(),
            tool: StrokeTool(engine: "metal", inkType: "pen", color: .black, width: 4),
            createdAt: epoch,
            randomSeed: 2,
            points: [
                StrokePoint(
                    x: 500,
                    y: 500,
                    timeOffset: 0,
                    width: 2,
                    height: 2,
                    opacity: 1,
                    force: 0.5,
                    azimuth: 0,
                    altitude: 1,
                    secondaryScale: 1
                )
            ]
        )
        let ink = BoardItem(content: .ink(strokes: [stroke]))
        board.add(ink)

        XCTAssertEqual(ink.bounds, CGRect(x: 498, y: 498, width: 4, height: 4))
        XCTAssertEqual(
            board.items(in: CGRect(x: 490, y: 490, width: 20, height: 20)).map(\.id),
            [ink.id]
        )
        XCTAssertTrue(board.items(in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }

    func testConnectorIsIncludedWhenAnEndpointIsVisible() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let a = textItem(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = textItem(frame: CGRect(x: 500, y: 500, width: 10, height: 10))
        let connector = BoardItem(
            zIndex: 10,
            content: .connector(fromItemID: a.id, toItemID: b.id, style: .curved)
        )
        board.add(a)
        board.add(b)
        board.add(connector)

        let nearA = board.items(in: CGRect(x: -5, y: -5, width: 20, height: 20))
        XCTAssertEqual(Set(nearA.map(\.id)), Set([a.id, connector.id]))

        let empty = board.items(in: CGRect(x: 200, y: 200, width: 10, height: 10))
        XCTAssertTrue(empty.isEmpty)
    }

    func testTombstonedPayloadIsHiddenFromReaders() {
        let item = textItem()
        let board = Board(
            id: UUID(),
            items: [item],
            deletedItemIDs: [item.id],
            createdAt: epoch,
            updatedAt: epoch
        )

        XCTAssertEqual(board.items.count, 1)
        XCTAssertTrue(board.visibleItems.isEmpty)
        XCTAssertTrue(board.normalizedZOrder().isEmpty)
        XCTAssertNil(board.bounds())
        XCTAssertTrue(board.items(in: CGRect(x: -1_000, y: -1_000, width: 2_000, height: 2_000)).isEmpty)
    }

    func testCodableRoundTripForEveryContentCase() throws {
        let imageID = UUID()
        let textID = UUID()
        let stroke = StrokeRecord(
            id: UUID(),
            layerID: UUID(),
            tool: StrokeTool(engine: "metal", inkType: "pen", color: .black, width: 3),
            createdAt: epoch,
            randomSeed: 42,
            points: [
                StrokePoint(
                    x: 1,
                    y: 2,
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
        let items = [
            BoardItem(id: UUID(), zIndex: 0, createdAt: epoch, content: .ink(strokes: [stroke])),
            BoardItem(id: imageID, zIndex: 1, createdAt: epoch, content: .image(assetName: "photo", frame: CGRect(x: 1, y: 2, width: 3, height: 4))),
            BoardItem(id: textID, zIndex: 2, createdAt: epoch, content: .text("Note", frame: CGRect(x: 5, y: 6, width: 70, height: 80), fontSize: 18, color: .black)),
            BoardItem(id: UUID(), zIndex: 3, createdAt: epoch, content: .shape(kind: .ellipse, frame: CGRect(x: 9, y: 10, width: 11, height: 12), strokeColor: .black, fillColor: .white, lineWidth: 2)),
            BoardItem(id: UUID(), zIndex: 4, createdAt: epoch, content: .shape(kind: .rectangle, frame: CGRect(x: 13, y: 14, width: 15, height: 16), strokeColor: .black, fillColor: nil, lineWidth: 1)),
            BoardItem(id: UUID(), zIndex: 5, createdAt: epoch, content: .connector(fromItemID: imageID, toItemID: textID, style: .elbow)),
        ]
        let board = Board(
            id: UUID(),
            title: "Round trip",
            items: items,
            deletedItemIDs: [UUID()],
            createdAt: epoch,
            updatedAt: epoch.addingTimeInterval(5),
            schemaVersion: Board.currentSchemaVersion
        )

        let data = try JSONEncoder().encode(board)
        let decoded = try JSONDecoder().decode(Board.self, from: data)
        XCTAssertEqual(decoded, board)
    }
}
