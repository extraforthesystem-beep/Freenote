import Foundation

/// One item of a checklist block.
public struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    /// Stable identity, preserved across saves and edits.
    public var id: UUID
    /// The item text, without any checkbox marker.
    public var text: String
    /// Whether the item is ticked.
    public var isChecked: Bool

    /// Creates an item, unchecked by default.
    public init(id: UUID = UUID(), text: String, isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}
