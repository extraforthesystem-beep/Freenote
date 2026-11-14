import Foundation

/// One item of a bulleted or numbered list.
///
/// The item carries an identity so an editor can keep one row bound to one
/// item while items above it are split, merged or removed. Older documents
/// stored plain strings; `init(from:)` still reads those and gives each item a
/// fresh identity, so no file needs converting.
public struct ListItem: Codable, Hashable, Identifiable, Sendable, ExpressibleByStringLiteral {
    /// Stable identity, preserved across saves, edits and splits.
    public var id: UUID
    /// The item text, without any list marker.
    public var text: String

    /// Creates an item with a fresh identity unless one is supplied.
    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }

    /// Creates an item from a literal string, for tests and short lists.
    public init(stringLiteral value: String) {
        self.init(text: value)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
    }

    /// Decodes both the object written by this build and the bare string of an
    /// older file.
    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.id = UUID()
            self.text = text
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.text = try container.decode(String.self, forKey: .text)
    }

    /// Writes `id` and `text` as an object.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
    }
}

extension Sequence where Element == ListItem {
    /// The items' text, for exporting and measuring.
    public var texts: [String] { map(\.text) }
}
