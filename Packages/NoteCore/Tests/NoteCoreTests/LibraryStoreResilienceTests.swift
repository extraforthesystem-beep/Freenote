import Foundation
import Testing
@testable import NoteCore

@Suite("Library resilience, trash ageing and duplication")
struct LibraryStoreResilienceTests {
    private func store(at root: URL) async throws -> LibraryStore {
        let store = LibraryStore(root: root)
        try await store.open()
        return store
    }

    // MARK: - A broken manifest must not hide the library

    @Test func corruptManifestIsSkippedAndCounted() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)

        let healthy = try await store.createNotebook(title: "Healthy")
        let broken = try await store.createNotebook(title: "Broken")
        try Data("not json at all".utf8).write(
            to: notebookDirectory(root: root, notebookID: broken.id)
                .appendingPathComponent("notebook.json")
        )

        let listing = try await store.scanNotebooks()
        #expect(listing.manifests.map(\.id) == [healthy.id])
        #expect(listing.unreadableIDs == [broken.id])
        #expect(listing.unreadableCount == 1)

        // The old entry point keeps working and simply omits the unreadable notebook.
        #expect(try await store.listNotebooks().map(\.id) == [healthy.id])
    }

    @Test func corruptTrashedManifestIsSkippedAndCounted() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)

        let healthy = try await store.createNotebook(title: "Healthy")
        let broken = try await store.createNotebook(title: "Broken")
        try await store.deleteNotebook(healthy.id)
        try await store.deleteNotebook(broken.id)
        try Data("{".utf8).write(
            to: root.appendingPathComponent("trash")
                .appendingPathComponent(broken.id.diskName)
                .appendingPathComponent("notebook.json")
        )

        let listing = try await store.scanTrash()
        #expect(listing.manifests.map(\.id) == [healthy.id])
        #expect(listing.unreadableCount == 1)
    }

    // MARK: - Metadata edits do not reorder the library

    @Test func renamingAndChangingTheCoverKeepUpdatedAt() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Original")

        try await store.renameNotebook(notebook.id, title: "Renamed")
        var current = try await store.loadManifest(notebook.id)
        #expect(current.title == "Renamed")
        #expect(current.updatedAt == notebook.updatedAt)

        try await store.setCover("ocean", for: notebook.id)
        current = try await store.loadManifest(notebook.id)
        #expect(current.coverName == "ocean")
        #expect(current.updatedAt == notebook.updatedAt)

        // Editing content still bumps the date.
        _ = try await store.addPage(
            to: notebook.id,
            at: 0,
            width: 612,
            height: 792,
            template: .blank
        )
        #expect(try await store.loadManifest(notebook.id).updatedAt > notebook.updatedAt)
    }

    // MARK: - Trash ageing

    /// Manifests written before `deletedAt` existed must still decode, and a
    /// notebook in the library must not grow the field.
    @Test func deletionDateIsOptionalOnDisk() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = """
        {
          "schemaVersion": 1,
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "pageOrder": [],
          "createdAt": "\(ISODate.string(from: date))",
          "updatedAt": "\(ISODate.string(from: date))"
        }
        """
        let decoded = try ManifestCodec.decode(Data(legacy.utf8))
        #expect(decoded.deletedAt == nil)

        let encoded = String(decoding: try ManifestCodec.encode(decoded), as: UTF8.self)
        #expect(!encoded.contains("deletedAt"))
    }

    @Test func trashingStampsADateAndRestoringClearsIt() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Stamped")

        try await store.deleteNotebook(notebook.id)
        let trashed = try #require(try await store.scanTrash().manifests.first)
        #expect(trashed.deletedAt != nil)

        try await store.restoreNotebook(notebook.id)
        #expect(try await store.loadManifest(notebook.id).deletedAt == nil)
    }

    @Test func purgeExpiredTrashKeepsRecentNotebooks() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)

        let old = try await store.createNotebook(title: "Old")
        let recent = try await store.createNotebook(title: "Recent")
        try await store.deleteNotebook(old.id)
        try await store.deleteNotebook(recent.id)

        // Backdate one deletion by rewriting its trashed manifest.
        let oldManifestPath = root.appendingPathComponent("trash")
            .appendingPathComponent(old.id.diskName)
            .appendingPathComponent("notebook.json")
        var manifest = try ManifestCodec.decode(try Data(contentsOf: oldManifestPath))
        manifest.deletedAt = Date(timeIntervalSinceNow: -31 * 24 * 60 * 60)
        try ManifestCodec.encode(manifest).write(to: oldManifestPath)

        let purged = try await store.purgeExpiredTrash(olderThan: 30 * 24 * 60 * 60)
        #expect(purged == [old.id])
        #expect(try await store.scanTrash().manifests.map(\.id) == [recent.id])
    }

    @Test func aTrashedNotebookWithoutADateAgesFromItsFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "No stamp")
        try await store.deleteNotebook(notebook.id)

        let directory = root.appendingPathComponent("trash")
            .appendingPathComponent(notebook.id.diskName)
        let manifestURL = directory.appendingPathComponent("notebook.json")
        var manifest = try ManifestCodec.decode(try Data(contentsOf: manifestURL))
        manifest.deletedAt = nil
        try ManifestCodec.encode(manifest).write(to: manifestURL)
        // Age the folder itself, the way a trash filled by an older build looks.
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)],
            ofItemAtPath: directory.path
        )

        let purged = try await store.purgeExpiredTrash(olderThan: 30 * 24 * 60 * 60)
        #expect(purged == [notebook.id])
        #expect(try await store.listTrash().isEmpty)
    }

    @Test func emptyTrashRemovesEveryNotebook() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        for title in ["One", "Two", "Three"] {
            let notebook = try await store.createNotebook(title: title)
            try await store.deleteNotebook(notebook.id)
        }

        #expect(try await store.emptyTrash() == 3)
        #expect(try await store.listTrash().isEmpty)
    }

    // MARK: - Duplication

    @Test func duplicatingANotebookCopiesPagesAndAssets() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let original = try await store.createNotebook(title: "Source")
        try await store.setCover("ocean", for: original.id)

        var rng = SplitMix64(seed: 0xD0D0_1234)
        let layerID = UUID()
        for index in 0..<2 {
            let page = try await store.addPage(
                to: original.id,
                at: index,
                width: 612,
                height: 792,
                template: randomTemplate(&rng)
            )
            var loaded = try await store.loadPage(page.id, in: original.id)
            loaded.layers = [Page.Layer(id: layerID, name: "Ink")]
            loaded.strokes = [randomStroke(&rng, layerID: layerID)]
            try await store.savePage(loaded, in: original.id)
        }
        let assetName = try await store.addAsset(
            Data("asset bytes".utf8),
            fileExtension: "png",
            to: original.id
        )

        let copy = try await store.duplicateNotebook(original.id)

        #expect(copy.id != original.id)
        #expect(copy.title == "Source Copy")
        #expect(copy.coverName == "ocean")
        #expect(copy.pageOrder.count == 2)
        #expect(Set(copy.pageOrder).isDisjoint(with: Set((try await store.loadManifest(original.id)).pageOrder)))

        // The copied page keeps its content but gets a new id.
        let copiedFirst = try await store.loadPage(copy.pageOrder[0], in: copy.id)
        #expect(copiedFirst.strokes.count == 1)
        #expect(try Data(contentsOf: store.assetURL(named: assetName, in: copy.id))
            == Data("asset bytes".utf8))

        let snapshot = try await store.loadNotebook(copy.id)
        #expect(snapshot.orphanPageIDs.isEmpty)
        #expect(snapshot.missingPageIDs.isEmpty)
        #expect(try await store.listNotebooks().count == 2)
    }
}
