import BoardKit
import Foundation
import Observation

/// Owns the whiteboard library: one JSON board file per board under a
/// caller-supplied directory.
///
/// The model is intentionally thin — `BoardKit` owns the file format and
/// `BoardEditorView` owns a board's editing session. The list is kept in
/// most-recently-updated order so the library sheet mirrors the notebook grid.
@MainActor
@Observable
final class BoardModel {
    /// Directory containing the board files.
    let rootURL: URL

    /// Folder holding images inserted into boards, shared by every board.
    var assetsDirectory: URL {
        rootURL.appendingPathComponent("Assets", isDirectory: true)
    }

    private let store: BoardStore
    /// Last saved camera per board, so a plain `save(board)` does not discard
    /// the viewport stored by an earlier editing session.
    private var cameras: [UUID: BoardCamera] = [:]

    private(set) var boards: [Board] = []
    private(set) var isLoading = true
    var lastError: String?

    init(rootURL: URL) {
        self.rootURL = rootURL
        store = BoardStore(rootURL: rootURL)
    }

    // MARK: - Loading

    /// Reloads every board file. One unreadable file does not hide the rest;
    /// the failures are reported together through `lastError`.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let ids = try await store.list()
            var loadedBoards: [Board] = []
            var loadedCameras: [UUID: BoardCamera] = [:]
            var failures: [String] = []

            for id in ids {
                do {
                    let document = try await store.load(id)
                    loadedBoards.append(document.board)
                    loadedCameras[id] = document.camera
                } catch {
                    failures.append(error.localizedDescription)
                }
            }

            boards = Self.sorted(loadedBoards)
            cameras = loadedCameras
            lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        } catch {
            boards = []
            cameras = [:]
            lastError = error.localizedDescription
        }
    }

    // MARK: - Mutation

    /// Creates and saves a board with a trimmed title, then returns it.
    func createBoard(title: String) async -> Board? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let board = Board(title: trimmed.isEmpty ? "Untitled Board" : trimmed)

        do {
            try await store.save(BoardDocument(board: board))
            boards.append(board)
            boards = Self.sorted(boards)
            lastError = nil
            return board
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Saves one board's document. The optional camera keeps the scroll and
    /// zoom position with the board; without it the last known camera is used.
    ///
    /// Returns `false` when the write failed; the failure is also published
    /// through ``lastError`` so the editor can stay open.
    @discardableResult
    func save(_ board: Board, camera: BoardCamera? = nil) async -> Bool {
        var updated = board
        updated.updatedAt = Date()
        let documentCamera = camera ?? cameras[board.id] ?? BoardCamera()

        do {
            try await store.save(BoardDocument(board: updated, camera: documentCamera))
            cameras[updated.id] = documentCamera
            if let index = boards.firstIndex(where: { $0.id == updated.id }) {
                boards[index] = updated
            } else {
                boards.append(updated)
            }
            boards = Self.sorted(boards)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Writes an image inserted into a board and returns the asset name the
    /// board item stores.
    func addAsset(_ data: Data, fileExtension: String) async throws -> String {
        try await store.addAsset(data, fileExtension: fileExtension)
    }

    /// Renames a board, keeping its items and camera.
    @discardableResult
    func rename(_ board: Board, to title: String) async -> Bool {
        var updated = board
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? "Untitled Board" : trimmed
        return await save(updated)
    }

    /// The last camera seen for a board, or `nil` when there is no viewport
    /// worth restoring (a board that has never been positioned).
    func camera(for boardID: UUID) -> BoardCamera? {
        guard let camera = cameras[boardID] else { return nil }
        // The stored default means "never positioned": let the page fit itself.
        if camera.centerX == 0, camera.centerY == 0, camera.zoom == 1 { return nil }
        return camera
    }

    /// The board with this identity, if it is still in the library.
    func board(withID id: UUID) -> Board? {
        boards.first { $0.id == id }
    }

    /// Deletes a board file and removes it from the list.
    func delete(_ board: Board) async {
        do {
            try await store.delete(board.id)
            boards.removeAll { $0.id == board.id }
            cameras.removeValue(forKey: board.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Ordering

    private static func sorted(_ boards: [Board]) -> [Board] {
        boards.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.title != rhs.title {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
