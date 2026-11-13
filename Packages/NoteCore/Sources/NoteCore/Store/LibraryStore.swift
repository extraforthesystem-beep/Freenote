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

    /// What a scan of one directory of notebooks found.
    ///
    /// A single unreadable `notebook.json` is skipped instead of failing the whole
    /// scan, so the rest of the library stays usable. `unreadableCount` lets the
    /// caller tell the user that something on disk needs attention.
    public struct Listing: Sendable, Hashable {
        public var manifests: [NotebookManifest]
        public var unreadableIDs: [UUID]

        public init(manifests: [NotebookManifest] = [], unreadableIDs: [UUID] = []) {
            self.manifests = manifests
            self.unreadableIDs = unreadableIDs
        }

        public var unreadableCount: Int { unreadableIDs.count }
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
        let directory = layout.notebookDirectory(manifest.id)
        do {
            try createDirectory(directory)
            try createDirectory(layout.pagesDirectory(manifest.id))
            try createDirectory(layout.assetsDirectory(manifest.id))
            try writeDocument(manifest, to: layout.manifestFile(manifest.id))
            return manifest
        } catch {
            // A half-created folder would list as an unreadable notebook, so remove it.
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    /// Every readable notebook manifest.
    ///
    /// A notebook whose manifest cannot be decoded is skipped, not propagated: one
    /// corrupt file must not take the whole library away. Use `scanNotebooks()` to
    /// learn how many were skipped.
    public func listNotebooks() throws -> [NotebookManifest] {
        try scanNotebooks().manifests
    }

    /// Every notebook manifest that could be read, plus the ids that could not.
    public func scanNotebooks() throws -> Listing {
        try scan(directory: layout.notebooksDirectory)
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

    /// Changes the title only. Metadata edits do not touch `updatedAt`, so they
    /// cannot reshuffle a list sorted by date modified.
    public func renameNotebook(_ notebookID: UUID, title: String) throws {
        var manifest = try loadManifest(notebookID)
        manifest.title = title
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
    }

    /// Sets the cover style name, or clears it to show the first page instead.
    /// Like `renameNotebook`, this leaves `updatedAt` alone.
    public func setCover(_ coverName: String?, for notebookID: UUID) throws {
        var manifest = try loadManifest(notebookID)
        manifest.coverName = coverName
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
    }

    /// Sets the notebook's scroll direction, or clears it to follow the app
    /// default. Like `setCover`, this leaves `updatedAt` alone.
    public func setPageScrollMode(_ mode: PageScrollMode?, for notebookID: UUID) throws {
        var manifest = try loadManifest(notebookID)
        manifest.pageScrollMode = mode
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
    }

    /// Records that the notebook was opened. Kept apart from `updatedAt`, so
    /// opening a notebook does not reorder a grid sorted by date modified.
    public func markOpened(_ notebookID: UUID, at date: Date = Date()) throws {
        var manifest = try loadManifest(notebookID)
        manifest.lastOpenedAt = date
        try writeDocument(manifest, to: layout.manifestFile(notebookID))
    }

    /// Moves the notebook's folder, unchanged, to `trash/`, stamping the manifest
    /// with the deletion date used by the 30-day purge.
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
        markDeleted(notebookID, at: Date())
    }

    /// Records the deletion date inside the trashed notebook. A failure here only
    /// loses the purge deadline, so it must not fail the delete itself.
    private func markDeleted(_ notebookID: UUID, at date: Date) {
        let file = layout.trashedNotebookDirectory(notebookID)
            .appendingPathComponent("notebook.json")
        guard var manifest = try? ManifestCodec.decode(try readData(file), path: file.path) else {
            return
        }
        manifest.deletedAt = date
        try? writeDocument(manifest, to: file)
    }

    /// Moves a trashed notebook's folder back, unchanged, clearing the deletion date.
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
        clearDeleted(notebookID)
    }

    private func clearDeleted(_ notebookID: UUID) {
        let file = layout.manifestFile(notebookID)
        guard var manifest = try? ManifestCodec.decode(try readData(file), path: file.path),
              manifest.deletedAt != nil
        else { return }
        manifest.deletedAt = nil
        try? writeDocument(manifest, to: file)
    }

    public func listTrash() throws -> [NotebookManifest] {
        try scanTrash().manifests
    }

    /// Every trashed manifest that could be read, plus the ids that could not.
    public func scanTrash() throws -> Listing {
        try scan(directory: layout.trashDirectory)
    }

    /// Deletes trashed notebooks whose deletion date is older than `age`.
    ///
    /// A notebook with no recorded date falls back to the folder's creation date,
    /// so a trash filled by an older build still ages out.
    @discardableResult
    public func purgeExpiredTrash(olderThan age: TimeInterval, now: Date = Date()) throws -> [UUID] {
        var purged: [UUID] = []
        for url in try contents(of: layout.trashDirectory) where isDirectory(url) {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            let deletedAt = try? loadTrashedManifest(id).deletedAt
            let date = deletedAt ?? creationDate(of: url) ?? now
            guard now.timeIntervalSince(date) > age else { continue }
            do {
                try fileManager.removeItem(at: url)
                purged.append(id)
            } catch {
                throw NoteCoreError.ioFailure("purge expired notebook: \(error)")
            }
        }
        return purged
    }

    /// Removes everything in the trash.
    @discardableResult
    public func emptyTrash() throws -> Int {
        var removed = 0
        for url in try contents(of: layout.trashDirectory) where isDirectory(url) {
            do {
                try fileManager.removeItem(at: url)
                removed += 1
            } catch {
                throw NoteCoreError.ioFailure("empty trash: \(error)")
            }
        }
        return removed
    }

    private func loadTrashedManifest(_ notebookID: UUID) throws -> NotebookManifest {
        let file = layout.trashedNotebookDirectory(notebookID)
            .appendingPathComponent("notebook.json")
        return try ManifestCodec.decode(try readData(file), path: file.path)
    }

    private func creationDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    /// Copies a notebook, giving the copy and every page a new id.
    ///
    /// Asset files are content-addressed, so they are copied as they are and the
    /// element references inside the copied pages stay valid.
    public func duplicateNotebook(_ notebookID: UUID, title: String? = nil) throws -> NotebookManifest {
        let snapshot = try loadNotebook(notebookID)
        var copy = try createNotebook(title: title ?? "\(snapshot.manifest.title) Copy")
        copy.coverName = snapshot.manifest.coverName
        copy.pageOrder = []

        do {
            for pageID in snapshot.manifest.pageOrder {
                guard var page = try? loadPage(pageID, in: notebookID) else { continue }
                page.id = UUID()
                try writePageFile(page, in: copy.id)
                copy.pageOrder.append(page.id)
            }

            let sourceAssets = layout.assetsDirectory(notebookID)
            for url in try contents(of: sourceAssets) where !isDirectory(url) {
                let destination = layout.assetsDirectory(copy.id).appendingPathComponent(url.lastPathComponent)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                do {
                    try createDirectory(destination.deletingLastPathComponent())
                    try fileManager.copyItem(at: url, to: destination)
                } catch {
                    throw NoteCoreError.ioFailure("copy asset \(url.lastPathComponent): \(error)")
                }
            }

            copy.updatedAt = Date()
            try writeDocument(copy, to: layout.manifestFile(copy.id))
            return copy
        } catch {
            // A half-copied notebook would list as a broken duplicate.
            try? fileManager.removeItem(at: layout.notebookDirectory(copy.id))
            throw error
        }
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

    /// The notebook's private folder, used for sidecar metadata such as audio
    /// clip records.
    public nonisolated func notebookDirectoryURL(for notebookID: UUID) -> URL {
        layout.notebookDirectory(notebookID)
    }

    /// The library's cache folder, used for derived files such as covers.
    public nonisolated var cacheDirectoryURL: URL {
        layout.cacheDirectory
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

    public func setFolderAppearance(
        _ folderID: UUID,
        colorName: String?,
        iconName: String?
    ) throws {
        var tree = try loadFolderTree()
        guard let index = tree.folders.firstIndex(where: { $0.id == folderID }) else {
            throw NoteCoreError.notFound(path: "folder \(folderID.diskName)")
        }
        tree.folders[index].colorName = colorName
        tree.folders[index].iconName = iconName
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

    /// Reads every `notebooks/<id>/notebook.json` under `directory`, keeping the
    /// readable ones and counting the rest. Only a failure to list the directory
    /// itself is thrown.
    private func scan(directory: URL) throws -> Listing {
        var manifests: [NotebookManifest] = []
        var unreadable: [UUID] = []
        for url in try contents(of: directory) where isDirectory(url) {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            let file = url.appendingPathComponent("notebook.json")
            do {
                manifests.append(try ManifestCodec.decode(try readData(file), path: file.path))
            } catch {
                unreadable.append(id)
            }
        }
        return Listing(
            manifests: manifests.sorted { $0.id.diskName < $1.id.diskName },
            unreadableIDs: unreadable
        )
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
