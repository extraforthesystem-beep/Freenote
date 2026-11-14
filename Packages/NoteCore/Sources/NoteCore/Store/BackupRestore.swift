import Foundation

extension BackupArchive {
    /// Puts an archive's notebooks back into a library.
    ///
    /// Every file is checked against `manifest.sha256` before anything is
    /// written. Each notebook is copied into the library's cache first, its
    /// manifest is rewritten there, and every page is hashed and decoded; only
    /// then is the folder moved into `notebooks/`. A notebook whose id is still
    /// in the library (or its trash) is restored under a new id, so an existing
    /// notebook is never overwritten.
    public static func restore(
        archiveAt url: URL,
        into store: LibraryStore,
        progress: ProgressHandler? = nil
    ) async throws -> RestoreSummary {
        let verified = try verifiedFiles(in: url, progress: progress)
        let expectedHashes = Dictionary(
            uniqueKeysWithValues: verified.hashes.map { ($0.path, $0.hash) }
        )
        let fileManager = FileManager.default
        let layout = LibraryLayout(root: store.root)
        let archivedNotebooks = url.appendingPathComponent("notebooks", isDirectory: true)
        var archivedTree: FolderTree?
        if let data = try? Data(contentsOf: url.appendingPathComponent("folders.json")) {
            archivedTree = try? FolderTreeCodec.decode(data, path: "folders.json")
        }
        let currentTree = (try? await store.loadFolderTree()) ?? FolderTree()
        var tree = currentTree
        var didChangeTree = false

        var summary = RestoreSummary()
        let archivedFolders = try directories(in: archivedNotebooks)
        for (index, folder) in archivedFolders.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            progress?(Progress(
                step: .restoringNotebooks,
                done: index + 1,
                total: archivedFolders.count
            ))
            let staging = layout.cacheDirectory.appendingPathComponent(
                "restore-\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? fileManager.removeItem(at: staging) }

            do {
                try fileManager.createDirectory(
                    at: layout.cacheDirectory,
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: folder, to: staging)
            } catch {
                throw BackupError.ioFailure("could not stage \(folder.lastPathComponent): \(error)")
            }

            guard let sourceID = UUID(uuidString: folder.lastPathComponent) else { continue }
            let manifestFile = staging.appendingPathComponent("notebook.json")
            let storedManifest = try? ManifestCodec.decode(
                Data(contentsOf: manifestFile),
                path: manifestFile.path
            )

            // Prove the copy byte for byte before anything in it is changed.
            let copied = try verifyCopy(
                of: folder.lastPathComponent,
                in: staging,
                expectedHashes: expectedHashes
            )
            summary.pageCount += copied.pageCount
            summary.byteCount += copied.byteCount

            let isTaken = await store.containsNotebook(storedManifest?.id ?? sourceID)
            let destinationID = isTaken ? UUID() : (storedManifest?.id ?? sourceID)

            if let storedManifest {
                var manifest = storedManifest
                let needsRewrite = destinationID != storedManifest.id || manifest.deletedAt != nil
                if needsRewrite {
                    manifest.id = destinationID
                    manifest.deletedAt = nil
                    if destinationID != storedManifest.id {
                        manifest.title += " (Restored)"
                    }
                    try write(manifest, to: manifestFile)
                }
            } else if isTaken {
                // Rewriting the id needs a readable manifest; without one the old
                // folder cannot safely stay under an id the library already uses.
                summary.unreadableNotebookCount += 1
                continue
            }

            let destination = layout.notebookDirectory(destinationID)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            do {
                try fileManager.createDirectory(
                    at: layout.notebooksDirectory,
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: staging, to: destination)
            } catch {
                throw BackupError.ioFailure("could not restore \(folder.lastPathComponent): \(error)")
            }
            // The manifest was written here, not through the store, so any cache
            // entry for the id has to go.
            await store.forgetCachedManifest(destinationID)

            guard storedManifest != nil else {
                summary.unreadableNotebookCount += 1
                continue
            }
            summary.restoredNotebookIDs.append(destinationID)
            if destinationID != sourceID {
                summary.renamedNotebookIDs.append(destinationID)
            }

            // Tags and the folder are part of the tree, not of the notebook, so
            // they come from the archive's folders.json. A missing folder is
            // recreated with its archived id, parents included, so a restored
            // notebook lands where it was.
            if let archivedTree {
                if let tags = archivedTree.tags[sourceID], !tags.isEmpty {
                    tree.tags[destinationID] = tags
                    didChangeTree = true
                }
                if let folderID = archivedTree.notebookFolder[sourceID] {
                    restoreFolderPath(folderID, from: archivedTree, into: &tree)
                    tree.notebookFolder[destinationID] = folderID
                    didChangeTree = true
                }
            }
        }
        if didChangeTree {
            try await store.saveFolderTree(tree)
        }
        return summary
    }

    /// Adds the archived folder and any of its ancestors the library does not
    /// have yet. A folder that already exists keeps its current name and place.
    private static func restoreFolderPath(
        _ folderID: UUID,
        from archived: FolderTree,
        into tree: inout FolderTree
    ) {
        var missing: [Folder] = []
        var current: UUID? = folderID
        while let id = current,
              tree.folder(withID: id) == nil,
              let folder = archived.folder(withID: id) {
            missing.append(folder)
            current = folder.parentID
        }
        for folder in missing.reversed() {
            tree.folders.append(folder)
        }
    }

    /// Re-hashes every staged file against the archive's manifest and decodes
    /// every page, so a bad copy is caught before it reaches the library.
    private static func verifyCopy(
        of folderName: String,
        in staging: URL,
        expectedHashes: [String: String]
    ) throws -> (pageCount: Int, byteCount: Int) {
        var pageCount = 0
        var byteCount = 0
        for file in try regularFiles(in: staging) {
            let path = relativePath(of: file, in: staging)
            let archivePath = "notebooks/\(folderName)/\(path)"
            guard let data = try? Data(contentsOf: file) else {
                throw BackupError.verificationFailed(path: archivePath)
            }
            guard let expected = expectedHashes[archivePath], sha256Hex(data) == expected else {
                throw BackupError.verificationFailed(path: archivePath)
            }
            byteCount += data.count
            guard file.pathExtension == "page" else { continue }
            let page = try PageCodec.decode(data, path: archivePath)
            guard page.id == UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                throw BackupError.verificationFailed(path: archivePath)
            }
            pageCount += 1
        }
        return (pageCount, byteCount)
    }
}
