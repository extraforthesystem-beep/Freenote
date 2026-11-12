import Foundation

/// Every error `VersionHistoryStore` throws.
public enum HistoryKitError: Error, Hashable, Sendable {
    /// The history index was written by a newer schema than this build understands.
    case unsupportedIndexVersion(notebookID: UUID, found: Int, supported: Int)
    /// The index file exists but is not valid JSON of the expected shape.
    case corruptIndex(notebookID: UUID, reason: String)
    /// No metadata entry with that id exists in the notebook's index.
    case snapshotNotFound(UUID)
    /// Metadata exists, but its payload is missing or no longer matches the recorded hash and size.
    case corruptSnapshot(id: UUID, reason: String)
    /// A caller supplied a value the store cannot represent.
    case invalidInput(String)
    /// The file system refused an operation.
    case ioFailure(String)
}

extension HistoryKitError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unsupportedIndexVersion(notebookID, found, supported):
            "History index for notebook \(notebookID) has schema \(found); this build supports up to \(supported)."
        case let .corruptIndex(notebookID, reason):
            "History index for notebook \(notebookID) is unreadable: \(reason)"
        case let .snapshotNotFound(id):
            "No history snapshot with id \(id)."
        case let .corruptSnapshot(id, reason):
            "History snapshot \(id) is unreadable: \(reason)"
        case let .invalidInput(reason):
            "Invalid input: \(reason)"
        case let .ioFailure(reason):
            "File system error: \(reason)"
        }
    }
}
