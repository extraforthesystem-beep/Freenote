import CryptoKit
import Foundation

/// The library on disk: notebooks, pages, assets and the folder tree.
///
/// Every method reads what it needs from the files and writes results back to them;
/// the store keeps no state that could not be rebuilt by scanning the library again.
/// Each write goes to a temporary file in the target directory and is then moved
/// into place, so a crash leaves either the old file or the new one.
public actor LibraryStore {
    /// The result of loading a notebook, with page files and `pageOrder` reconciled.
    ///
    /// Never silently drops anything: a page file that `pageOrder` does not list is
    /// reported as an orphan and appended to the returned manifest, and an id in
    /// `pageOrder` with no file is reported as missing and left in place.
    public struct NotebookSnapshot: Sendable, Hashable, Codable {
        public var manifest: NotebookManifest
        public var orphanPageIDs: [UUID]
        public var missingPageIDs: [UUID]

        public init(
            manifest: NotebookManifest,
            orphanPageIDs: [UUID] = [],
            missingPageIDs: [UUID] = []
        ) {
            self.manifest = manifest
            self.orphanPageIDs = orphanPageIDs
            self.missingPageIDs = missingPageIDs
        }
    }

    public let root: URL

    private nonisolated let layout: LibraryLayout
    private let fileManager = FileManager.default

    public init(root: URL) {
        self.root = root
        self.layout = LibraryLayout(root: root)
    }

    // MARK: - Library

    /// Creates the layout if it is missing and returns the library info, writing a
    /// new `deviceID` on the first run.
    @discardableResult
    public func open() throws -> LibraryInfo {
        try createDirectory(layout.root)
        try createDirectory(layout.notebooksDirectory)
        try createDirectory(layout.trashDirectory)
        try createDirectory(layout.cacheDirectory)

        let file = layout.libraryFile
        if fileManager.fileExists(atPath: file.path) {
            return try LibraryInfoCodec.decode(try readData(file), path: file.path)
        }
        let info = LibraryInfo(deviceID: UUID())
        try writeDocument(info, to: file)
        return info
    }

    // MARK: - Notebooks

    public func createNotebook(title: String) throws -> NotebookManifest {
        try createDirectory(layout.notebooksDirectory)
        try createDirectory(layout.trashDirectory)

        let now = Date()
        let manifest = NotebookManifest(id: UUID(), title: title, createdAt: now, updatedAt: now)
        try createDirectory(layout.notebookDirectory(manifest.id))
        try createDirectory(layout.pagesDirectory(manifest.id))
        try createDirectory(layout.assetsDirectory(manifest.id))
        try writeDocument(manifest, to: layout.manifestFile(manifest.id))
        return manifest
    }

    public func listNotebooks() throws -> [NotebookManifest] {
        var manifests: [NotebookManifest] = []
        for url in try contents(of: layout.notebooksDirectory) where isDirectory(url) {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            manifests.append(try loadManifest(id))
        }
        return manifests.sorted { $0.id.diskName < $1.id.diskName }
    }

    public func loadManifest(_ notebookID: UUID) throws -> NotebookManifest {
        let file = layout.manifestFile(notebookID)
        return try ManifestCodec.decode(try readData(file), path: file.path)
    }

    /// Loads the manifest and reconciles its `pageOrder` with the page files on disk.
    /// A load never rewrites the manifest.
    public func loadNotebook(_ notebookID: UUID) throws -> NotebookSnapshot {
        var manifest = try loadManifest(notebookID)
        let fileIDs = try pageFileIDs(in: notebookID)
        let onDisk = Set(fileIDs)
        let listed = Set(manifest.pageOrder)

        let orphanPageIDs = fileIDs.filter { !listed.contains($0) }
        let missingPageIDs = manifest.pageOrder.filter { !onDisk.contains($0) }
        manifest.pageOrder.append(contentsOf: orphanPageIDs)

        return NotebookSnapshot(
            manifest: manifest,
            orphanPageIDs: orphanPageIDs,
            missingPageIDs: missingPageIDs
        )
    }

    public func renameNotebook(_ notebookID: UUID, title: String) throws {
        var manifest = try loadManifest(notebookID)
        manifest.title = title
        manifest.updatedAt = Date()
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
    }

    /// Sets the cover style name, or clears it to show the first page instead.
    public func setCover(_ coverName: String?, for notebookID: UUID) throws {
        var manifest = try loadManifest(notebookID)
        manifest.coverName = coverName
        manifest.updatedAt = Date()
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
    }

    /// Moves the notebook's folder, unchanged, to `trash/`.
    ///
    /// The folder tree is left alone, so a restore puts the notebook back where it was.
    public func deleteNotebook(_ notebookID: UUID) throws {
        let source = layout.notebookDirectory(notebookID)
        guard fileManager.fileExists(atPath: source.path) else {
            throw NoteCoreError.notFound(path: source.path)
        }
        let destination = layout.trashedNotebookDirectory(notebookID)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw NoteCoreError.invalidInput("trash already contains notebook \(notebookID.diskName)")
        }
        try createDirectory(layout.trashDirectory)
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw NoteCoreError.ioFailure("move notebook to trash: \(error)")
        }
    }

    /// Moves a trashed notebook's folder back, unchanged.
    public func restoreNotebook(_ notebookID: UUID) throws {
        let source = layout.trashedNotebookDirectory(notebookID)
        guard fileManager.fileExists(atPath: source.path) else {
            throw NoteCoreError.notFound(path: source.path)
        }
        let destination = layout.notebookDirectory(notebookID)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw NoteCoreError.invalidInput("notebook \(notebookID.diskName) is already in the library")
        }
        try createDirectory(layout.notebooksDirectory)
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw NoteCoreError.ioFailure("restore notebook from trash: \(error)")
        }
    }

    public func listTrash() throws -> [NotebookManifest] {
        var manifests: [NotebookManifest] = []
        for url in try contents(of: layout.trashDirectory) where isDirectory(url) {
            guard UUID(uuidString: url.lastPathComponent) != nil else { continue }
            let file = url.appendingPathComponent("notebook.json")
            manifests.append(try ManifestCodec.decode(try readData(file), path: file.path))
        }
        return manifests.sorted { $0.id.diskName < $1.id.diskName }
    }

    public func purgeNotebook(_ notebookID: UUID) throws {
        let directory = layout.trashedNotebookDirectory(notebookID)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw NoteCoreError.notFound(path: directory.path)
        }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw NoteCoreError.ioFailure("purge notebook: \(error)")
        }
    }

    // MARK: - Pages

    /// Adds a page and returns it. The page file is written first and
    /// `notebook.json` second, so a crash in between leaves a recoverable orphan
    /// rather than a manifest entry with no page.
    public func addPage(
        to notebookID: UUID,
        at index: Int,
        width: Double,
        height: Double,
        template: PageTemplate
    ) throws -> Page {
        var manifest = try loadManifest(notebookID)
        let page = Page(width: width, height: height, template: template)

        try writePageFile(page, in: notebookID)

        let position = min(max(0, index), manifest.pageOrder.count)
        manifest.pageOrder.insert(page.id, at: position)
        manifest.updatedAt = Date()
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
        return page
    }

    public func loadPage(_ pageID: UUID, in notebookID: UUID) throws -> Page {
        let file = layout.pageFile(pageID, in: notebookID)
        return try PageCodec.decode(try readData(file), path: file.path)
    }

    /// Writes the page file first and the manifest second. A page id that the
    /// manifest does not know about is appended to `pageOrder`.
    public func savePage(_ page: Page, in notebookID: UUID) throws {
        var manifest = try loadManifest(notebookID)
        try writePageFile(page, in: notebookID)
        if !manifest.pageOrder.contains(page.id) {
            manifest.pageOrder.append(page.id)
        }
        manifest.updatedAt = Date()
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
    }

    /// Removes the page from `notebook.json` first, then deletes the page file.
    public func deletePage(_ pageID: UUID, in notebookID: UUID) throws {
        var manifest = try loadManifest(notebookID)
        manifest.pageOrder.removeAll { $0 == pageID }
        manifest.updatedAt = Date()
        try writeDocument(manifest, to: layout.manifestFile(notebookID))

        let file = layout.pageFile(pageID, in: notebookID)
        guard fileManager.fileExists(atPath: file.path) else { return }
        do {
            try fileManager.removeItem(at: file)
        } catch {
            throw NoteCoreError.ioFailure("delete page: \(error)")
        }
    }

    public func reorderPages(in notebookID: UUID, order: [UUID]) throws {
        var manifest = try loadManifest(notebookID)
        guard order.count == manifest.pageOrder.count, Set(order) == Set(manifest.pageOrder) else {
            throw NoteCoreError.invalidInput(
                "reorderPages must list exactly the pages already in notebook \(notebookID.diskName)"
            )
        }
        manifest.pageOrder = order
        manifest.updatedAt = Date()
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
    }

    /// Copies a page, giving the copy, every layer, stroke and element a new id, and
    /// places it directly after the original.
    public func duplicatePage(_ pageID: UUID, in notebookID: UUID) throws -> Page {
        var manifest = try loadManifest(notebookID)
        let original = try loadPage(pageID, in: notebookID)

        var layerIDs: [UUID: UUID] = [:]

        var layers: [Page.Layer] = []
        for layer in original.layers {
            layers.append(
                Page.Layer(
                    id: Self.freshLayerID(layer.id, in: &layerIDs),
                    name: layer.name,
                    isVisible: layer.isVisible,
                    isLocked: layer.isLocked
                )
            )
        }

        var strokes: [StrokeRecord] = []
        for stroke in original.strokes {
            var fresh = stroke
            fresh.id = UUID()
            fresh.layerID = Self.freshLayerID(stroke.layerID, in: &layerIDs)
            strokes.append(fresh)
        }

        var elements: [PageElement] = []
        for element in original.elements {
            var fresh = element
            fresh.id = UUID()
            fresh.layerID = Self.freshLayerID(element.layerID, in: &layerIDs)
            elements.append(fresh)
        }

        var copy = original
        copy.id = UUID()
        copy.layers = layers
        copy.strokes = strokes
        copy.elements = elements
        // The original's deleted ids refer to strokes that do not exist in the copy,
        // so the copy starts with an empty tombstone list.
        copy.deletedStrokeIDs = []

        try writePageFile(copy, in: notebookID)

        let position = (manifest.pageOrder.firstIndex(of: pageID) ?? manifest.pageOrder.count - 1) + 1
        manifest.pageOrder.insert(copy.id, at: min(max(0, position), manifest.pageOrder.count))
        manifest.updatedAt = Date()
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
        return copy
    }

    // MARK: - Assets

    /// Stores bytes under their SHA-256 name. The same bytes stored twice produce
    /// one file and return the same name.
    public func addAsset(
        _ data: Data,
        fileExtension: String,
        to notebookID: UUID
    ) throws -> String {
        let name = Self.hexString(SHA256.hash(data: data)) + Self.normalizedExtension(fileExtension)
        let file = layout.assetsDirectory(notebookID).appendingPathComponent(name)
        guard !fileManager.fileExists(atPath: file.path) else { return name }
        try writeAtomically(data, to: file)
        return name
    }

    public nonisolated func assetURL(named name: String, in notebookID: UUID) -> URL {
        layout.assetsDirectory(notebookID).appendingPathComponent(name)
    }

    /// The folder holding a notebook's immutable binary assets.
    public nonisolated func assetsDirectoryURL(for notebookID: UUID) -> URL {
        layout.assetsDirectory(notebookID)
    }

    // MARK: - Folder tree

    public func loadFolderTree() throws -> FolderTree {
        let file = layout.folderTreeFile
        guard fileManager.fileExists(atPath: file.path) else { return FolderTree() }
        return try FolderTreeCodec.decode(try readData(file), path: file.path)
    }

    public func saveFolderTree(_ tree: FolderTree) throws {
        try writeDocument(tree, to: layout.folderTreeFile)
    }

    public func createFolder(name: String, parentID: UUID?) throws -> Folder {
        var tree = try loadFolderTree()
        if let parentID, tree.folder(withID: parentID) == nil {
            throw NoteCoreError.notFound(path: "folder \(parentID.diskName)")
        }
        let folder = Folder(id: UUID(), name: name, parentID: parentID)
        tree.folders.append(folder)
        try saveFolderTree(tree)
        return folder
    }

    public func renameFolder(_ folderID: UUID, name: String) throws {
        var tree = try loadFolderTree()
        guard let index = tree.folders.firstIndex(where: { $0.id == folderID }) else {
            throw NoteCoreError.notFound(path: "folder \(folderID.diskName)")
        }
        tree.folders[index].name = name
        try saveFolderTree(tree)
    }

    public func moveFolder(_ folderID: UUID, to parentID: UUID?) throws {
        var tree = try loadFolderTree()
        guard let index = tree.folders.firstIndex(where: { $0.id == folderID }) else {
            throw NoteCoreError.notFound(path: "folder \(folderID.diskName)")
        }
        if let parentID {
            guard tree.folder(withID: parentID) != nil else {
                throw NoteCoreError.notFound(path: "folder \(parentID.diskName)")
            }
            var ancestor: UUID? = parentID
            while let current = ancestor {
                if current == folderID {
                    throw NoteCoreError.invalidInput("cannot move a folder into itself or its descendants")
                }
                ancestor = tree.folder(withID: current)?.parentID
            }
        }
        tree.folders[index].parentID = parentID
        try saveFolderTree(tree)
    }

    /// Removes a folder, moving its child folders and notebooks to its parent.
    public func deleteFolder(_ folderID: UUID) throws {
        var tree = try loadFolderTree()
        guard let folder = tree.folder(withID: folderID) else {
            throw NoteCoreError.notFound(path: "folder \(folderID.diskName)")
        }
        for index in tree.folders.indices where tree.folders[index].parentID == folderID {
            tree.folders[index].parentID = folder.parentID
        }
        for (notebookID, parent) in tree.notebookFolder where parent == folderID {
            if let grandparent = folder.parentID {
                tree.notebookFolder[notebookID] = grandparent
            } else {
                tree.notebookFolder.removeValue(forKey: notebookID)
            }
        }
        tree.folders.removeAll { $0.id == folderID }
        try saveFolderTree(tree)
    }

    public func setFolder(_ folderID: UUID?, forNotebook notebookID: UUID) throws {
        var tree = try loadFolderTree()
        if let folderID {
            guard tree.folder(withID: folderID) != nil else {
                throw NoteCoreError.notFound(path: "folder \(folderID.diskName)")
            }
            tree.notebookFolder[notebookID] = folderID
        } else {
            tree.notebookFolder.removeValue(forKey: notebookID)
        }
        try saveFolderTree(tree)
    }

    public func setTags(_ tags: [String], forNotebook notebookID: UUID) throws {
        var tree = try loadFolderTree()
        if tags.isEmpty {
            tree.tags.removeValue(forKey: notebookID)
        } else {
            tree.tags[notebookID] = tags
        }
        try saveFolderTree(tree)
    }

    @discardableResult
    public func toggleFavourite(_ notebookID: UUID) throws -> Bool {
        var tree = try loadFolderTree()
        let isFavourite: Bool
        if tree.favourites.contains(notebookID) {
            tree.favourites.remove(notebookID)
            isFavourite = false
        } else {
            tree.favourites.insert(notebookID)
            isFavourite = true
        }
        try saveFolderTree(tree)
        return isFavourite
    }

    // MARK: - File helpers

    private func createDirectory(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw NoteCoreError.ioFailure("create \(url.path): \(error)")
        }
    }

    private func contents(of directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        do {
            return try fileManager
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw NoteCoreError.ioFailure("list \(directory.path): \(error)")
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func readData(_ url: URL) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else {
            throw NoteCoreError.notFound(path: url.path)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw NoteCoreError.ioFailure("read \(url.path): \(error)")
        }
    }

    /// A temporary file in the target directory, moved into place by the system.
    private func writeAtomically(_ data: Data, to url: URL) throws {
        try createDirectory(url.deletingLastPathComponent())
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw NoteCoreError.ioFailure("write \(url.path): \(error)")
        }
    }

    private func writeDocument<T: Encodable>(_ value: T, to url: URL) throws {
        try writeAtomically(try JSONDocument.encode(value, path: url.path), to: url)
    }

    private func writePageFile(_ page: Page, in notebookID: UUID) throws {
        try writeAtomically(
            try PageCodec.encode(page),
            to: layout.pageFile(page.id, in: notebookID)
        )
    }

    private func pageFileIDs(in notebookID: UUID) throws -> [UUID] {
        try contents(of: layout.pagesDirectory(notebookID)).compactMap { url in
            guard url.pathExtension == "page" else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
        .sorted { $0.diskName < $1.diskName }
    }

    /// Returns a stable new id for a source id, allocating one on first use.
    private static func freshLayerID(_ id: UUID, in map: inout [UUID: UUID]) -> UUID {
        if let existing = map[id] { return existing }
        let fresh = UUID()
        map[id] = fresh
        return fresh
    }

    private static func hexString(_ digest: SHA256.Digest) -> String {        digest.map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }
        .joined()
    }

    private static func normalizedExtension(_ fileExtension: String) -> String {
        var trimmed = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix(".") { trimmed.removeFirst() }
        let allowed = trimmed.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return allowed.isEmpty ? "" : "." + allowed
    }
}
