import Foundation

/// Every error StudyKit throws.
public enum StudyKitError: Error, Hashable, Sendable {
    /// A review quality outside the SM-2 range of 0...5.
    case invalidQuality(Int)
    /// The session has no card waiting to be graded.
    case noCurrentCard
    /// The import text is empty, or contains only blank lines.
    case emptyCSV
    /// The first CSV row is not a `question,answer` header.
    case invalidCSVHeader(found: [String])
    /// A quoted CSV field never closes before the end of the document.
    case unterminatedQuotedField(row: Int)
    /// A double quote appears inside an unquoted CSV field.
    case unexpectedQuote(row: Int, column: Int)
    /// A closing quote is followed by something other than a comma or line break.
    case unexpectedCharacterAfterQuote(row: Int, column: Int)
    /// A CSV row does not have exactly two fields.
    case wrongFieldCount(row: Int, expected: Int, found: Int)
    /// The requested set file does not exist.
    case notFound(path: String)
    /// A set file cannot be decoded, or its id does not match its file name.
    case corruptFile(path: String)
    /// The file system refused an operation.
    case ioFailure(String)
}

extension StudyKitError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidQuality(quality):
            "Invalid review quality \(quality); expected 0...5."
        case .noCurrentCard:
            "The session has no card waiting to be graded."
        case .emptyCSV:
            "The CSV document is empty."
        case let .invalidCSVHeader(found):
            "Invalid CSV header \(found); expected question,answer."
        case let .unterminatedQuotedField(row):
            "Unterminated quoted field in CSV row \(row)."
        case let .unexpectedQuote(row, column):
            "Unexpected quote in unquoted CSV field at row \(row), column \(column)."
        case let .unexpectedCharacterAfterQuote(row, column):
            "Unexpected character after a quoted CSV field at row \(row), column \(column)."
        case let .wrongFieldCount(row, expected, found):
            "CSV row \(row) has \(found) fields; expected \(expected)."
        case let .notFound(path):
            "Not found: \(path)"
        case let .corruptFile(path):
            "Corrupt study set file: \(path)"
        case let .ioFailure(reason):
            "File system error: \(reason)"
        }
    }
}
