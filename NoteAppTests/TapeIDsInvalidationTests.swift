import NoteCore
import Observation
@testable import NoteApp
import XCTest

/// Tape study chrome reads `session.tapeIDs` instead of `session.page`, so it
/// is not rebuilt for every stroke. This pins both halves: a stroke must not
/// invalidate `tapeIDs`, and adding a piece of tape must.
@MainActor
final class TapeIDsInvalidationTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapeIDsTests-\(UUID().uuidString)", isDirectory: true)
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
        let notebook = try await app.store.createNotebook(title: "Tape tests")
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

    private func observeTapeIDs(_ session: NotebookSession, _ flag: Flag) {
        withObservationTracking {
            _ = session.tapeIDs
        } onChange: {
            flag.set()
        }
    }

    func testAStrokeDoesNotInvalidateTapeIDs() async throws {
        let session = try await makeSession()
        let layerID = try XCTUnwrap(session.page?.layers.first?.id)

        let fired = Flag()
        observeTapeIDs(session, fired)
        session.strokesChanged([makeStroke(layerID: layerID)])
        await session.commitPendingSave()

        XCTAssertFalse(fired.isSet, "A stroke invalidated session.tapeIDs")
    }

    func testAddingTapeInvalidatesTapeIDs() async throws {
        let session = try await makeSession()
        XCTAssertEqual(session.tapeIDs, [])

        let fired = Flag()
        observeTapeIDs(session, fired)
        await session.insertTape(color: NotebookSession.tapeColors[0])

        XCTAssertTrue(fired.isSet, "Adding tape did not invalidate session.tapeIDs")
        let elementID = try XCTUnwrap(
            session.page?.elements.first {
                if case .tape = $0.content { return true }
                return false
            }?.id
        )
        XCTAssertEqual(session.tapeIDs, [elementID])

        await session.flushPendingSave()
    }
}
