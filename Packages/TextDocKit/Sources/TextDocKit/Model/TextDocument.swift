import Foundation

/// A typed text document: a title and an ordered list of reflowable blocks.
///
/// Editing methods keep block order and identity stable. They do not change
/// `updatedAt`; call ``touch(at:)`` when saving an edit.
public struct TextDocument: Codable, Hashable, Identifiable, Sendable {
    /// The schema version written by this build.
    public static let currentSchemaVersion = 1

    /// Stable identity, also used as the file name by ``TextDocumentStore``.
    public var id: UUID
    /// Human-readable title, shown in the library.
    public var title: String
    /// The document body, in reading order.
    public var blocks: [TextBlock]
    /// When the document was created.
    public var createdAt: Date
    /// When the document was last edited.
    public var updatedAt: Date
    /// The on-disk schema version.
    public var schemaVersion: Int

    /// Creates a document; `updatedAt` defaults to `createdAt`.
    public init(
        id: UUID = UUID(),
        title: String = "",
        blocks: [TextBlock] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        schemaVersion: Int = TextDocument.currentSchemaVersion
    ) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.schemaVersion = schemaVersion
    }

    /// Inserts a block, clamping the index into `0...blocks.count`.
    public mutating func insert(_ block: TextBlock, at index: Int) {
        blocks.insert(block, at: min(max(index, 0), blocks.count))
    }

    /// Removes the block at `index` and returns it, or returns `nil` if the index is out of range.
    @discardableResult
    public mutating func removeBlock(at index: Int) -> TextBlock? {
        guard blocks.indices.contains(index) else { return nil }
        return blocks.remove(at: index)
    }

    /// Removes the block with `id` and returns it, or returns `nil` if it is not present.
    @discardableResult
    public mutating func removeBlock(id: UUID) -> TextBlock? {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return nil }
        return blocks.remove(at: index)
    }

    /// Moves the block at `source` so that it ends up at `destination`, clamped
    /// into `0...blocks.count`. Returns `false` for an invalid source index.
    ///
    /// `destination` is the index in the array after the block has been removed.
    @discardableResult
    public mutating func moveBlock(from source: Int, to destination: Int) -> Bool {
        guard blocks.indices.contains(source) else { return false }
        let block = blocks.remove(at: source)
        blocks.insert(block, at: min(max(destination, 0), blocks.count))
        return true
    }

    /// Moves the block with `id` to `destination`. Returns `false` if it is not present.
    @discardableResult
    public mutating func moveBlock(id: UUID, to destination: Int) -> Bool {
        guard let source = blocks.firstIndex(where: { $0.id == id }) else { return false }
        return moveBlock(from: source, to: destination)
    }

    /// Records an edit at `date`, which defaults to now.
    public mutating func touch(at date: Date = Date()) {
        updatedAt = date
    }

    /// The document body as plain text: each block's text on its own line.
    ///
    /// List and checklist items are one line each, without markers. Images,
    /// dividers and empty blocks contribute nothing.
    public var plainText: String {
        blocks.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
