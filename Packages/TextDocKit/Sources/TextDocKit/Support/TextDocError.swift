import Foundation

/// Every error this package throws.
public enum TextDocError: Error, Hashable, Sendable {
    /// The file was written by a schema this build does not support.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The bytes are not a valid text document.
    case corruptFile(path: String)
    /// The requested document does not exist.
    case notFound(path: String)
    /// The file system refused an operation.
    case ioFailure(String)
}

extension TextDocError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            "Unsupported schema version \(found); this build supports up to \(supported)."
        case let .corruptFile(path):
            "Corrupt text document: \(path.isEmpty ? "<memory>" : path)"
        case let .notFound(path):
            "Text document not found: \(path)"
        case let .ioFailure(reason):
            "File system error: \(reason)"
        }
    }
}
