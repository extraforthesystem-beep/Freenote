import Foundation

/// A versioned on-disk board file: one board plus its camera.
public struct BoardDocument: Codable, Hashable, Sendable {
    /// Schema version written by this build.
    public static let currentSchemaVersion = Board.currentSchemaVersion

    /// Version of the whole document, checked before the board is decoded.
    public var schemaVersion: Int
    /// The board content.
    public var board: Board
    /// The saved viewport.
    public var camera: BoardCamera

    /// Creates a document. The version defaults to the board's schema version.
    public init(
        board: Board,
        camera: BoardCamera = BoardCamera(),
        schemaVersion: Int? = nil
    ) {
        self.schemaVersion = schemaVersion ?? board.schemaVersion
        self.board = board
        self.camera = camera
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, board, camera
    }

    /// Decodes a document, taking its version from the upgraded board: an
    /// older file opens, and its next save writes the current format.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        board = try container.decode(Board.self, forKey: .board)
        camera = try container.decodeIfPresent(BoardCamera.self, forKey: .camera) ?? BoardCamera()
        schemaVersion = board.schemaVersion
    }
}
