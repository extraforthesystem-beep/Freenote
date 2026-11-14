import Foundation
import Testing
@testable import NoteCore

/// The progress each long backup operation reports, so the sheet can show a
/// count instead of an indeterminate spinner.
@Suite("Backup progress reporting")
struct BackupArchiveProgressTests {
    /// Collects the handler's reports; the handler is `@Sendable` and runs off
    /// the caller's actor.
    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [BackupArchive.Progress] = []

        func record(_ progress: BackupArchive.Progress) {
            lock.lock()
            items.append(progress)
            lock.unlock()
        }

        var all: [BackupArchive.Progress] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }

        func last(_ step: BackupArchive.Progress.Step) -> BackupArchive.Progress? {
            all.last { $0.step == step }
        }
    }

    private func makeSourceLibrary(at root: URL) async throws -> LibraryStore {
        let store = LibraryStore(root: root)
        try await store.open()
        for index in 0..<2 {
            let notebook = try await store.createNotebook(title: "Notebook \(index)")
            _ = try await store.addPage(
                to: notebook.id,
                at: 0,
                width: 612,
                height: 792,
                template: .blank
            )
        }
        return store
    }

    @Test func createAndVerifyReportEveryItem() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await makeSourceLibrary(at: root.appendingPathComponent("Source"))
        let archive = root.appendingPathComponent("Backups/Progress.noteappbackup")

        let createLog = ProgressLog()
        _ = try await BackupArchive.create(
            from: store,
            at: archive,
            progress: { createLog.record($0) }
        )

        let copied = try #require(createLog.last(.copyingNotebooks))
        #expect(copied.done == 2)
        #expect(copied.total == 2)
        #expect(copied.fraction == 1)

        let hashed = try #require(createLog.last(.checkingFiles))
        #expect(hashed.total > 0)
        #expect(hashed.done == hashed.total)
        #expect(hashed.fraction == 1)

        let verifyLog = ProgressLog()
        let verified = try await BackupArchive.verify(
            archiveAt: archive,
            progress: { verifyLog.record($0) }
        )
        let checked = try #require(verifyLog.last(.checkingFiles))
        #expect(checked.done == verified.fileCount)
        #expect(checked.total == verified.fileCount)
        // One report per file, in order.
        #expect(verifyLog.all.map(\.done) == Array(1...verified.fileCount))
    }

    @Test func restoreReportsEveryNotebook() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await makeSourceLibrary(at: root.appendingPathComponent("Source"))
        let archive = root.appendingPathComponent("Backups/Restore.noteappbackup")
        _ = try await BackupArchive.create(from: store, at: archive)

        let destination = LibraryStore(root: root.appendingPathComponent("Restored"))
        try await destination.open()
        let log = ProgressLog()
        let summary = try await BackupArchive.restore(
            archiveAt: archive,
            into: destination,
            progress: { log.record($0) }
        )

        let restored = try #require(log.last(.restoringNotebooks))
        #expect(restored.total == summary.restoredNotebookIDs.count)
        #expect(restored.done == restored.total)
    }
}
