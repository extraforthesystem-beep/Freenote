import Foundation
import Testing
@testable import NoteCore

@Suite("Pages through the store")
struct LibraryStorePageTests {
    @Test func addingAPageWritesThePageBeforeTheManifest() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Pages")

        let first = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )
        let second = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )

        let file = pageFile(root: root, notebookID: notebook.id, pageID: first.id)
        let onDisk = try PageCodec.decode(Data(contentsOf: file))
        #expect(onDisk == first)

        let manifest = try await store.loadManifest(notebook.id)
        #expect(manifest.pageOrder == [second.id, first.id])
        #expect(manifest.updatedAt >= notebook.updatedAt)
        #expect(first.layers.count == 1)
        #expect(second.layers.count == 1)
    }

    @Test func randomPageOperationsKeepOrderAndDiskInSync() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Random ops")
        var rng = SplitMix64(seed: 0x5EED_1234)

        for step in 0..<100 {
            let before = try await store.loadNotebook(notebook.id)
            let ids = before.manifest.pageOrder

            switch rng.int(in: 0...3) {
            case 0:
                _ = try await store.addPage(
                    to: notebook.id,
                    at: rng.int(in: 0...ids.count),
                    width: 612,
                    height: 792,
                    template: .blank
                )
            case 1:
                if let victim = ids.randomElement(using: &rng) {
                    try await store.deletePage(victim, in: notebook.id)
                }
            case 2:
                if ids.count > 1 {
                    var order = ids
                    order.shuffle(using: &rng)
                    try await store.reorderPages(in: notebook.id, order: order)
                }
            default:
                if let source = ids.randomElement(using: &rng) {
                    _ = try await store.duplicatePage(source, in: notebook.id)
                }
            }

            let after = try await store.loadNotebook(notebook.id)
            let files = try pageFileIDs(in: pagesDirectory(root: root, notebookID: notebook.id))

            #expect(Set(after.manifest.pageOrder) == files, "step \(step): order and files disagree")
            #expect(
                Set(after.manifest.pageOrder).count == after.manifest.pageOrder.count,
                "step \(step): pageOrder contains a duplicate"
            )
            #expect(after.orphanPageIDs.isEmpty, "step \(step): unexpected orphan")
            #expect(after.missingPageIDs.isEmpty, "step \(step): unexpected missing page")

            for pageID in after.manifest.pageOrder {
                _ = try await store.loadPage(pageID, in: notebook.id)
            }
        }
    }

    @Test func duplicatePageGivesTheCopyFreshIDs() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Duplicates")
        var rng = SplitMix64(seed: 0xD0_9C_A7E)

        let page = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )
        var loaded = try await store.loadPage(page.id, in: notebook.id)
        let layerID = loaded.layers[0].id
        loaded.strokes = (0..<25).map { _ in randomStroke(&rng, layerID: layerID) }
        loaded.elements = (0..<6).map { _ in randomElement(&rng, layerID: layerID) }
        loaded.deletedStrokeIDs = [randomUUID(&rng)]
        try await store.savePage(loaded, in: notebook.id)

        let copy = try await store.duplicatePage(page.id, in: notebook.id)

        #expect(copy.id != loaded.id)
        #expect(copy.strokes.count == loaded.strokes.count)
        #expect(copy.elements.count == loaded.elements.count)
        #expect(copy.layers.count == loaded.layers.count)

        let originalStrokeIDs = Set(loaded.strokes.map(\.id))
        let copyStrokeIDs = Set(copy.strokes.map(\.id))
        #expect(originalStrokeIDs.isDisjoint(with: copyStrokeIDs))
        #expect(originalStrokeIDs.count == loaded.strokes.count)

        let originalElementIDs = Set(loaded.elements.map(\.id))
        let copyElementIDs = Set(copy.elements.map(\.id))
        #expect(originalElementIDs.isDisjoint(with: copyElementIDs))

        // Everything except the ids is preserved.
        for (original, duplicate) in zip(loaded.strokes, copy.strokes) {
            var expected = original
            expected.id = duplicate.id
            expected.layerID = duplicate.layerID
            #expect(duplicate == expected)
        }
        for (original, duplicate) in zip(loaded.elements, copy.elements) {
            var expected = original
            expected.id = duplicate.id
            expected.layerID = duplicate.layerID
            #expect(duplicate == expected)
        }

        // The copy is on disk and sits directly after the original.
        let manifest = try await store.loadManifest(notebook.id)
        #expect(manifest.pageOrder == [loaded.id, copy.id])
        let copyOnDisk = try await store.loadPage(copy.id, in: notebook.id)
        #expect(copyOnDisk == copy)
        let originalOnDisk = try await store.loadPage(loaded.id, in: notebook.id)
        #expect(originalOnDisk == loaded)
    }

    @Test func savePageUpdatesTheManifestAndTheFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Save")
        var rng = SplitMix64(seed: 0x5A_7E_0001)

        let page = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )
        let beforeSave = try await store.loadManifest(notebook.id)

        var loaded = try await store.loadPage(page.id, in: notebook.id)
        loaded.strokes = [randomStroke(&rng, layerID: loaded.layers[0].id)]
        loaded.template = PageTemplate(
            kind: "grid", spacing: 20, lineColor: .black, paperColor: .white
        )
        try await store.savePage(loaded, in: notebook.id)

        let afterSave = try await store.loadManifest(notebook.id)
        #expect(afterSave.updatedAt >= beforeSave.updatedAt)
        #expect(afterSave.pageOrder == beforeSave.pageOrder)

        let reloaded = try await store.loadPage(page.id, in: notebook.id)
        #expect(reloaded == loaded)

        let file = pageFile(root: root, notebookID: notebook.id, pageID: page.id)
        let bytes = try Data(contentsOf: file)
        let expected = try PageCodec.encode(loaded)
        #expect(bytes == expected)
    }

    @Test func deletingAPageRemovesTheEntryAndThenTheFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Delete")
        let keep = try await store.addPage(to: notebook.id, at: 0, width: 100, height: 100, template: .blank)
        let drop = try await store.addPage(to: notebook.id, at: 1, width: 100, height: 100, template: .blank)

        try await store.deletePage(drop.id, in: notebook.id)

        let manifest = try await store.loadManifest(notebook.id)
        #expect(manifest.pageOrder == [keep.id])
        let file = pageFile(root: root, notebookID: notebook.id, pageID: drop.id)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // Deleting a page that is already gone is a no-op for the order.
        try await store.deletePage(drop.id, in: notebook.id)
        let afterSecondDelete = try await store.loadManifest(notebook.id)
        #expect(afterSecondDelete.pageOrder == [keep.id])
    }

    @Test func reorderingRejectsADifferentSetOfPages() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Reorder")
        let a = try await store.addPage(to: notebook.id, at: 0, width: 100, height: 100, template: .blank)
        let b = try await store.addPage(to: notebook.id, at: 1, width: 100, height: 100, template: .blank)

        var threw = false
        do { try await store.reorderPages(in: notebook.id, order: [a.id]) } catch { threw = true }
        #expect(threw, "reordering with a different set of pages must fail")

        threw = false
        do { try await store.reorderPages(in: notebook.id, order: [a.id, a.id]) } catch { threw = true }
        #expect(threw, "reordering with a duplicate page must fail")

        try await store.reorderPages(in: notebook.id, order: [b.id, a.id])
        let manifest = try await store.loadManifest(notebook.id)
        #expect(manifest.pageOrder == [b.id, a.id])
    }

    @Test func missingPageFilesAreReportedAndKept() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Missing")
        let first = try await store.addPage(to: notebook.id, at: 0, width: 100, height: 100, template: .blank)
        let second = try await store.addPage(to: notebook.id, at: 1, width: 100, height: 100, template: .blank)

        let manifestBefore = try Data(
            contentsOf: notebookDirectory(root: root, notebookID: notebook.id)
                .appendingPathComponent("notebook.json")
        )

        try FileManager.default.removeItem(
            at: pageFile(root: root, notebookID: notebook.id, pageID: first.id)
        )

        let snapshot = try await store.loadNotebook(notebook.id)
        #expect(snapshot.missingPageIDs == [first.id])
        #expect(snapshot.orphanPageIDs.isEmpty)
        #expect(snapshot.manifest.pageOrder == [first.id, second.id], "a missing page must stay in pageOrder")

        // A load never rewrites the manifest.
        let manifestAfter = try Data(
            contentsOf: notebookDirectory(root: root, notebookID: notebook.id)
                .appendingPathComponent("notebook.json")
        )
        #expect(manifestAfter == manifestBefore)
    }

    @Test func orphanPageFilesAreReportedAndAppendedForTheCaller() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Orphans")
        let first = try await store.addPage(to: notebook.id, at: 0, width: 100, height: 100, template: .blank)

        let manifestBefore = try Data(
            contentsOf: notebookDirectory(root: root, notebookID: notebook.id)
                .appendingPathComponent("notebook.json")
        )

        // Two extra, valid page files that the manifest does not know about.
        var rng = SplitMix64(seed: 0x0_2FA_0B)
        let orphanA = Page(id: randomUUID(&rng), width: 100, height: 100, template: .blank)
        let orphanB = Page(id: randomUUID(&rng), width: 100, height: 100, template: .blank)
        for orphan in [orphanB, orphanA] {
            let url = pageFile(root: root, notebookID: notebook.id, pageID: orphan.id)
            try PageCodec.encode(orphan).write(to: url)
        }

        let snapshot = try await store.loadNotebook(notebook.id)
        let expected = [orphanA.id, orphanB.id].sorted { $0.uuidString.lowercased() < $1.uuidString.lowercased() }
        #expect(snapshot.orphanPageIDs == expected, "orphans are reported sorted by id")
        #expect(snapshot.missingPageIDs.isEmpty)
        #expect(snapshot.manifest.pageOrder == [first.id] + expected)

        let manifestAfter = try Data(
            contentsOf: notebookDirectory(root: root, notebookID: notebook.id)
                .appendingPathComponent("notebook.json")
        )
        #expect(manifestAfter == manifestBefore)

        // The reported orphans really are loadable pages.
        let loadedOrphan = try await store.loadPage(expected[0], in: notebook.id)
        #expect(loadedOrphan.id == expected[0])
    }

    @Test func crashBetweenThePageWriteAndTheManifestLeavesARecoverableOrphan() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Crash")

        let manifestURL = notebookDirectory(root: root, notebookID: notebook.id)
            .appendingPathComponent("notebook.json")
        let manifestBefore = try Data(contentsOf: manifestURL)

        // Exactly what addPage does first, and nothing after it.
        let page = Page(id: UUID(), width: 612, height: 792, template: .blank)
        try PageCodec.encode(page).write(
            to: pageFile(root: root, notebookID: notebook.id, pageID: page.id)
        )

        let snapshot = try await store.loadNotebook(notebook.id)
        #expect(snapshot.orphanPageIDs == [page.id])
        #expect(snapshot.missingPageIDs.isEmpty)
        #expect(snapshot.manifest.pageOrder == [page.id])
        #expect(snapshot.manifest.title == notebook.title)

        let manifestAfter = try Data(contentsOf: manifestURL)
        #expect(manifestAfter == manifestBefore)

        let recovered = try await store.loadPage(page.id, in: notebook.id)
        #expect(recovered == page)
    }

    @Test func pagesFromASecondStoreOverTheSameFolderAreVisible() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Shared")
        let page = try await store.addPage(to: notebook.id, at: 0, width: 100, height: 100, template: .blank)

        let other = LibraryStore(root: root)
        try await other.open()
        let seen = try await other.loadPage(page.id, in: notebook.id)
        #expect(seen == page)
        let snapshot = try await other.loadNotebook(notebook.id)
        #expect(snapshot.manifest.pageOrder == [page.id])
    }
}
