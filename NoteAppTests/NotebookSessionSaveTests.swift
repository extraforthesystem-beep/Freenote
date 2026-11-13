import XCTest
@testable import NoteApp
import NoteCore

/// The page queue behind `NotebookSession`'s writes: one slot per page, so a
/// failed save of one page cannot be erased by an edit on another.
@MainActor
final class PendingPageQueueTests: XCTestCase {
    private func makePage(width: Double = 600) -> Page {
        Page(id: UUID(), width: width, height: 800, template: .blank)
    }

    func testAFailedPageSurvivesAnEditOnAnotherPage() {
        var queue = PendingPageQueue()
        let a = makePage()
        let b = makePage()
        var newerA = a
        newerA.width = 700

        queue.enqueue(a)
        queue.enqueue(b)
        let first = queue.takeFirst()
        XCTAssertEqual(first, a)

        queue.retry(a)                             // A failed; B still waits
        queue.enqueue(newerA)                      // editing A again
        let retried = queue.takeFirst()
        XCTAssertEqual(retried, newerA)            // newer A, not the failed copy
        let remaining = queue.takeFirst()
        XCTAssertEqual(remaining, b)               // B was never erased
        XCTAssertTrue(queue.isEmpty)
    }

    func testANewerVersionKeepsThePagesPlaceInTheQueue() {
        var queue = PendingPageQueue()
        let a = makePage()
        let b = makePage()
        var newerA = a
        newerA.width = 700

        queue.enqueue(a)
        queue.enqueue(b)
        queue.enqueue(newerA)

        let first = queue.takeFirst()
        XCTAssertEqual(first?.id, a.id)
        XCTAssertEqual(first?.width, 700)
        let second = queue.takeFirst()
        XCTAssertEqual(second, b)
        let empty = queue.takeFirst()
        XCTAssertNil(empty)
    }

    func testAFailedCopyIsDroppedWhenANewerVersionIsWaiting() {
        var queue = PendingPageQueue()
        let a = makePage()
        var newerA = a
        newerA.width = 700

        queue.enqueue(a)
        let taken = queue.takeFirst()
        XCTAssertEqual(taken, a)

        queue.enqueue(newerA)
        queue.retry(a)                             // must not displace the newer copy
        let retried = queue.takeFirst()
        XCTAssertEqual(retried, newerA)
        let empty = queue.takeFirst()
        XCTAssertNil(empty)
    }

    func testRemovingADeletedPageDropsItsQueuedSave() {
        var queue = PendingPageQueue()
        let a = makePage()
        let b = makePage()

        queue.enqueue(a)
        queue.enqueue(b)
        let removed = queue.remove(a.id)
        XCTAssertEqual(removed, a)
        XCTAssertFalse(queue.contains(a.id))

        let next = queue.takeFirst()
        XCTAssertEqual(next, b)
        let empty = queue.takeFirst()
        XCTAssertNil(empty)
    }
}

/// The save and navigation behaviour of a real session on a temporary library.
/// No UI is involved; the session talks to a `LibraryStore` on disk.
@MainActor
final class NotebookSessionSaveTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotebookSessionSaveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        try await super.tearDown()
    }

    private struct Fixture {
        let store: LibraryStore
        let session: NotebookSession
        let notebookID: UUID
        let pageIDs: [UUID]
    }

    private func makeFixture(pageCount: Int) async throws -> Fixture {
        // AppModel is only used to reach a `VersionHistoryStore` without the
        // test target having to link HistoryKit itself. Its history lives in a
        // sibling of the library, inside `fixtureRoot`, so teardown removes it.
        let app = AppModel(root: fixtureRoot.appendingPathComponent("library", isDirectory: true))
        try await app.store.open()
        let notebook = try await app.store.createNotebook(title: "Save tests")
        for _ in 0..<pageCount {
            _ = try await app.store.addPage(
                to: notebook.id,
                at: Int.max,
                width: 600,
                height: 800,
                template: .blank
            )
        }
        let snapshot = try await app.store.loadNotebook(notebook.id)
        let session = NotebookSession(store: app.store, snapshot: snapshot, history: app.history)
        await session.loadPage(at: 0)
        return Fixture(
            store: app.store,
            session: session,
            notebookID: notebook.id,
            pageIDs: snapshot.manifest.pageOrder
        )
    }

    private func makeStroke(layerID: UUID) -> StrokeRecord {
        StrokeRecord(
            id: UUID(),
            layerID: layerID,
            tool: StrokeTool(
                engine: "pencilkit",
                inkType: "com.apple.ink.pen",
                color: .black,
                width: 2,
                isHighlighter: false
            ),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            randomSeed: 1,
            points: [
                StrokePoint(
                    x: 10, y: 20, timeOffset: 0, width: 2, height: 2,
                    opacity: 1, force: 1, azimuth: 0, altitude: 1, secondaryScale: 1
                ),
                StrokePoint(
                    x: 30, y: 40, timeOffset: 0.01, width: 4, height: 4,
                    opacity: 1, force: 1, azimuth: 0, altitude: 1, secondaryScale: 1
                ),
            ]
        )
    }

    private func pagesDirectory(for notebookID: UUID, in store: LibraryStore) -> URL {
        store.notebookDirectoryURL(for: notebookID)
            .appendingPathComponent("pages", isDirectory: true)
    }

    private func pageFile(for pageID: UUID, notebookID: UUID, in store: LibraryStore) -> URL {
        pagesDirectory(for: notebookID, in: store)
            .appendingPathComponent(pageID.uuidString.lowercased() + ".page")
    }

    private func setWritable(_ writable: Bool, at directory: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: writable ? 0o755 : 0o555],
            ofItemAtPath: directory.path
        )
    }

    /// H1: a page whose save failed stays on screen, keeps its ink and is
    /// written by the retry before the next page is shown.
    func testFailedSaveBlocksNavigationAndIsRetried() async throws {
        let fixture = try await makeFixture(pageCount: 2)
        let session = fixture.session
        let firstID = try XCTUnwrap(fixture.pageIDs.first)
        let secondID = try XCTUnwrap(fixture.pageIDs.dropFirst().first)
        let page = try XCTUnwrap(session.page)
        let layerID = try XCTUnwrap(page.layers.first?.id)

        let stroke = makeStroke(layerID: layerID)
        session.strokesChanged([stroke], onPage: firstID)
        let edited = try XCTUnwrap(session.page)
        XCTAssertTrue(edited.strokes.contains { $0.id == stroke.id })

        let directory = pagesDirectory(for: fixture.notebookID, in: fixture.store)
        try setWritable(false, at: directory)
        await session.commitPendingSave()
        guard session.errorMessage != nil else {
            try? setWritable(true, at: directory)
            throw XCTSkip("The save did not fail; file permissions are not enforced here.")
        }

        // The flush failed, so the page must not change.
        await session.loadPage(at: 1)
        XCTAssertEqual(session.pageIndex, 0)
        XCTAssertEqual(session.page?.id, firstID)
        XCTAssertNotNil(session.errorMessage)

        // The retry writes the queued ink and only then moves on.
        try setWritable(true, at: directory)
        await session.loadPage(at: 1)
        XCTAssertEqual(session.pageIndex, 1)
        XCTAssertEqual(session.page?.id, secondID)
        XCTAssertNil(session.errorMessage)

        let saved = try await fixture.store.loadPage(firstID, in: fixture.notebookID)
        XCTAssertEqual(saved.strokes.map(\.id), [stroke.id])
        await session.flushPendingSave()
    }

    /// H3: the newest page turn wins even when the previous page's load takes
    /// the slower quarantine-recovery path.
    func testRapidPageTurnsEndOnTheNewestPage() async throws {
        let fixture = try await makeFixture(pageCount: 3)
        let session = fixture.session
        let middleID = fixture.pageIDs[1]
        let newestID = fixture.pageIDs[2]
        XCTAssertEqual(session.page?.id, fixture.pageIDs[0])

        // A corrupt file makes the middle page's load await quarantine recovery
        // after its first read; a newer turn can finish while that runs.
        let middleFile = pageFile(for: middleID, notebookID: fixture.notebookID, in: fixture.store)
        try Data().write(to: middleFile)

        let slower = Task { await session.loadPage(at: 1) }
        // Wait until the slower turn has captured its generation and is reading.
        for _ in 0..<200 {
            if session.isLoadingPage || session.pageIndex == 1 { break }
            await Task.yield()
        }
        XCTAssertTrue(session.isLoadingPage || session.pageIndex == 1)
        await session.loadPage(at: 2)
        await slower.value

        XCTAssertEqual(session.pageIndex, 2)
        XCTAssertEqual(session.page?.id, newestID)
        XCTAssertFalse(session.isLoadingPage)
        XCTAssertNil(session.loadError)
    }
}
