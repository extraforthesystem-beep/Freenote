import Foundation

/// Persists one JSON file per text document under a caller-owned root directory.
///
/// Files are named `<lowercased-uuid>.json`. Writes are atomic, so a crash leaves
/// either the previous file or the complete new one. A file with a schema this
/// build does not support is refused instead of being partly decoded.
public actor TextDocumentStore {
    /// The directory that holds the document files.
    public nonisolated let root: URL

    private let fileManager: FileManager

    /// Creates a store rooted at `root`; the directory is created on first save.
    public init(root: URL) {
        self.root = root
        self.fileManager = .default
    }

    /// The file URL a document with `id` is stored at.
    public nonisolated func fileURL(for id: UUID) -> URL {
        root.appending(
            path: "\(id.uuidString.lowercased()).json",
            directoryHint: .notDirectory
        )
    }

    /// Writes `document` atomically and returns its file URL.
    ///
    /// Refuses to write a document with a schema this build does not support.
    @discardableResult
    public func save(_ document: TextDocument) throws -> URL {
        guard (1...TextDocument.currentSchemaVersion).contains(document.schemaVersion) else {
            throw TextDocError.unsupportedSchemaVersion(
                found: document.schemaVersion,
                supported: TextDocument.currentSchemaVersion
            )
        }
        try createRootIfNeeded()
        let file = fileURL(for: document.id)
        let data = try TextDocJSON.encode(document, path: file.path)
        do {
            try data.write(to: file, options: [.atomic])
        } catch {
            throw TextDocError.ioFailure("could not write \(file.path): \(error)")
        }
        return file
    }

    /// Loads the document with `id`, refusing a file with an unsupported schema.
    public func load(id: UUID) throws -> TextDocument {
        try load(fileURL: fileURL(for: id))
    }

    /// Loads one document file, refusing a file with an unsupported schema.
    private func load(fileURL file: URL) throws -> TextDocument {
        guard fileManager.fileExists(atPath: file.path) else {
            throw TextDocError.notFound(path: file.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw TextDocError.ioFailure("could not read \(file.path): \(error)")
        }
        return try TextDocJSON.decodeDocument(from: data, path: file.path)
    }

    /// All documents in the store, most recently updated first.
    ///
    /// Files whose names are not document UUIDs are ignored. A corrupt or
    /// future-schema document makes the call throw rather than disappear from
    /// the library silently.
    public func list() throws -> [TextDocument] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw TextDocError.ioFailure("could not list \(root.path): \(error)")
        }

        var documents: [TextDocument] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else {
                continue
            }
            documents.append(try load(fileURL: url))
        }
        return documents.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Deletes the document with `id`, or throws ``TextDocError/notFound(path:)``.
    public func delete(id: UUID) throws {
        let file = fileURL(for: id)
        guard fileManager.fileExists(atPath: file.path) else {
            throw TextDocError.notFound(path: file.path)
        }
        do {
            try fileManager.removeItem(at: file)
        } catch {
            throw TextDocError.ioFailure("could not delete \(file.path): \(error)")
        }
    }

    /// Creates the root directory, or verifies that the existing root is a directory.
    private func createRootIfNeeded() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw TextDocError.ioFailure("not a directory: \(root.path)")
            }
            return
        }
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw TextDocError.ioFailure("could not create \(root.path): \(error)")
        }
    }
}
