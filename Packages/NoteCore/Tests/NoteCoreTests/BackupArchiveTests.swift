import Foundation
import Testing
@testable import NoteCore

@Suite("Backup archives: create, verify, restore")
struct BackupArchiveTests {
    struct SourceNotebook {
        var id: UUID
        var pageIDs: [UUID]
    }

    /// A library with two notebooks, ink, an attachment, a folder and tags.
    private func makeSourceLibrary(at root: URL) async throws -> (
        store: LibraryStore,
        folderID: UUID,
        notebooks: [SourceNotebook],
        assetName: String
    ) {
        let store = LibraryStore(root: root)
        try await store.open()
        let folder = try await store.createFolder(name: "Projects", parentID: nil)

        var rng = SplitMix64(seed: 0xBAC_C0DE)
        var notebooks: [SourceNotebook] = []

        for index in 0..<2 {
            let notebook = try await store.createNotebook(title: "Notebook \(index)")
            try await store.setFolder(folder.id, forNotebook: notebook.id)
            try await store.setTags(["work", "index-\(index)"], forNotebook: notebook.id)

            var pageIDs: [UUID] = []
            for pageIndex in 0..<(index + 1) {
                let page = try await store.addPage(
                    to: notebook.id, at: pageIndex, width: 612, height: 792, template: .blank
                )
                var loaded = try await store.loadPage(page.id, in: notebook.id)
                loaded.strokes = (0..<8).map { _ in
                    randomStroke(&rng, layerID: loaded.layers[0].id, pointCount: 16)
                }
                loaded.elements = [randomElement(&rng, layerID: loaded.layers[0].id)]
                try await store.savePage(loaded, in: notebook.id)
                pageIDs.append(page.id)
            }
            notebooks.append(SourceNotebook(id: notebook.id, pageIDs: pageIDs))
        }

        let assetName = try await store.addAsset(
            Data("attachment bytes".utf8),
            fileExtension: "txt",
            to: notebooks[0].id
        )
        return (store, folder.id, notebooks, assetName)
    }

    @Test func archiveRoundTripsIntoAnEmptyLibrary() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeSourceLibrary(at: root.appendingPathComponent("Source"))
        let archive = root.appendingPathComponent("Backups/First.noteappbackup")

        let created = try await BackupArchive.create(from: source.store, at: archive)
        #expect(created.manifest.notebookCount == 2)
        #expect(created.manifest.pageCount == 3)
        #expect(created.fileCount > 0)
        #expect(FileManager.default.fileExists(
            atPath: archive.appendingPathComponent("manifest.json").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: archive.appendingPathComponent("manifest.sha256").path
        ))

        let verified = try await BackupArchive.verify(archiveAt: archive)
        #expect(verified.manifest == created.manifest)

        let destination = LibraryStore(root: root.appendingPathComponent("Restored"))
        try await destination.open()
        let restored = try await BackupArchive.restore(archiveAt: archive, into: destination)
        #expect(restored.restoredNotebookIDs.count == 2)
        #expect(restored.renamedNotebookIDs.isEmpty)
        #expect(restored.pageCount == 3)
        #expect(restored.unreadableNotebookCount == 0)

        // The notebooks, their ids, their pages and the ink all came back.
        let listing = try await destination.scanNotebooks()
        #expect(Set(listing.manifests.map(\.id)) == Set(source.notebooks.map(\.id)))
        for notebook in source.notebooks {
            for pageID in notebook.pageIDs {
                let expected = try await source.store.loadPage(pageID, in: notebook.id)
                let actual = try await destination.loadPage(pageID, in: notebook.id)
                #expect(actual == expected)
            }
        }

        // The attachment came with the notebook, under its content hash.
        let asset = await destination.assetURL(named: source.assetName, in: source.notebooks[0].id)
        #expect(try Data(contentsOf: asset) == Data("attachment bytes".utf8))

        // Folder and tags are part of the tree, so they come from folders.json.
        let tree = try await destination.loadFolderTree()
        #expect(tree.folder(withID: source.folderID)?.name == "Projects")
        #expect(tree.notebookFolder[source.notebooks[0].id] == source.folderID)
        #expect(tree.tags[source.notebooks[1].id] == ["work", "index-1"])
    }

    @Test func verifyRefusesATamperedArchiveAndRestoreWritesNothing() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeSourceLibrary(at: root.appendingPathComponent("Source"))
        let archive = root.appendingPathComponent("Backups/Tampered.noteappbackup")
        try await BackupArchive.create(from: source.store, at: archive)

        let manifest = try String(
            contentsOf: archive.appendingPathComponent("manifest.sha256"),
            encoding: .utf8
        )
        let pageLine = try #require(
            manifest.split(separator: "\n").first { $0.contains("/pages/") }
        )
        let pagePath = String(pageLine.dropFirst(66))
        let pageFile = archive.appendingPathComponent(pagePath)
        let bytes = try Data(contentsOf: pageFile)
        try (bytes + Data([0x00])).write(to: pageFile)

        do {
            _ = try await BackupArchive.verify(archiveAt: archive)
            Issue.record("a changed file must fail verification")
        } catch let error as BackupError {
            guard case .verificationFailed = error else {
                Issue.record("expected verificationFailed, got \(error)")
                return
            }
        }

        let destination = LibraryStore(root: root.appendingPathComponent("Restored"))
        try await destination.open()
        do {
            _ = try await BackupArchive.restore(archiveAt: archive, into: destination)
            Issue.record("a tampered archive must not restore")
        } catch let error as BackupError {
            guard case .verificationFailed = error else {
                Issue.record("expected verificationFailed, got \(error)")
                return
            }
        }
        #expect(try await destination.scanNotebooks().manifests.isEmpty)
    }

    @Test func restoringIntoTheSameLibraryMakesCopiesAndKeepsTheOriginals() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeSourceLibrary(at: root.appendingPathComponent("Source"))
        let archive = root.appendingPathComponent("Backups/Same.noteappbackup")
        try await BackupArchive.create(from: source.store, at: archive)

        let restored = try await BackupArchive.restore(archiveAt: archive, into: source.store)

        #expect(restored.restoredNotebookIDs.count == 2)
        #expect(Set(restored.renamedNotebookIDs) == Set(restored.restoredNotebookIDs))

        // The originals are untouched, and the copies are separate notebooks.
        let listing = try await source.store.scanNotebooks()
        #expect(listing.manifests.count == 4)
        #expect(Set(listing.manifests.map(\.id)).isSuperset(of: source.notebooks.map(\.id)))
        for manifest in listing.manifests where restored.restoredNotebookIDs.contains(manifest.id) {
            #expect(manifest.title.hasSuffix(" (Restored)"))
        }
        let originalPage = try await source.store.loadPage(
            source.notebooks[0].pageIDs[0],
            in: source.notebooks[0].id
        )
        #expect(originalPage.id == source.notebooks[0].pageIDs[0])
    }

    @Test func creatingTwiceAtTheSamePathIsRefused() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeSourceLibrary(at: root.appendingPathComponent("Source"))
        let archive = root.appendingPathComponent("Backups/Once.noteappbackup")
        try await BackupArchive.create(from: source.store, at: archive)

        do {
            _ = try await BackupArchive.create(from: source.store, at: archive)
            Issue.record("an existing archive must not be replaced")
        } catch let error as BackupError {
            guard case .archiveExists = error else {
                Issue.record("expected archiveExists, got \(error)")
                return
            }
        }
    }

    @Test func summariesListNewestFirstAndSkipOtherFolders() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeSourceLibrary(at: root.appendingPathComponent("Source"))
        let directory = root.appendingPathComponent("Backups")
        try await BackupArchive.create(
            from: source.store,
            at: directory.appendingPathComponent("Old.noteappbackup"),
            now: Date(timeIntervalSince1970: 1_000)
        )
        try await BackupArchive.create(
            from: source.store,
            at: directory.appendingPathComponent("New.noteappbackup"),
            now: Date(timeIntervalSince1970: 2_000)
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("NotABackup.noteappbackup"),
            withIntermediateDirectories: true
        )

        let summaries = BackupArchive.summaries(in: directory)
        #expect(summaries.map(\.url.lastPathComponent) == [
            "New.noteappbackup", "Old.noteappbackup",
        ])
        #expect(summaries.allSatisfy { $0.manifest.format == BackupArchive.formatName })
    }
}
