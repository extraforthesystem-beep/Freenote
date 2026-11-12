import Foundation
import Testing
@testable import NoteCore

@Suite("Library layout and notebooks")
struct LibraryStoreNotebookTests {
    @Test func openCreatesTheLayoutOnce() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)

        let first = try await store.open()
        #expect(first.schemaVersion == SchemaVersion.current)

        let manager = FileManager.default
        let libraryFile = root.appendingPathComponent("library.json")
        #expect(manager.fileExists(atPath: libraryFile.path))
        #expect(manager.fileExists(atPath: root.appendingPathComponent("notebooks").path))
        #expect(manager.fileExists(atPath: root.appendingPathComponent("trash").path))
        #expect(manager.fileExists(atPath: root.appendingPathComponent("cache").path))

        // The device id survives a reopen, through this instance and a new one.
        let secondStore = LibraryStore(root: root)
        let second = try await secondStore.open()
        #expect(second == first)

        let third = try await store.open()
        #expect(third == first)
        #expect(first.deviceID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    @Test func createListRenameAndLoadNotebook() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()

        let notebook = try await store.createNotebook(title: "Physics")
        #expect(notebook.schemaVersion == SchemaVersion.current)
        #expect(notebook.pageOrder.isEmpty)

        let directory = notebookDirectory(root: root, notebookID: notebook.id)
        let manager = FileManager.default
        #expect(manager.fileExists(atPath: directory.appendingPathComponent("notebook.json").path))
        #expect(manager.fileExists(atPath: pagesDirectory(root: root, notebookID: notebook.id).path))
        #expect(manager.fileExists(atPath: assetsDirectory(root: root, notebookID: notebook.id).path))
        #expect(directory.lastPathComponent == notebook.id.uuidString.lowercased())

        let listed = try await store.listNotebooks()
        #expect(listed == [notebook])

        let loaded = try await store.loadManifest(notebook.id)
        #expect(loaded == notebook)

        try await store.renameNotebook(notebook.id, title: "Physics II")
        let renamed = try await store.loadManifest(notebook.id)
        #expect(renamed.title == "Physics II")
        #expect(renamed.updatedAt >= notebook.updatedAt)
        #expect(renamed.id == notebook.id)
        #expect(renamed.pageOrder == notebook.pageOrder)

        try await store.setCover("ocean", for: notebook.id)
        #expect(try await store.loadManifest(notebook.id).coverName == "ocean")
        try await store.setCover(nil, for: notebook.id)
        #expect(try await store.loadManifest(notebook.id).coverName == nil)
    }

    @Test func deletingAndRestoringANotebookKeepsEveryByte() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()

        var rng = SplitMix64(seed: 0xDE1E_7E01)
        let notebook = try await store.createNotebook(title: "To trash")
        let other = try await store.createNotebook(title: "Stays")

        let layerID = UUID()
        for index in 0..<3 {
            let page = try await store.addPage(
                to: notebook.id,
                at: index,
                width: 612,
                height: 792,
                template: randomTemplate(&rng)
            )
            var loaded = try await store.loadPage(page.id, in: notebook.id)
            loaded.layers = [Page.Layer(id: layerID, name: "Ink")]
            loaded.strokes = (0..<3).map { _ in randomStroke(&rng, layerID: layerID) }
            loaded.elements = [randomElement(&rng, layerID: layerID)]
            try await store.savePage(loaded, in: notebook.id)
        }
        let assetName = try await store.addAsset(Data("some pdf bytes".utf8), fileExtension: "pdf", to: notebook.id)

        let before = try captureDirectory(notebookDirectory(root: root, notebookID: notebook.id))
        #expect(before.count == 3 + 1 + 1) // notebook.json, 3 pages, 1 asset

        try await store.deleteNotebook(notebook.id)

        let manager = FileManager.default
        #expect(!manager.fileExists(atPath: notebookDirectory(root: root, notebookID: notebook.id).path))
        let trashed = root.appendingPathComponent("trash")
            .appendingPathComponent(notebook.id.uuidString.lowercased())
        #expect(manager.fileExists(atPath: trashed.path))

        let trashedContents = try captureDirectory(trashed)
        // The only byte that changes on the way to the trash is the deletion stamp
        // in notebook.json; every page and asset is untouched.
        let manifestPath = "notebook.json"
        let trashedManifest = try #require(trashedContents[manifestPath])
        let deletedManifest = try ManifestCodec.decode(
            trashedManifest,
            path: trashed.path + "/notebook.json"
        )
        #expect(deletedManifest.deletedAt != nil)
        #expect(trashedContents.filter { $0.key != manifestPath } == before.filter { $0.key != manifestPath })

        let remaining = try await store.listNotebooks()
        #expect(remaining.map(\.id) == [other.id])
        let trashList = try await store.listTrash()
        #expect(trashList.map(\.id) == [notebook.id])

        try await store.restoreNotebook(notebook.id)

        #expect(!manager.fileExists(atPath: trashed.path))
        let restoredContents = try captureDirectory(notebookDirectory(root: root, notebookID: notebook.id))
        #expect(restoredContents == before)

        let trashAfterRestore = try await store.listTrash()
        #expect(trashAfterRestore.isEmpty)
        let allNotebooks = try await store.listNotebooks()
        #expect(Set(allNotebooks.map(\.id)) == Set([notebook.id, other.id]))

        // The restored notebook is fully usable.
        let snapshot = try await store.loadNotebook(notebook.id)
        #expect(snapshot.orphanPageIDs.isEmpty)
        #expect(snapshot.missingPageIDs.isEmpty)
        #expect(snapshot.manifest.pageOrder.count == 3)

        let assetURL = store.assetURL(named: assetName, in: notebook.id)
        let assetBytes = try Data(contentsOf: assetURL)
        #expect(assetBytes == Data("some pdf bytes".utf8))
    }

    @Test func purgingRemovesTheTrashedFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Gone")
        try await store.deleteNotebook(notebook.id)

        let beforePurge = try await store.listTrash()
        #expect(beforePurge.count == 1)

        try await store.purgeNotebook(notebook.id)

        let trashed = root.appendingPathComponent("trash")
            .appendingPathComponent(notebook.id.uuidString.lowercased())
        #expect(!FileManager.default.fileExists(atPath: trashed.path))
        let afterPurge = try await store.listTrash()
        #expect(afterPurge.isEmpty)

        var threw = false
        do { try await store.purgeNotebook(notebook.id) } catch { threw = true }
        #expect(threw, "purging a notebook that is not in the trash must fail")
    }

    @Test func trashSurvivesAReloadFromDisk() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Trashed")
        try await store.deleteNotebook(notebook.id)

        // A brand new store over the same folder sees the same library: nothing
        // lives only in memory.
        let fresh = LibraryStore(root: root)
        try await fresh.open()
        let trashed = try await fresh.listTrash()
        #expect(trashed.map(\.id) == [notebook.id])
        let live = try await fresh.listNotebooks()
        #expect(live.isEmpty)
    }
}
