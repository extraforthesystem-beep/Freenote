import Foundation
import Testing
@testable import NoteCore

/// The store caches the manifest it last read or wrote, so `savePage` does not
/// decode `notebook.json` a second time only to rewrite it. These tests prove
/// that the cache never stands between a caller and the file.
@Suite("Manifest cache")
struct ManifestCacheTests {
    private func store(at root: URL) async throws -> LibraryStore {
        let store = LibraryStore(root: root)
        try await store.open()
        return store
    }

    /// The bytes a caller would see if the store read the file again.
    private func onDiskManifest(root: URL, notebookID: UUID) throws -> NotebookManifest {
        let file = notebookDirectory(root: root, notebookID: notebookID)
            .appendingPathComponent("notebook.json")
        return try ManifestCodec.decode(try Data(contentsOf: file), path: file.path)
    }

    private func onDiskTrashedManifest(root: URL, notebookID: UUID) throws -> NotebookManifest {
        let file = root.appendingPathComponent("trash")
            .appendingPathComponent(notebookID.diskName)
            .appendingPathComponent("notebook.json")
        return try ManifestCodec.decode(try Data(contentsOf: file), path: file.path)
    }

    /// The cached entry exists and is exactly what the file holds.
    private func expectCacheMatchesDisk(
        _ store: LibraryStore,
        root: URL,
        notebookID: UUID,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let disk = try onDiskManifest(root: root, notebookID: notebookID)
        let cached = await store.cachedManifest(notebookID)
        #expect(cached != nil, "a manifest write must leave the cache warm", sourceLocation: sourceLocation)
        #expect(cached == disk, "the cache disagrees with notebook.json", sourceLocation: sourceLocation)
    }

    // MARK: - Every mutating API

    @Test func everyManifestWriteKeepsTheCacheInStepWithTheDisk() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Cached")
        var rng = SplitMix64(seed: 0xCA_C4E)

        // The cache is consulted first, so warm it the way the editor does.
        _ = try await store.loadManifest(notebook.id)

        try await store.renameNotebook(notebook.id, title: "Renamed")
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        try await store.setCover("ocean", for: notebook.id)
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        try await store.setPageScrollMode(.vertical, for: notebook.id)
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        try await store.markOpened(notebook.id, at: Date(timeIntervalSince1970: 1_700_000_000))
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        let first = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        let second = try await store.addPage(
            to: notebook.id, at: 1, width: 612, height: 792, template: .blank
        )
        var loaded = try await store.loadPage(first.id, in: notebook.id)
        loaded.strokes = [randomStroke(&rng, layerID: loaded.layers[0].id, pointCount: 5)]
        try await store.savePage(loaded, in: notebook.id)
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        let copy = try await store.duplicatePage(first.id, in: notebook.id)
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        try await store.reorderPages(in: notebook.id, order: [second.id, copy.id, first.id])
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        try await store.deletePage(second.id, in: notebook.id)
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        let duplicate = try await store.duplicateNotebook(notebook.id)
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: duplicate.id)
        try await self.expectCacheMatchesDisk(store, root: root, notebookID: notebook.id)

        // What the cache serves is what the API publishes.
        let cached = try await store.loadManifest(notebook.id)
        #expect(cached.title == "Renamed")
        #expect(cached.coverName == "ocean")
        #expect(cached.pageScrollMode == .vertical)
        #expect(cached.pageOrder == [copy.id, first.id])
        #expect(duplicate.pageOrder.count == cached.pageOrder.count)
    }

    // MARK: - Trash and purge

    @Test func deletingRestoringAndPurgingNeverLeaveAStaleEntry() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Trashed")
        _ = try await store.loadManifest(notebook.id)

        try await store.deleteNotebook(notebook.id)

        // The library path must not answer from the cache now that it is gone.
        do {
            _ = try await store.loadManifest(notebook.id)
            Issue.record("a deleted notebook must not load from the library path")
        } catch let error as NoteCoreError {
            guard case .notFound = error else {
                Issue.record("expected notFound, got \(error)")
                throw error
            }
        }

        let trashed = try onDiskTrashedManifest(root: root, notebookID: notebook.id)
        #expect(trashed.deletedAt != nil)
        // The failed library read dropped the entry rather than answer for the
        // wrong file, and the listing reads the trashed manifest from disk.
        #expect(await store.cachedManifest(notebook.id) == nil)
        #expect(try await store.scanTrash().manifests == [trashed])

        try await store.restoreNotebook(notebook.id)
        let restored = try onDiskManifest(root: root, notebookID: notebook.id)
        #expect(restored.deletedAt == nil)
        #expect(try await store.loadManifest(notebook.id) == restored)
        #expect(await store.cachedManifest(notebook.id) == restored)

        try await store.deleteNotebook(notebook.id)
        try await store.purgeNotebook(notebook.id)
        #expect(await store.cachedManifest(notebook.id) == nil)
        #expect(try await store.scanTrash().manifests.isEmpty)
    }

    @Test func emptyingTheTrashDropsEveryCachedEntry() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Gone")
        try await store.deleteNotebook(notebook.id)
        #expect(await store.cachedManifest(notebook.id) != nil)

        #expect(try await store.emptyTrash() == 1)
        #expect(await store.cachedManifest(notebook.id) == nil)
    }

    @Test func purgingAnExpiredNotebookDropsItsEntry() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Expired")
        try await store.deleteNotebook(notebook.id)

        let manifestURL = root.appendingPathComponent("trash")
            .appendingPathComponent(notebook.id.diskName)
            .appendingPathComponent("notebook.json")
        var manifest = try ManifestCodec.decode(try Data(contentsOf: manifestURL))
        manifest.deletedAt = Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)
        try ManifestCodec.encode(manifest).write(to: manifestURL)

        #expect(try await store.purgeExpiredTrash(olderThan: 30 * 24 * 60 * 60) == [notebook.id])
        #expect(await store.cachedManifest(notebook.id) == nil)
    }

    // MARK: - Another store over the same root

    /// A long-lived store notices a manifest another instance wrote. The check
    /// is the file's size and modification date, so the window in which a
    /// long-lived store could serve the previous value is the time between the
    /// other writer's rename and the next read, which is no wider than the
    /// read-to-write window every save already has.
    @Test func aLongLivedStoreSeesAnotherStoresWrite() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await store(at: root)
        let notebook = try await first.createNotebook(title: "Shared")

        // Warm the first store's cache.
        #expect(try await first.loadManifest(notebook.id).title == "Shared")

        let second = try await store(at: root)
        try await second.renameNotebook(notebook.id, title: "Edited elsewhere")
        _ = try await second.addPage(to: notebook.id, at: 0, width: 612, height: 792, template: .blank)

        #expect(try await first.loadManifest(notebook.id).title == "Edited elsewhere")
        #expect(try await first.loadManifest(notebook.id).pageOrder.count == 1)

        // A fresh instance reads the same file, and so does a scan.
        let third = try await store(at: root)
        #expect(try await third.loadManifest(notebook.id).title == "Edited elsewhere")
        #expect(try await first.scanNotebooks().manifests.first?.title == "Edited elsewhere")

        // A write through the first store keeps the other store's page.
        let page = try #require(try await first.loadManifest(notebook.id).pageOrder.first)
        var loaded = try await first.loadPage(page, in: notebook.id)
        loaded.strokes = []
        try await first.savePage(loaded, in: notebook.id)
        #expect(try await second.loadManifest(notebook.id).pageOrder == [page])
    }

    /// An edit made straight to the file, outside the store, is seen too.
    @Test func aHandEditIsSeenByALongLivedStore() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Hand edited")
        _ = try await store.loadManifest(notebook.id)

        let file = notebookDirectory(root: root, notebookID: notebook.id)
            .appendingPathComponent("notebook.json")
        var manifest = try ManifestCodec.decode(try Data(contentsOf: file))
        manifest.title = "Typed in a text editor"
        try ManifestCodec.encode(manifest).write(to: file)

        #expect(try await store.loadManifest(notebook.id).title == "Typed in a text editor")

        // A file that no longer decodes is an error, not the cached value.
        try Data("not json at all".utf8).write(to: file)
        do {
            _ = try await store.loadManifest(notebook.id)
            Issue.record("a corrupt file must not load from the cache")
        } catch let error as NoteCoreError {
            guard case .corruptFile = error else {
                Issue.record("expected corruptFile, got \(error)")
                throw error
            }
        }
        #expect(await store.cachedManifest(notebook.id) == nil)
    }

    // MARK: - open() and restore

    @Test func openingTheLibraryDropsEverythingCached() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Reopened")
        try await store.markOpened(notebook.id)
        #expect(await store.cachedManifest(notebook.id) != nil)

        try await store.open()
        #expect(await store.cachedManifest(notebook.id) == nil)
        #expect(try await store.loadManifest(notebook.id).title == "Reopened")
    }

    @Test func aRestoredNotebookIsReadFromDisk() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Archived")
        let page = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )
        _ = try await store.loadManifest(notebook.id)

        let archive = root.appendingPathComponent("Backup.noteappbackup")
        _ = try await BackupArchive.create(from: store, at: archive)
        let restored = try await BackupArchive.restore(archiveAt: archive, into: store)

        let restoredID = try #require(restored.restoredNotebookIDs.first)
        let disk = try onDiskManifest(root: root, notebookID: restoredID)
        #expect(try await store.loadManifest(restoredID) == disk)
        #expect(disk.pageOrder == [page.id])
        let source = try onDiskManifest(root: root, notebookID: notebook.id)
        #expect(await store.cachedManifest(notebook.id) == source)
    }
}
