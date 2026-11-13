import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Errors thrown by `BoardStore`.
public enum BoardStoreError: Error, Hashable, Sendable {
    /// The file or payload uses a schema this build does not understand.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The file is not a valid board document.
    case corruptFile(String)
    /// No file exists for the requested board ID.
    case notFound(UUID)
    /// The file system refused an operation.
    case ioFailure(String)
}

extension BoardStoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            "Unsupported board schema version \(found); this build supports version \(supported)."
        case let .corruptFile(path):
            "Corrupt board file: \(path.isEmpty ? "<memory>" : path)."
        case let .notFound(boardID):
            "No board file for \(boardID.uuidString)."
        case let .ioFailure(reason):
            "Board storage error: \(reason)"
        }
    }
}

/// Persists one JSON document per board under a root directory.
public actor BoardStore {
    /// Directory containing the board files.
    public nonisolated let rootURL: URL

    /// Creates a store rooted at a directory. The directory is created on first save.
    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// The file used for one board: `<lowercased UUID>.board.json`.
    public nonisolated func fileURL(for boardID: UUID) -> URL {
        rootURL.appendingPathComponent(
            "\(boardID.uuidString.lowercased()).board.json",
            isDirectory: false
        )
    }

    /// The folder holding images and other files inserted into boards. It is
    /// shared by every board, and asset names are unique, so a duplicate
    /// board can point at the same file.
    public nonisolated var assetsDirectoryURL: URL {
        rootURL.appendingPathComponent("Assets", isDirectory: true)
    }

    /// Writes an inserted file under the assets folder and returns the asset
    /// name an item stores. The folder is created on first use.
    public func addAsset(_ data: Data, fileExtension: String) throws -> String {
        let name = UUID().uuidString.lowercased() + Self.normalizedExtension(fileExtension)
        let file = assetsDirectoryURL.appendingPathComponent(name, isDirectory: false)

        do {
            try Self.writeDurably(data, to: file)
        } catch {
            throw BoardStoreError.ioFailure(
                "could not write \(file.path): \(error.localizedDescription)"
            )
        }
        return name
    }

    /// Lists board IDs that have a file, sorted by UUID string.
    public func list() throws -> [UUID] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw BoardStoreError.ioFailure(
                "could not list \(rootURL.path): \(error.localizedDescription)"
            )
        }
        return urls.compactMap { url -> UUID? in
            let name = url.lastPathComponent
            guard name.hasSuffix(".board.json") else { return nil }
            let stem = String(name.dropLast(".board.json".count))
            return UUID(uuidString: stem)
        }.sorted { $0.uuidString < $1.uuidString }
    }

    /// Loads one board, refusing an unknown schema before decoding the board body.
    public func load(_ boardID: UUID) throws -> BoardDocument {
        let url = fileURL(for: boardID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BoardStoreError.notFound(boardID)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BoardStoreError.ioFailure(
                "could not read \(url.path): \(error.localizedDescription)"
            )
        }

        try Self.checkDocumentVersion(data, path: url.lastPathComponent)

        let document: BoardDocument
        do {
            document = try Self.makeDecoder().decode(BoardDocument.self, from: data)
        } catch {
            throw BoardStoreError.corruptFile(url.lastPathComponent)
        }

        guard document.board.schemaVersion == BoardDocument.currentSchemaVersion else {
            throw BoardStoreError.unsupportedSchemaVersion(
                found: document.board.schemaVersion,
                supported: BoardDocument.currentSchemaVersion
            )
        }
        guard document.board.id == boardID else {
            throw BoardStoreError.corruptFile(url.lastPathComponent)
        }
        return document
    }

    /// Writes one board atomically, refusing to write an unknown schema.
    public func save(_ document: BoardDocument) throws {
        guard document.schemaVersion == BoardDocument.currentSchemaVersion else {
            throw BoardStoreError.unsupportedSchemaVersion(
                found: document.schemaVersion,
                supported: BoardDocument.currentSchemaVersion
            )
        }
        guard document.board.schemaVersion == BoardDocument.currentSchemaVersion else {
            throw BoardStoreError.unsupportedSchemaVersion(
                found: document.board.schemaVersion,
                supported: BoardDocument.currentSchemaVersion
            )
        }

        let url = fileURL(for: document.board.id)
        let data: Data
        do {
            data = try Self.makeEncoder().encode(document)
        } catch {
            throw BoardStoreError.ioFailure(
                "could not encode \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }

        do {
            try Self.writeDurably(data, to: url)
        } catch {
            throw BoardStoreError.ioFailure(
                "could not write \(url.path): \(error.localizedDescription)"
            )
        }
    }

    /// Writes bytes so a crash leaves either the old file or the new one,
    /// never a half-written file: a hidden temporary sibling is written,
    /// flushed to disk, renamed over the target, and then the directory itself
    /// is flushed so the rename survives a power loss.
    ///
    /// `Data.write(options: .atomic)` renames but does not flush, so a crash
    /// just after a save can leave an empty or truncated board file.
    private static func writeDurably(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = directory.appendingPathComponent(
            ".tmp-\(UUID().uuidString)",
            isDirectory: false
        )
        do {
            try data.write(to: temporary, options: [])

            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            // POSIX rename replaces an existing file in one step and cannot
            // leave a copy behind, as `replaceItemAt` can.
            guard rename(temporary.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        try syncDirectory(directory)
    }

    /// Flushes a directory entry, so a rename into it is on disk.
    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Deletes one board file. A missing file is ignored.
    public func delete(_ boardID: UUID) throws {
        let url = fileURL(for: boardID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw BoardStoreError.ioFailure(
                "could not delete \(url.path): \(error.localizedDescription)"
            )
        }
    }

    /// Deletes one board file, then the image assets that only it referenced.
    ///
    /// The assets folder is shared by every board, so an asset is removed only
    /// when no remaining board file still names it. An asset is also kept when
    /// a board file cannot be read: leaking a file is better than deleting one
    /// that is still in use.
    ///
    /// - Returns: The names of the assets that were removed.
    @discardableResult
    public func delete(_ board: Board) throws -> [String] {
        try delete(board.id)
        return deleteUnreferencedAssets(of: board)
    }

    private func deleteUnreferencedAssets(of board: Board) -> [String] {
        let candidates = Self.assetNames(in: board)
        guard !candidates.isEmpty else { return [] }

        var stillUsed = Set<String>()
        do {
            for id in try list() {
                do {
                    stillUsed.formUnion(Self.assetNames(in: try load(id).board))
                } catch {
                    // An unreadable board may still point at any asset.
                    return []
                }
            }
        } catch {
            return []
        }

        var removed: [String] = []
        for name in candidates.subtracting(stillUsed).sorted() {
            let file = assetsDirectoryURL.appendingPathComponent(name, isDirectory: false)
            // Never follow a name out of the assets folder.
            guard file.lastPathComponent == name else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil {
                removed.append(name)
            }
        }
        return removed
    }

    /// Every asset name the board's stored items point at.
    private nonisolated static func assetNames(in board: Board) -> Set<String> {
        var names = Set<String>()
        for item in board.items {
            if case let .image(assetName, _) = item.content, !assetName.isEmpty {
                names.insert(assetName)
            }
        }
        return names
    }

    private struct VersionProbe: Decodable {
        struct BoardProbe: Decodable {
            let schemaVersion: Int
        }

        let schemaVersion: Int
        let board: BoardProbe?
    }

    private static func checkDocumentVersion(_ data: Data, path: String) throws {
        let probe: VersionProbe
        do {
            probe = try makeDecoder().decode(VersionProbe.self, from: data)
        } catch {
            throw BoardStoreError.corruptFile(path)
        }
        guard Self.supports(probe.schemaVersion) else {
            throw BoardStoreError.unsupportedSchemaVersion(
                found: probe.schemaVersion,
                supported: BoardDocument.currentSchemaVersion
            )
        }
        if let boardVersion = probe.board?.schemaVersion,
           !Self.supports(boardVersion) {
            throw BoardStoreError.unsupportedSchemaVersion(
                found: boardVersion,
                supported: BoardDocument.currentSchemaVersion
            )
        }
    }

    /// Reads are lenient about older versions, which are upgraded on load;
    /// writes always use the current version.
    private static func supports(_ version: Int) -> Bool {
        version >= 1 && version <= BoardDocument.currentSchemaVersion
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    /// A file extension as a dot and lower-case letters, or `.png`.
    private static func normalizedExtension(_ raw: String) -> String {
        let cleaned = raw.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return cleaned.isEmpty ? ".png" : ".\(cleaned)"
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
