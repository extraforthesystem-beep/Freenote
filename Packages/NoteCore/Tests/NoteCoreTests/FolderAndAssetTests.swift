import Foundation
import Testing
@testable import NoteCore

@Suite("Folder tree")
struct FolderTreeStoreTests {
    @Test func createRenameMoveAndAssign() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Filed")

        let inbox = try await store.createFolder(name: "Inbox", parentID: nil)
        let child = try await store.createFolder(name: "Child", parentID: inbox.id)

        try await store.renameFolder(child.id, name: "Renamed")
        try await store.setFolder(child.id, forNotebook: notebook.id)
        try await store.setTags(["physics", "term 1"], forNotebook: notebook.id)
        let favourited = try await store.toggleFavourite(notebook.id)
        #expect(favourited)

        var tree = try await store.loadFolderTree()
        #expect(tree.schemaVersion == SchemaVersion.current)
        #expect(tree.folder(withID: child.id)?.name == "Renamed")
        #expect(tree.folder(withID: child.id)?.parentID == inbox.id)
        #expect(tree.notebookFolder[notebook.id] == child.id)
        #expect(tree.tags[notebook.id] == ["physics", "term 1"])
        #expect(tree.favourites == [notebook.id])

        // Moving to the root clears the parent.
        try await store.moveFolder(child.id, to: nil)
        tree = try await store.loadFolderTree()
        #expect(tree.folder(withID: child.id)?.parentID == nil)

        // Moving a folder into one of its own descendants is refused.
        try await store.moveFolder(child.id, to: inbox.id)
        let sibling = try await store.createFolder(name: "Sibling", parentID: child.id)
        var threw = false
        do { try await store.moveFolder(child.id, to: sibling.id) } catch { threw = true }
        #expect(threw, "moving a folder into its descendant must fail")

        let unchanged = try await store.loadFolderTree()
        #expect(unchanged.folder(withID: child.id)?.parentID == inbox.id)

        // Un-favouriting and clearing tags.
        let unfavourited = try await store.toggleFavourite(notebook.id)
        #expect(!unfavourited)
        try await store.setTags([], forNotebook: notebook.id)
        try await store.setFolder(nil, forNotebook: notebook.id)
        let cleared = try await store.loadFolderTree()
        #expect(cleared.favourites.isEmpty)
        #expect(cleared.tags[notebook.id] == nil)
        #expect(cleared.notebookFolder[notebook.id] == nil)
    }

    @Test func deletingAFolderLeavesNoDanglingReferences() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()

        let one = try await store.createNotebook(title: "One")
        let two = try await store.createNotebook(title: "Two")
        let a = try await store.createFolder(name: "A", parentID: nil)
        let b = try await store.createFolder(name: "B", parentID: a.id)
        let c = try await store.createFolder(name: "C", parentID: b.id)
        try await store.setFolder(b.id, forNotebook: one.id)
        try await store.setFolder(a.id, forNotebook: two.id)

        try await store.deleteFolder(a.id)

        let tree = try await store.loadFolderTree()
        let folderIDs = Set(tree.folders.map(\.id))
        #expect(!folderIDs.contains(a.id))
        #expect(
            tree.folders.allSatisfy { $0.parentID.map { folderIDs.contains($0) } ?? true },
            "a folder still points at a folder that no longer exists"
        )
        #expect(
            tree.notebookFolder.values.allSatisfy { folderIDs.contains($0) },
            "a notebook still points at a folder that no longer exists"
        )

        // Children of the deleted folder move up to where it was (the root).
        #expect(tree.folder(withID: b.id)?.parentID == nil)
        #expect(tree.folder(withID: c.id)?.parentID == b.id)
        #expect(
            tree.notebookFolder[one.id] == b.id,
            "a notebook in a surviving child folder stays there"
        )
        #expect(tree.notebookFolder[two.id] == nil, "a notebook in the deleted folder moves to its parent")
    }

    @Test func deletingAFolderMovesItsNotebooksAndChildFoldersToItsParent() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()

        let notebook = try await store.createNotebook(title: "Deep")
        let parent = try await store.createFolder(name: "Parent", parentID: nil)
        let middle = try await store.createFolder(name: "Middle", parentID: parent.id)
        let leaf = try await store.createFolder(name: "Leaf", parentID: middle.id)
        try await store.setFolder(middle.id, forNotebook: notebook.id)

        try await store.deleteFolder(middle.id)

        let tree = try await store.loadFolderTree()
        let folderIDs = Set(tree.folders.map(\.id))
        #expect(tree.folders.allSatisfy { $0.parentID.map { folderIDs.contains($0) } ?? true })
        #expect(tree.notebookFolder.values.allSatisfy { folderIDs.contains($0) })
        #expect(tree.folder(withID: leaf.id)?.parentID == parent.id)
        #expect(tree.notebookFolder[notebook.id] == parent.id)

        // And the tree round-trips from disk through a fresh store.
        let fresh = LibraryStore(root: root)
        try await fresh.open()
        let reloaded = try await fresh.loadFolderTree()
        #expect(reloaded == tree)
    }

    @Test func folderTreeIsWrittenAsPlainJSON() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let folder = try await store.createFolder(name: "Plain", parentID: nil)

        let url = root.appendingPathComponent("folders.json")
        let data = try Data(contentsOf: url)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\n"))
        #expect(text.contains(folder.id.uuidString))
        let decoded = try FolderTreeCodec.decode(data)
        #expect(decoded.folder(withID: folder.id)?.name == "Plain")
    }
}

@Suite("Assets")
struct AssetStoreTests {
    @Test func identicalBytesProduceOneContentAddressedFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Assets")

        var rng = SplitMix64(seed: 0xA55E_7001)
        var bytes = Data(count: 4_096)
        for index in 0..<bytes.count {
            bytes[index] = UInt8(truncatingIfNeeded: rng.next())
        }

        let first = try await store.addAsset(bytes, fileExtension: "pdf", to: notebook.id)
        let second = try await store.addAsset(bytes, fileExtension: "pdf", to: notebook.id)

        #expect(first == second)
        #expect(first.hasSuffix(".pdf"))
        #expect(first.count == 64 + 4, "the name is the hex digest plus the extension")

        let directory = assetsDirectory(root: root, notebookID: notebook.id)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names == [first])

        let url = store.assetURL(named: first, in: notebook.id)
        let stored = try Data(contentsOf: url)
        #expect(stored == bytes)
        #expect(url.lastPathComponent == first)

        // Different bytes, different name.
        var otherBytes = bytes
        otherBytes.append(0)
        let third = try await store.addAsset(otherBytes, fileExtension: "png", to: notebook.id)
        #expect(third != first)
        #expect(third.hasSuffix(".png"))
        let namesAfter = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(Set(namesAfter) == Set([first, third]))

        // Extension handling is forgiving about case and a leading dot.
        let fourth = try await store.addAsset(bytes, fileExtension: ".PDF", to: notebook.id)
        #expect(fourth == first)
    }
}
