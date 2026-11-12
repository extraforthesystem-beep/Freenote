import Foundation

/// A versioned on-disk board file: one board plus its camera.
public struct BoardDocument: Codable, Hashable, Sendable {
    /// Schema version written by this build.
    public static let currentSchemaVersion = 1

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
}
