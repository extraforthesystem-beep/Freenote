import CryptoKit
import Foundation

/// One point in a notebook's local version history.
///
/// The snapshot is metadata only; its bytes live in a separate payload file owned
/// by `VersionHistoryStore`. `dataHash` is the lowercase hexadecimal SHA-256 of
/// that payload, and `byteCount` is its length, so a load can reject a file that
/// was truncated or edited behind the store's back.
public struct VersionSnapshot: Codable, Identifiable, Hashable, Sendable {
    /// Stable identifier, also used as the metadata key.
    public var id: UUID
    /// The notebook this snapshot belongs to.
    public var notebookID: UUID
    /// The page this snapshot belongs to, or `nil` for a notebook-level snapshot.
    public var pageID: UUID?
    /// When the snapshot was recorded.
    public var createdAt: Date
    /// Why the snapshot was taken, for example `autosave` or `manual`.
    public var reason: String
    /// Lowercase hexadecimal SHA-256 of the payload.
    public var dataHash: String
    /// Payload length in bytes.
    public var byteCount: Int

    /// Creates a snapshot value; the id is new unless the caller supplies one.
    public init(
        id: UUID = UUID(),
        notebookID: UUID,
        pageID: UUID? = nil,
        createdAt: Date,
        reason: String,
        dataHash: String,
        byteCount: Int
    ) {
        self.id = id
        self.notebookID = notebookID
        self.pageID = pageID
        self.createdAt = createdAt
        self.reason = reason
        self.dataHash = dataHash
        self.byteCount = byteCount
    }
}

/// Newest-first and oldest-first ordering, with a stable tie-break on the id.
enum SnapshotOrder {
    static func isNewer(_ lhs: VersionSnapshot, than rhs: VersionSnapshot) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    static func isOlder(_ lhs: VersionSnapshot, than rhs: VersionSnapshot) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Content hashing shared by the store and its tests.
enum HistoryHash {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Deterministic JSON for the history index and manifest envelopes.
enum HistoryJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
