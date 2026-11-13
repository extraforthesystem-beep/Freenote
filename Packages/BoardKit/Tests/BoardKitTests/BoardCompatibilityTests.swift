import BoardKit
import CoreGraphics
import NoteCore
import XCTest

/// Old files, unknown item kinds and the sticky-note kind.
final class BoardCompatibilityTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private func textItem(id: UUID = UUID()) -> BoardItem {
        BoardItem(
            id: id,
            zIndex: 1,
            createdAt: epoch,
            updatedAt: epoch,
            content: .text(
                "Hello",
                frame: CGRect(x: 10, y: 20, width: 100, height: 40),
                fontSize: 16,
                color: .black
            )
        )
    }

    private func stickyItem(id: UUID = UUID()) -> BoardItem {
        BoardItem(
            id: id,
            zIndex: 2,
            createdAt: epoch,
            updatedAt: epoch,
            content: .sticky(
                "Remember",
                frame: CGRect(x: 40, y: 50, width: 200, height: 200),
                color: RGBAColor(r: 1, g: 0.95, b: 0.62)
            )
        )
    }

    func testStickyNoteIsAFrameBackedItem() {
        var board = Board(id: UUID(), createdAt: epoch, updatedAt: epoch)
        let sticky = stickyItem()
        board.add(sticky)

        XCTAssertEqual(sticky.frame, CGRect(x: 40, y: 50, width: 200, height: 200))
        XCTAssertEqual(sticky.bounds, sticky.frame)
        XCTAssertEqual(board.bounds(), sticky.frame)

        XCTAssertTrue(board.move(sticky.id, to: CGPoint(x: 0, y: 5)))
        XCTAssertEqual(
            board.item(sticky.id)?.frame,
            CGRect(x: 0, y: 5, width: 200, height: 200)
        )

        XCTAssertTrue(board.resize(sticky.id, to: CGSize(width: 120, height: 120)))
        XCTAssertEqual(
            board.item(sticky.id)?.frame,
            CGRect(x: 0, y: 5, width: 120, height: 120)
        )

        XCTAssertTrue(board.setFrame(sticky.id, to: CGRect(x: 7, y: 8, width: 90, height: 90), at: epoch))
        XCTAssertEqual(board.item(sticky.id)?.frame, CGRect(x: 7, y: 8, width: 90, height: 90))
    }

    func testVersionOneBoardUpgradesOnDecode() throws {
        let board = Board(
            id: UUID(),
            title: "Old board",
            items: [textItem()],
            createdAt: epoch,
            updatedAt: epoch,
            schemaVersion: 1
        )
        let data = try encoder().encode(board)

        let decoded = try decoder().decode(Board.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, Board.currentSchemaVersion)
        XCTAssertEqual(decoded.items, board.items)
        XCTAssertEqual(decoded.title, board.title)
    }

    func testUnknownItemKindIsSkipped() throws {
        let kept = textItem()
        let board = Board(
            id: UUID(),
            title: "Mixed",
            items: [kept],
            createdAt: epoch,
            updatedAt: epoch,
            schemaVersion: 1
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder().encode(board)) as? [String: Any]
        )
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        items.append([
            "id": UUID().uuidString,
            "zIndex": 9,
            "isLocked": false,
            "createdAt": 0,
            "updatedAt": 0,
            "content": ["kind": "hologram"],
        ])
        json["items"] = items

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder().decode(Board.self, from: data)

        XCTAssertEqual(decoded.items.map(\.id), [kept.id])
        XCTAssertEqual(decoded.schemaVersion, Board.currentSchemaVersion)
    }

    func testStickyNoteRoundTrip() throws {
        let item = stickyItem()
        let board = Board(
            id: UUID(),
            title: "Sticky",
            items: [item],
            createdAt: epoch,
            updatedAt: epoch
        )

        let data = try encoder().encode(board)
        let decoded = try decoder().decode(Board.self, from: data)
        XCTAssertEqual(decoded, board)
        XCTAssertEqual(decoded.items.first?.frame, item.frame)
    }
}
