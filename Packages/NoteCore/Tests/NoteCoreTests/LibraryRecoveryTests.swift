import Foundation
import Testing
@testable import NoteCore

@Suite("Library recovery and durable writes")
struct LibraryRecoveryTests {
    private func store(at root: URL) async throws -> LibraryStore {
        let store = LibraryStore(root: root)
        try await store.open()
        return store
    }

    // MARK: - A damaged folders.json must not empty the library

    @Test func damagedFolderTreeIsQuarantinedAndTheNotebooksStayVisible() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Still here")

        let damaged = Data("not a folder tree".utf8)
        let treeFile = root.appendingPathComponent("folders.json")
        try damaged.write(to: treeFile)

        // The tolerant load degrades to an empty tree instead of throwing...
        let tree = try await store.loadFolderTreeRecovering()
        #expect(tree == FolderTree())

        // ...and the notebooks are read independently, exactly as reload() does.
        #expect(try await store.scanNotebooks().manifests.map(\.id) == [notebook.id])
        #expect(!FileManager.default.fileExists(atPath: treeFile.path))

        let notices = await store.takeRecoveryNotices()
        let notice = try #require(notices.first)
        #expect(notices.count == 1)
        #expect(notice.fileName == "folders.json")
        #expect(notice.quarantinedURL.deletingLastPathComponent().lastPathComponent == "quarantine")
        #expect(notice.quarantinedURL.lastPathComponent.hasSuffix("-folders.json"))
        #expect(try Data(contentsOf: notice.quarantinedURL) == damaged)

        // A notice is shown once, not on every reload.
        #expect(await store.takeRecoveryNotices().isEmpty)

        // The tree starts fresh and remains writable after the quarantine.
        let folder = try await store.createFolder(name: "Recovered", parentID: nil)
        #expect(try await store.loadFolderTree().folder(withID: folder.id)?.name == "Recovered")
    }

    @Test func aDamagedLibraryInfoIsReplacedInsteadOfBlockingLaunch() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryFile = root.appendingPathComponent("library.json")
        let damaged = Data("garbage, not json".utf8)
        try damaged.write(to: libraryFile)

        let store = LibraryStore(root: root)
        let info = try await store.open()
        #expect(info.schemaVersion == SchemaVersion.current)

        // The file on disk is a fresh, readable one and the device id survives.
        #expect(try LibraryInfoCodec.decode(Data(contentsOf: libraryFile)) == info)
        let reopened = try await LibraryStore(root: root).open()
        #expect(reopened == info)

        let notices = await store.takeRecoveryNotices()
        let notice = try #require(notices.first)
        #expect(notice.fileName == "library.json")
        #expect(notice.quarantinedURL.lastPathComponent.hasSuffix("-library.json"))
        #expect(try Data(contentsOf: notice.quarantinedURL) == damaged)
    }

    @Test func openStillThrowsOnARealIOFailure() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // A directory where the file belongs is a genuine I/O failure, not a
        // damaged document, so it must not be swallowed.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("library.json"),
            withIntermediateDirectories: true
        )

        let store = LibraryStore(root: root)
        do {
            _ = try await store.open()
            Issue.record("a directory in place of library.json must not open")
        } catch let error as NoteCoreError {
            guard case .ioFailure = error else {
                Issue.record("expected ioFailure, got \(error)")
                return
            }
        }
    }

    // MARK: - Tolerant folder-tree decoding

    @Test func aSingleMalformedIDDoesNotDiscardTheWholeTree() throws {
        let folderID = UUID()
        let notebookID = UUID()
        let json = """
        {
          "schemaVersion": \(SchemaVersion.current),
          "folders": [
            { "id": "\(folderID.uuidString)", "name": "Inbox" }
          ],
          "notebookFolder": {
            "\(notebookID.uuidString)": "\(folderID.uuidString)",
            "not-a-uuid": "\(folderID.uuidString)",
            "\(UUID().uuidString)": "not-a-uuid"
          },
          "tags": {
            "\(notebookID.uuidString)": ["physics"],
            "not-a-uuid": ["dropped"]
          },
          "favourites": ["\(notebookID.uuidString)", "not-a-uuid"]
        }
        """

        let tree = try FolderTreeCodec.decode(Data(json.utf8))
        #expect(tree.folders.map(\.id) == [folderID])
        #expect(tree.notebookFolder == [notebookID: folderID])
        #expect(tree.tags == [notebookID: ["physics"]])
        #expect(tree.favourites == [notebookID])
    }

    // MARK: - Atomic and durable writes

    @Test func writtenDocumentsRoundTripAndLeaveNoTemporaryFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await store(at: root)
        let notebook = try await store.createNotebook(title: "Durable")
        let page = try await store.addPage(
            to: notebook.id, at: 0, width: 612, height: 792, template: .blank
        )
        let folder = try await store.createFolder(name: "Atomic", parentID: nil)

        // Rewriting existing documents exercises the replace path, not just the
        // create path.
        try await store.renameNotebook(notebook.id, title: "Durable II")
        try await store.renameFolder(folder.id, name: "Atomic II")

        #expect(try await store.loadManifest(notebook.id).title == "Durable II")
        #expect(try await store.loadPage(page.id, in: notebook.id) == page)
        #expect(try await store.loadFolderTree().folder(withID: folder.id)?.name == "Atomic II")

        let directories = [
            root,
            notebookDirectory(root: root, notebookID: notebook.id),
            pagesDirectory(root: root, notebookID: notebook.id),
        ]
        for directory in directories {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(
                !names.contains { $0.hasPrefix(".tmp-") },
                "\(directory.lastPathComponent) left a temporary file behind"
            )
        }
    }
}
