import XCTest
@testable import NoteApp

/// The launch pass behind `PageBookmarks.prepare`: files are read off the main
/// actor, and a notebook without a file still migrates its UserDefaults list on
/// first use.
@MainActor
final class PageBookmarksPrepareTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageBookmarksPrepareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "PageBookmarksPrepareTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeNotebookDirectory(_ id: UUID) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("notebooks/\(id.uuidString.lowercased())", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func bookmarkFile(for id: UUID) -> URL {
        root.appendingPathComponent("notebooks/\(id.uuidString.lowercased())/bookmarks.json")
    }

    /// A pin already in the file is in the cache after `prepare`, so the first
    /// library frame reads no file per notebook.
    func testPrepareLoadsPinsFromTheFile() async throws {
        let notebookID = UUID()
        let pageID = UUID()
        try makeNotebookDirectory(notebookID)

        let writer = PageBookmarks(root: root, defaults: defaults)
        writer.setTitle("Derivative rules", notebookID: notebookID, pageID: pageID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bookmarkFile(for: notebookID).path))

        let reader = PageBookmarks(root: root, defaults: defaults)
        await reader.prepare(notebookIDs: [notebookID])

        XCTAssertTrue(reader.isBookmarked(notebookID: notebookID, pageID: pageID))
        XCTAssertEqual(reader.bookmark(notebookID: notebookID, pageID: pageID)?.title, "Derivative rules")
        XCTAssertEqual(reader.allBookmarks.map(\.pageID), [pageID])
    }

    /// A notebook with no file is left for the lazy path, which still migrates
    /// the old UserDefaults key and writes the file.
    func testPrepareLeavesNotebooksWithoutAFileForMigration() async throws {
        let notebookID = UUID()
        let pageID = UUID()
        try makeNotebookDirectory(notebookID)
        let legacy = try JSONEncoder().encode([notebookID.uuidString: [pageID.uuidString]])
        defaults.set(legacy, forKey: "noteapp.pageBookmarks.v1")

        let store = PageBookmarks(root: root, defaults: defaults)
        await store.prepare(notebookIDs: [notebookID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookmarkFile(for: notebookID).path))

        // The first read migrates and writes, exactly as before.
        XCTAssertTrue(store.isBookmarked(notebookID: notebookID, pageID: pageID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bookmarkFile(for: notebookID).path))

        let reopened = PageBookmarks(root: root, defaults: defaults)
        await reopened.prepare(notebookIDs: [notebookID])
        XCTAssertTrue(reopened.isBookmarked(notebookID: notebookID, pageID: pageID))
        XCTAssertEqual(reopened.allBookmarks.map(\.pageID), [pageID])
    }

    /// Preparing twice does not duplicate pins or lose a removal.
    func testPrepareIsSafeToRepeatAfterARemoval() async throws {
        let notebookID = UUID()
        let pageID = UUID()
        try makeNotebookDirectory(notebookID)

        let store = PageBookmarks(root: root, defaults: defaults)
        store.toggle(notebookID: notebookID, pageID: pageID)
        await store.prepare(notebookIDs: [notebookID])
        XCTAssertTrue(store.isBookmarked(notebookID: notebookID, pageID: pageID))

        store.toggle(notebookID: notebookID, pageID: pageID)
        await store.prepare(notebookIDs: [notebookID])
        XCTAssertFalse(store.isBookmarked(notebookID: notebookID, pageID: pageID))
        XCTAssertTrue(store.allBookmarks.isEmpty)
    }
}
