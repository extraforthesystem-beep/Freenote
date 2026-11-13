import BoardKit
import CoreGraphics
import NoteCore
import XCTest

final class BoardStoreTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BoardKitTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDocument(id: UUID = UUID()) -> BoardDocument {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123_456)
        let board = Board(
            id: id,
            title: "Store test",
            items: [
                BoardItem(
                    id: UUID(),
                    zIndex: 1,
                    createdAt: date,
                    updatedAt: date,
                    content: .text(
                        "Saved",
                        frame: CGRect(x: 1, y: 2, width: 30, height: 40),
                        fontSize: 14,
                        color: .black
                    )
                )
            ],
            deletedItemIDs: [UUID()],
            createdAt: date,
            updatedAt: date.addingTimeInterval(1),
            schemaVersion: Board.currentSchemaVersion
        )
        return BoardDocument(
            board: board,
            camera: BoardCamera(centerX: 10, centerY: -20, zoom: 2.5)
        )
    }

    func testSaveLoadListAndDeleteRoundTrip() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        let document = makeDocument()

        try await store.save(document)

        let file = store.fileURL(for: document.board.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(
            file.lastPathComponent,
            "\(document.board.id.uuidString.lowercased()).board.json"
        )

        let ids = try await store.list()
        XCTAssertEqual(ids, [document.board.id])

        let loaded = try await store.load(document.board.id)
        XCTAssertEqual(loaded, document)

        try await store.delete(document.board.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let emptyIDs = try await store.list()
        XCTAssertEqual(emptyIDs, [])
        try await store.delete(document.board.id)
    }

    func testOneFilePerBoardAndSortedListing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        let first = makeDocument()
        let second = makeDocument()

        try await store.save(first)
        try await store.save(second)

        let ids = try await store.list()
        XCTAssertEqual(ids, [first.board.id, second.board.id].sorted { $0.uuidString < $1.uuidString })

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(".board.json") }
        XCTAssertEqual(files.count, 2)
    }

    func testLoadRefusesUnknownVersionBeforeDecodingTheBoard() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        let boardID = UUID()
        let url = store.fileURL(for: boardID)
        try Data(#"{"schemaVersion":999}"#.utf8).write(to: url)

        do {
            _ = try await store.load(boardID)
            XCTFail("Expected unsupportedSchemaVersion")
        } catch let error as BoardStoreError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(found: 999, supported: BoardDocument.currentSchemaVersion)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadRefusesUnknownBoardVersionBeforeDecodingTheBoard() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        let boardID = UUID()
        let url = store.fileURL(for: boardID)
        // The board body is intentionally incomplete: the nested version must be
        // rejected before any of the board is decoded.
        try Data(#"{"schemaVersion":1,"board":{"schemaVersion":999}}"#.utf8).write(to: url)

        do {
            _ = try await store.load(boardID)
            XCTFail("Expected unsupportedSchemaVersion")
        } catch let error as BoardStoreError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(found: 999, supported: BoardDocument.currentSchemaVersion)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveRefusesUnknownDocumentVersionWithoutWriting() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        var document = makeDocument()
        document.schemaVersion = 999

        do {
            try await store.save(document)
            XCTFail("Expected unsupportedSchemaVersion")
        } catch let error as BoardStoreError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(found: 999, supported: BoardDocument.currentSchemaVersion)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.fileURL(for: document.board.id).path)
        )
    }

    func testSaveRefusesUnknownBoardVersion() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        var document = makeDocument()
        document.board.schemaVersion = 999

        do {
            try await store.save(document)
            XCTFail("Expected unsupportedSchemaVersion")
        } catch let error as BoardStoreError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(found: 999, supported: BoardDocument.currentSchemaVersion)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadRejectsCorruptJSON() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        let boardID = UUID()
        let url = store.fileURL(for: boardID)
        try Data(#"{"schemaVersion":1,"board":{}}"#.utf8).write(to: url)

        do {
            _ = try await store.load(boardID)
            XCTFail("Expected corruptFile")
        } catch let error as BoardStoreError {
            XCTAssertEqual(error, .corruptFile(url.lastPathComponent))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadRejectsAFileWhoseBoardIDDoesNotMatchItsName() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        let document = makeDocument()
        try await store.save(document)

        let otherID = UUID()
        let source = store.fileURL(for: document.board.id)
        let destination = store.fileURL(for: otherID)
        try FileManager.default.copyItem(at: source, to: destination)

        do {
            _ = try await store.load(otherID)
            XCTFail("Expected corruptFile")
        } catch let error as BoardStoreError {
            XCTAssertEqual(error, .corruptFile(destination.lastPathComponent))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadMissingBoardAndDeleteMissingBoard() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        let boardID = UUID()

        do {
            _ = try await store.load(boardID)
            XCTFail("Expected notFound")
        } catch let error as BoardStoreError {
            XCTAssertEqual(error, .notFound(boardID))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        try await store.delete(boardID)
    }

    func testSaveOverwritesTheSameBoardFile() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        var document = makeDocument()

        try await store.save(document)
        document.board.title = "Updated title"
        try await store.save(document)

        let ids = try await store.list()
        XCTAssertEqual(ids, [document.board.id])
        let loaded = try await store.load(document.board.id)
        XCTAssertEqual(loaded.board.title, "Updated title")
    }

    func testSaveCreatesTheRootDirectoryAndListHandlesAMissingOne() async throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("nested/store", isDirectory: true)
        let store = BoardStore(rootURL: root)

        let emptyIDs = try await store.list()
        XCTAssertEqual(emptyIDs, [])

        let document = makeDocument()
        try await store.save(document)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        let ids = try await store.list()
        XCTAssertEqual(ids, [document.board.id])
    }

    func testLoadUpgradesAVersionOneFile() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)

        var board = makeDocument().board
        board.schemaVersion = 1
        let legacy = BoardDocument(board: board, schemaVersion: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(legacy).write(to: store.fileURL(for: board.id))

        let loaded = try await store.load(board.id)
        XCTAssertEqual(loaded.board.schemaVersion, Board.currentSchemaVersion)
        XCTAssertEqual(loaded.schemaVersion, BoardDocument.currentSchemaVersion)
        XCTAssertEqual(loaded.board.items, board.items)

        // The upgraded document saves over the old file in the current format.
        try await store.save(loaded)
        let data = try Data(contentsOf: store.fileURL(for: board.id))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["schemaVersion"] as? Int, BoardDocument.currentSchemaVersion)
    }

    func testAddAssetWritesUnderTheAssetsFolder() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(rootURL: directory)
        let data = Data([1, 2, 3, 4])

        let name = try await store.addAsset(data, fileExtension: "PNG")
        XCTAssertTrue(name.hasSuffix(".png"))

        let file = store.assetsDirectoryURL.appendingPathComponent(name)
        XCTAssertEqual(store.assetsDirectoryURL.lastPathComponent, "Assets")
        XCTAssertEqual(try Data(contentsOf: file), data)

        let other = try await store.addAsset(data, fileExtension: "")
        XCTAssertNotEqual(other, name)
        XCTAssertTrue(other.hasSuffix(".png"))
    }
}
