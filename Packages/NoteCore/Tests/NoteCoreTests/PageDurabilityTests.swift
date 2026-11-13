import Foundation
import Testing
@testable import NoteCore

@Suite("Page durability: checksums and quarantine")
struct PageDurabilityTests {
    private func store(at root: URL) async throws -> LibraryStore {
        let store = LibraryStore(root: root)
        try await store.open()
        return store
    }

    /// A page with enough ink that its file is not empty after compression.
    private func inkedPage(
        in store: LibraryStore,
        notebookID: UUID
    ) async throws -> Page {
        let page = try await store.addPage(
            to: notebookID, at: 0, width: 612, height: 792, template: .blank
        )
        var loaded = try await store.loadPage(page.id, in: notebookID)
        var rng = SplitMix64(seed: 0xC0_FFEE)
        loaded.strokes = (0..<12).map { _ in
            randomStroke(&rng, layerID: loaded.layers[0].id, pointCount: 20)
        }
        loaded.elements = [randomElement(&rng, layerID: loaded.layers[0].id)]
        try await store.savePage(loaded, in: notebookID)
        return loaded
    }

    @Test func savingAPageRecordsItsChecksum() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Checksums")
        let page = try await inkedPage(in: store, notebookID: notebook.id)

        let file = pageFile(root: root, notebookID: notebook.id, pageID: page.id)
        let checksumFile = file.deletingPathExtension().appendingPathExtension("sha256")
        let recorded = try String(contentsOf: checksumFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(recorded == BackupArchive.sha256Hex(try Data(contentsOf: file)))

        // The public verifier agrees and re-records the same hash.
        #expect(try await store.verifyPageFile(page.id, in: notebook.id) == recorded)
    }

    @Test func verifyReportsAPageWhoseBytesChanged() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Tampered")
        let page = try await inkedPage(in: store, notebookID: notebook.id)

        // Swap in a different, perfectly decodable page. Only the hash can tell,
        // and a check reports it without rewriting the record.
        var other = page
        other.strokes = []
        other.elements = []
        try PageCodec.encode(other).write(
            to: pageFile(root: root, notebookID: notebook.id, pageID: page.id)
        )

        let checksumFile = pageFile(root: root, notebookID: notebook.id, pageID: page.id)
            .deletingPathExtension()
            .appendingPathExtension("sha256")
        let recorded = try String(contentsOf: checksumFile, encoding: .utf8)
        do {
            _ = try await store.verifyPageFile(page.id, in: notebook.id)
            Issue.record("a changed page must not verify")
        } catch let error as NoteCoreError {
            guard case .corruptFile = error else {
                Issue.record("expected corruptFile, got \(error)")
                return
            }
        }
        #expect(try String(contentsOf: checksumFile, encoding: .utf8) == recorded)

        // A page whose checksum is missing is not an error; the check records one.
        try? FileManager.default.removeItem(at: checksumFile)
        #expect(try await store.verifyPageFile(page.id, in: notebook.id).count == 64)
    }

    @Test func loadRejectsUndecodableBytes() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Broken")
        let page = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )
        try Data("not a page".utf8).write(
            to: pageFile(root: root, notebookID: notebook.id, pageID: page.id)
        )

        do {
            _ = try await store.loadPage(page.id, in: notebook.id)
            Issue.record("garbage bytes must not load")
        } catch let error as NoteCoreError {
            guard case .corruptFile = error else {
                Issue.record("expected corruptFile, got \(error)")
                return
            }
        }
    }

    @Test func aPageWrittenBeforeChecksumsStillLoads() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Legacy")
        let page = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )

        // Write the bytes without the sidecar a newer build would add.
        let file = pageFile(root: root, notebookID: notebook.id, pageID: page.id)
        try PageCodec.encode(page).write(to: file)
        try? FileManager.default.removeItem(
            at: file.deletingPathExtension().appendingPathExtension("sha256")
        )

        #expect(try await store.loadPage(page.id, in: notebook.id) == page)
    }

    @Test func quarantineKeepsTheDamagedBytesAndRemovesThePageFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Quarantine")
        let page = try await inkedPage(in: store, notebookID: notebook.id)

        let file = pageFile(root: root, notebookID: notebook.id, pageID: page.id)
        let damaged = Data("truncated bytes".utf8)
        try damaged.write(to: file)

        let moved = try await store.quarantinePage(page.id, in: notebook.id)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(moved.path.contains("corrupt"))
        #expect(try Data(contentsOf: moved) == damaged)
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved
            .deletingLastPathComponent().path).contains(moved.lastPathComponent))

        // The page is gone from the notebook, so the manifest reports it missing
        // instead of the whole notebook failing.
        let snapshot = try await store.loadNotebook(notebook.id)
        #expect(snapshot.missingPageIDs == [page.id])

        do {
            _ = try await store.loadPage(page.id, in: notebook.id)
            Issue.record("a quarantined page has no file to load")
        } catch let error as NoteCoreError {
            guard case .notFound = error else {
                Issue.record("expected notFound, got \(error)")
                return
            }
        }

        // A replacement written under the same id verifies and loads again.
        try await store.savePage(page, in: notebook.id)
        #expect(try await store.loadPage(page.id, in: notebook.id) == page)
    }
}
