import XCTest
@testable import NoteApp

@MainActor
final class PageBookmarksTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageBookmarksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "PageBookmarksTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeNotebookDirectories(_ ids: [UUID]) throws {
        for id in ids {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("notebooks/\(id.uuidString.lowercased())", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func writeLegacy(_ pages: [String: Set<String>]) throws {
        let data = try JSONEncoder().encode(pages)
        defaults.set(data, forKey: "noteapp.pageBookmarks.v1")
    }

    func testLegacyBookmarksMigrateOnceAndStayReadable() throws {
        let notebookID = UUID()
        let pageID = UUID()
        try makeNotebookDirectories([notebookID])
        try writeLegacy([notebookID.uuidString: [pageID.uuidString]])

        let store = PageBookmarks(root: root, defaults: defaults)
        XCTAssertTrue(store.isBookmarked(notebookID: notebookID, pageID: pageID))

        let file = root.appendingPathComponent(
            "notebooks/\(notebookID.uuidString.lowercased())/bookmarks.json"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        // Removing a migrated pin must not be undone by the legacy list on the
        // next launch: the file exists and wins, even when it is empty.
        store.toggle(notebookID: notebookID, pageID: pageID)
        XCTAssertFalse(store.isBookmarked(notebookID: notebookID, pageID: pageID))

        let reopened = PageBookmarks(root: root, defaults: defaults)
        XCTAssertFalse(reopened.isBookmarked(notebookID: notebookID, pageID: pageID))
        XCTAssertTrue(reopened.bookmarkedPageIDs(notebookID: notebookID).isEmpty)

        // The old key is untouched, so a build without this code still reads it.
        let legacyData = try XCTUnwrap(defaults.data(forKey: "noteapp.pageBookmarks.v1"))
        let legacy = try JSONDecoder().decode([String: Set<String>].self, from: legacyData)
        XCTAssertEqual(legacy, [notebookID.uuidString: [pageID.uuidString]])
    }

    func testNamedBookmarkRoundTripsThroughTheNotebookFolder() throws {
        let notebookID = UUID()
        let pageID = UUID()
        try makeNotebookDirectories([notebookID])

        let store = PageBookmarks(root: root, defaults: defaults)
        store.setTitle("Derivative rules", notebookID: notebookID, pageID: pageID)
        XCTAssertEqual(
            store.bookmark(notebookID: notebookID, pageID: pageID)?.title,
            "Derivative rules"
        )

        let reopened = PageBookmarks(root: root, defaults: defaults)
        let bookmark = reopened.bookmark(notebookID: notebookID, pageID: pageID)
        XCTAssertEqual(bookmark?.title, "Derivative rules")
        XCTAssertEqual(bookmark?.pageID, pageID)
        XCTAssertEqual(reopened.allBookmarks.map(\.pageID), [pageID])

        // Clearing the name keeps the pin.
        reopened.setTitle("  ", notebookID: notebookID, pageID: pageID)
        XCTAssertNotNil(reopened.bookmark(notebookID: notebookID, pageID: pageID))
        XCTAssertNil(reopened.bookmark(notebookID: notebookID, pageID: pageID)?.title)
    }

    func testBookmarkFileIsIgnoredWithoutLegacyData() throws {
        let notebookID = UUID()
        let pageID = UUID()
        try makeNotebookDirectories([notebookID])

        let store = PageBookmarks(root: root, defaults: defaults)
        XCTAssertFalse(store.isBookmarked(notebookID: notebookID, pageID: pageID))
        store.toggle(notebookID: notebookID, pageID: pageID)

        let reopened = PageBookmarks(root: root, defaults: defaults)
        XCTAssertTrue(reopened.isBookmarked(notebookID: notebookID, pageID: pageID))
        XCTAssertEqual(reopened.allBookmarks.count, 1)
    }
}
