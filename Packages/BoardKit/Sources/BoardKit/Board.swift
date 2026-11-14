import CoreGraphics
import Foundation

/// One board: a z-ordered collection of items plus deletion tombstones.
public struct Board: Codable, Identifiable, Hashable, Sendable {
    /// Schema version written by this build.
    ///
    /// Version 2 adds sticky notes. Reads stay compatible with version 1, and
    /// an unknown item kind is skipped instead of failing the whole board.
    public static let currentSchemaVersion = 2

    /// Stable identity, also used as the board file name by `BoardStore`.
    public var id: UUID
    /// Human-readable board name.
    public var title: String
    /// Stored items. May retain tombstoned payloads after a merge; see `deletedItemIDs`.
    public var items: [BoardItem]
    /// Deleted item IDs. A tombstone always hides an item with the same ID.
    public var deletedItemIDs: Set<UUID>
    /// When the board was created.
    public var createdAt: Date
    /// When the board last changed.
    public var updatedAt: Date
    /// Version of the board payload.
    public var schemaVersion: Int

    /// Creates a board. `updatedAt` defaults to `createdAt`.
    public init(
        id: UUID = UUID(),
        title: String = "Untitled Board",
        items: [BoardItem] = [],
        deletedItemIDs: Set<UUID> = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        schemaVersion: Int = Board.currentSchemaVersion
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.deletedItemIDs = deletedItemIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.schemaVersion = schemaVersion
    }

    /// Items that are not tombstoned, in stored order.
    public var visibleItems: [BoardItem] {
        items.filter { !deletedItemIDs.contains($0.id) }
    }

    /// The stored item with this ID, including a tombstoned payload.
    public func item(_ id: UUID) -> BoardItem? {
        items.first { $0.id == id }
    }

    /// Adds an item, replacing an existing item with the same ID, and clears its tombstone.
    public mutating func add(_ item: BoardItem, at date: Date = Date()) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        deletedItemIDs.remove(item.id)
        updatedAt = max(updatedAt, date)
    }

    /// Removes an item and records a tombstone so a merge cannot resurrect it.
    @discardableResult
    public mutating func remove(_ itemID: UUID, at date: Date = Date()) -> BoardItem? {
        let removed = item(itemID)
        items.removeAll { $0.id == itemID }
        deletedItemIDs.insert(itemID)
        updatedAt = max(updatedAt, date)
        return removed
    }

    /// Moves a frame-backed, unlocked item to a new origin, preserving its size.
    @discardableResult
    public mutating func move(_ itemID: UUID, to origin: CGPoint, at date: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              !items[index].isLocked,
              !deletedItemIDs.contains(itemID),
              let frame = items[index].frame
        else {
            return false
        }
        guard origin.x.isFinite, origin.y.isFinite else { return false }
        let newFrame = CGRect(origin: origin, size: frame.size)
        guard newFrame != frame else { return false }
        items[index].setFrame(newFrame)
        items[index].updatedAt = date
        updatedAt = max(updatedAt, date)
        return true
    }

    /// Resizes a frame-backed, unlocked item, preserving its origin.
    @discardableResult
    public mutating func resize(_ itemID: UUID, to size: CGSize, at date: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              !items[index].isLocked,
              !deletedItemIDs.contains(itemID),
              let frame = items[index].frame
        else {
            return false
        }
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let newFrame = CGRect(origin: frame.origin, size: CGSize(width: width, height: height))
        guard newFrame != frame else { return false }
        items[index].setFrame(newFrame)
        items[index].updatedAt = date
        updatedAt = max(updatedAt, date)
        return true
    }

    /// Sets the locked flag of a stored item.
    @discardableResult
    public mutating func lock(
        _ itemID: UUID,
        _ locked: Bool = true,
        at date: Date = Date()
    ) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              !deletedItemIDs.contains(itemID),
              items[index].isLocked != locked
        else {
            return false
        }
        items[index].isLocked = locked
        items[index].updatedAt = date
        updatedAt = max(updatedAt, date)
        return true
    }

    /// Visible items in deterministic draw order: z-index, creation time, then ID.
    public func normalizedZOrder() -> [BoardItem] {
        visibleItems.sorted { lhs, rhs in
            if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// World bounds of all visible items; nil for an empty board.
    public func bounds() -> CGRect? {
        var result: CGRect?
        for item in visibleItems {
            guard let itemBounds = item.bounds else { continue }
            result = result.map { $0.union(itemBounds) } ?? itemBounds
        }
        return result
    }

    /// Visible items whose bounds intersect `rect`, in draw order.
    ///
    /// A connector is included when either of its endpoint items is included.
    public func items(in rect: CGRect) -> [BoardItem] {
        let visible = normalizedZOrder()
        var included = Set<UUID>()
        for item in visible {
            if let itemBounds = item.bounds, itemBounds.intersects(rect) {
                included.insert(item.id)
            }
        }
        for item in visible {
            if case let .connector(from, to, _) = item.content,
               included.contains(from) || included.contains(to) {
                included.insert(item.id)
            }
        }
        return visible.filter { included.contains($0.id) }
    }

    /// Frame-backed items whose frame intersects `rect`, in draw order, plus
    /// every item in `alwaysIncluding`.
    ///
    /// This is the viewport query for the item layer. It cannot use
    /// ``items(in:)``: that computes the bounds of the ink item, which walks
    /// every point of every stroke, and the item layer never draws ink anyway.
    /// `alwaysIncluding` keeps a selected object's outline and handles alive
    /// when the object is dragged past the edge of the screen.
    public func frameBackedItems(
        in rect: CGRect,
        alwaysIncluding ids: Set<UUID> = []
    ) -> [BoardItem] {
        normalizedZOrder().filter { item in
            guard let frame = item.frame else { return false }
            return frame.intersects(rect) || ids.contains(item.id)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, items, deletedItemIDs, createdAt, updatedAt, schemaVersion
    }

    /// Decodes a board from an older schema, and skips item kinds this build
    /// does not know instead of refusing the file. The board is upgraded to
    /// `currentSchemaVersion`, so its next save writes the current format.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Board"
        items = try container.decodeIfPresent([LossyBoardItem].self, forKey: .items)?
            .compactMap(\.item) ?? []
        deletedItemIDs = Set(
            try container.decodeIfPresent([UUID].self, forKey: .deletedItemIDs) ?? []
        )
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        schemaVersion = Self.currentSchemaVersion
    }

    /// One item decoded on its own: an unknown content kind drops that item
    /// and keeps the rest of the board readable.
    private struct LossyBoardItem: Decodable {
        let item: BoardItem?

        init(from decoder: any Decoder) throws {
            item = try? BoardItem(from: decoder)
        }
    }

    /// Encodes tombstones in sorted order so board files are deterministic.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(items, forKey: .items)
        try container.encode(
            deletedItemIDs.sorted { $0.uuidString < $1.uuidString },
            forKey: .deletedItemIDs
        )
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }
}

extension Board {
    /// Applies a frame from layout code, respecting locks and tombstones.
    @discardableResult
    public mutating func setFrame(_ itemID: UUID, to frame: CGRect, at date: Date) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              !items[index].isLocked,
              !deletedItemIDs.contains(itemID),
              let current = items[index].frame,
              current != frame
        else {
            return false
        }
        items[index].setFrame(frame)
        items[index].updatedAt = date
        updatedAt = max(updatedAt, date)
        return true
    }
}
