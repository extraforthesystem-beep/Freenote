import NoteCore
@testable import NoteApp
import XCTest

/// A cancelled page insert stops at a page boundary: the pages already written
/// stay in the notebook and on disk, and nothing is half-written.
@MainActor
final class PageInsertCancellationTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageInsertCancellationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        try await super.tearDown()
    }

    private func makeSession() async throws -> NotebookSession {
        // AppModel reaches a `VersionHistoryStore` without the test target
        // linking HistoryKit; its history sits beside the temporary library.
        let app = AppModel(root: fixtureRoot.appendingPathComponent("library", isDirectory: true))
        try await app.store.open()
        let notebook = try await app.store.createNotebook(title: "Insert tests")
        _ = try await app.store.addPage(
            to: notebook.id,
            at: Int.max,
            width: 600,
            height: 800,
            template: .blank
        )
        let snapshot = try await app.store.loadNotebook(notebook.id)
        let session = NotebookSession(store: app.store, snapshot: snapshot, history: app.history)
        await session.loadPage(at: 0)
        return session
    }

    /// Holds the insert task, so the progress callback can stop it at a page
    /// boundary. Waiting for a fixed delay instead would race the writes.
    private final class TaskBox {
        var task: Task<Int, any Error>?
    }

    private func makePages(_ count: Int) -> [Page] {
        (0..<count).map { _ in
            Page(id: UUID(), width: 600, height: 800, template: .blank)
        }
    }

    private func pageFileCount(for notebookID: UUID, in store: LibraryStore) -> Int {
        let pages = store.notebookDirectoryURL(for: notebookID)
            .appendingPathComponent("pages", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: pages.path)) ?? []
        return files.filter { $0.hasSuffix(".page") }.count
    }

    func testCancellingAnInsertStopsAtAPageBoundary() async throws {
        let session = try await makeSession()
        let store = session.store
        let notebookID = session.notebookID
        let existingOrder = session.manifest.pageOrder
        let pages = makePages(5)
        let cancelledAfter = 2

        let box = TaskBox()
        let task = Task { @MainActor in
            try await session.insertPages(pages, at: 0) { written, _ in
                // Written pages so far, counted from one.
                if written == cancelledAfter { box.task?.cancel() }
            }
        }
        box.task = task

        do {
            let inserted = try await task.value
            XCTFail("The cancelled insert returned \(inserted) instead of throwing")
        } catch is CancellationError {
            // A stop is not a failure.
        }

        let written = Array(pages.prefix(cancelledAfter))
        let unwritten = Array(pages.dropFirst(cancelledAfter))
        let writtenIDs = written.map(\.id)

        // The manifest holds exactly the pages written, in write order.
        XCTAssertEqual(
            session.manifest.pageOrder,
            existingOrder + writtenIDs,
            "The session's manifest does not match the pages written"
        )
        let manifest = try await store.loadManifest(notebookID)
        XCTAssertEqual(
            manifest.pageOrder,
            existingOrder + writtenIDs,
            "The manifest on disk does not match the pages written"
        )

        // Those pages are whole on disk and readable.
        for page in written {
            let saved = try await store.loadPage(page.id, in: notebookID)
            XCTAssertEqual(saved.id, page.id)
            XCTAssertEqual(saved.width, page.width)
            XCTAssertEqual(saved.height, page.height)
        }
        // The pages after the stop were never started.
        for page in unwritten {
            do {
                _ = try await store.loadPage(page.id, in: notebookID)
                XCTFail("Page \(page.id) was written after the cancel")
            } catch {
                // Expected: the file does not exist.
            }
        }
        XCTAssertEqual(pageFileCount(for: notebookID, in: store), existingOrder.count + cancelledAfter)
        XCTAssertNil(session.errorMessage, "A cancel set the failure banner")

        await session.flushPendingSave()
    }
}
