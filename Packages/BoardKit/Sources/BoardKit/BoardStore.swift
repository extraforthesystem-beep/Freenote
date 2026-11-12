import Foundation

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
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            throw BoardStoreError.ioFailure(
                "could not write \(url.path): \(error.localizedDescription)"
            )
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
        guard probe.schemaVersion == BoardDocument.currentSchemaVersion else {
            throw BoardStoreError.unsupportedSchemaVersion(
                found: probe.schemaVersion,
                supported: BoardDocument.currentSchemaVersion
            )
        }
        if let boardVersion = probe.board?.schemaVersion,
           boardVersion != BoardDocument.currentSchemaVersion {
            throw BoardStoreError.unsupportedSchemaVersion(
                found: boardVersion,
                supported: BoardDocument.currentSchemaVersion
            )
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
