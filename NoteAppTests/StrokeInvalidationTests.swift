import NoteCore
import Observation
@testable import NoteApp
import XCTest

/// The editor chrome reads `currentPageID`, `activeLayer` and `manifest` so it
/// does not rebuild for every stroke. This pins that: a normal stroke change
/// must not invalidate any of them, while `page` itself must.
@MainActor
final class StrokeInvalidationTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeInvalidationTests-\(UUID().uuidString)", isDirectory: true)
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
        let notebook = try await app.store.createNotebook(title: "Invalidation tests")
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

    /// `withObservationTracking`'s `onChange` is `@Sendable`, so the flag it
    /// sets has to be safe to touch from any thread.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// Tracks `read`, applies one stroke change, waits for the save, and says
    /// whether the tracked value was invalidated.
    private func invalidated(
        byAddingStrokeTo session: NotebookSession,
        layerID: UUID,
        read: @escaping @MainActor () -> Void
    ) async -> Bool {
        let fired = Flag()
        withObservationTracking {
            read()
        } onChange: {
            fired.set()
        }
        session.strokesChanged([makeStroke(layerID: layerID)])
        await session.commitPendingSave()
        return fired.isSet
    }

    func testAStrokeDoesNotInvalidateTheEditorChrome() async throws {
        let session = try await makeSession()
        let layerID = try XCTUnwrap(session.page?.layers.first?.id)

        var fired: [String] = []
        if await invalidated(byAddingStrokeTo: session, layerID: layerID, read: {
            _ = session.currentPageID
        }) {
            fired.append("currentPageID")
        }
        if await invalidated(byAddingStrokeTo: session, layerID: layerID, read: {
            _ = session.activeLayer
        }) {
            fired.append("activeLayer")
        }
        if await invalidated(byAddingStrokeTo: session, layerID: layerID, read: {
            _ = session.manifest
        }) {
            fired.append("manifest")
        }

        XCTAssertEqual(
            fired,
            [],
            "A stroke invalidated editor chrome that is supposed to be stroke-independent: \(fired)"
        )
    }

    /// The control: the tracked page must change, or the test above proves
    /// nothing about observation.
    func testAStrokeDoesInvalidateThePage() async throws {
        let session = try await makeSession()
        let layerID = try XCTUnwrap(session.page?.layers.first?.id)
        let fired = await invalidated(byAddingStrokeTo: session, layerID: layerID) {
            _ = session.page
        }
        XCTAssertTrue(fired, "A stroke did not invalidate session.page")
    }
}
