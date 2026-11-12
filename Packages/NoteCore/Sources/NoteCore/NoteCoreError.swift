import Foundation

/// Every error this package throws.
public enum NoteCoreError: Error, Hashable, Sendable {
    /// The file was written by a newer schema than this build understands.
    /// No partly decoded value is ever returned.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The bytes are not a valid file of the expected kind.
    case corruptFile(path: String)
    /// The requested file or folder does not exist.
    case notFound(path: String)
    /// The caller asked for something the format cannot represent.
    case invalidInput(String)
    /// The file system refused an operation.
    case ioFailure(String)
}

extension NoteCoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            "Unsupported schema version \(found); this build supports up to \(supported)."
        case let .corruptFile(path):
            "Corrupt file: \(path.isEmpty ? "<memory>" : path)"
        case let .notFound(path):
            "Not found: \(path)"
        case let .invalidInput(reason):
            "Invalid input: \(reason)"
        case let .ioFailure(reason):
            "File system error: \(reason)"
        }
    }
}
