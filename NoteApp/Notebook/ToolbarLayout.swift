import Foundation

/// One item that can be shown in the editor toolbar. The pen chip is not an
/// item: it is always first and cannot be removed.
nonisolated enum ToolbarItemID: String, CaseIterable, Codable, Identifiable, Sendable {
    case highlighter, eraser, lasso, elements, insert
    case laser, zoomView, followLinks, ruler, shapes
    case textBox, image, stickyNote, addPage, search, favoritePens
    // Undo and Redo, shown at the leading edge rather than in the tool group.
    case undo, redo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        case .elements: "Select Objects"
        case .insert: "Insert"
        case .laser: "Laser Pointer"
        case .zoomView: "Zoom View"
        case .followLinks: "Follow Links"
        case .ruler: "Ruler"
        case .shapes: "Shapes"
        case .textBox: "Text Box"
        case .image: "Image"
        case .stickyNote: "Sticky Note"
        case .addPage: "Add Page"
        case .search: "Search in Notebook"
        case .favoritePens: "Favourite Pens"
        case .undo: "Undo"
        case .redo: "Redo"
        }
    }

    var systemImage: String {
        switch self {
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        // A hand pointing at a box reads as "pick an object", where the old
        // cursorarrow.rays read as a sparkle.
        case .elements: "rectangle.and.hand.point.up.left"
        case .insert: "plus.circle"
        case .laser: "cursorarrow"
        case .zoomView: "plus.magnifyingglass"
        case .followLinks: "hand.point.up.left"
        case .ruler: "ruler"
        case .shapes: "square.on.circle"
        case .textBox: "character.textbox"
        case .image: "photo"
        case .stickyNote: "note"
        case .addPage: "plus.square"
        case .search: "magnifyingglass"
        case .favoritePens: "star"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        }
    }
}

/// Which toolbar items are shown, in order, stored as a comma-separated list of
/// raw values in `UserDefaults` (key `toolbar.items.v1`).
nonisolated struct ToolbarLayout: Equatable, Sendable {
    /// The key `@AppStorage` writes to.
    static let storageKey = "toolbar.items.v1"

    /// One-time flag for the Undo/Redo migration below.
    static let undoRedoMigrationKey = "toolbar.undoRedoAdded.v2"

    /// Undo and Redo. They are customisable items, but the toolbar draws them
    /// at the leading edge, next to Back, instead of in the tool group.
    static let historyItems: [ToolbarItemID] = [.undo, .redo]

    /// Undo, Redo, then the drawing tools: Undo and Redo lead, so they are
    /// visible by default rather than opt-in.
    static let defaultItems: [ToolbarItemID] = [.undo, .redo, .highlighter, .eraser, .lasso, .elements, .insert]

    /// `defaultItems` as the stored string, for `@AppStorage` defaults.
    static var defaultStorage: String {
        defaultItems.map(\.rawValue).joined(separator: ",")
    }

    private(set) var items: [ToolbarItemID]

    init(items: [ToolbarItemID] = ToolbarLayout.defaultItems) {
        self.items = items
    }

    /// Reads the stored string. Unknown and duplicate ids are dropped. An
    /// empty string is a toolbar with only the pen (the user removed every
    /// item); a non-empty string with no usable ids falls back to the defaults.
    init(storage: String) {
        guard !storage.isEmpty else {
            items = []
            return
        }
        var seen = Set<ToolbarItemID>()
        let parsed = storage
            .split(separator: ",")
            .compactMap { ToolbarItemID(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { seen.insert($0).inserted }
        items = parsed.isEmpty ? Self.defaultItems : parsed
    }

    var storage: String {
        items.map(\.rawValue).joined(separator: ",")
    }

    /// Everything not already in the toolbar, in declaration order.
    var available: [ToolbarItemID] {
        ToolbarItemID.allCases.filter { !items.contains($0) }
    }

    var isDefault: Bool {
        items == Self.defaultItems
    }

    /// True when either history control is in the toolbar.
    var hasHistoryItems: Bool {
        items.contains(.undo) || items.contains(.redo)
    }

    /// The items the toolbar draws in its tool group: everything except Undo
    /// and Redo, which sit at the leading edge.
    var toolItems: [ToolbarItemID] {
        items.filter { !Self.historyItems.contains($0) }
    }

    mutating func add(_ item: ToolbarItemID) {
        guard !items.contains(item) else { return }
        items.append(item)
    }

    mutating func remove(_ item: ToolbarItemID) {
        items.removeAll { $0 == item }
    }

    /// Deletes the rows `List` reports removed.
    mutating func remove(atOffsets offsets: IndexSet) {
        items = items.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
    }

    /// Reorders the rows `List` reports moved, keeping their order.
    mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.sorted().compactMap { items.indices.contains($0) ? items[$0] : nil }
        guard !moving.isEmpty else { return }
        var remaining = items
        for index in offsets.sorted(by: >) where remaining.indices.contains(index) {
            remaining.remove(at: index)
        }
        let passed = offsets.filter { $0 < destination }.count
        let insertion = min(max(destination - passed, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertion)
        items = remaining
    }

    /// Puts Undo and Redo first, in that order, skipping either one already
    /// present. Used by the one-time migration, and by Reset to Default.
    mutating func insertHistoryItemsAtFront() {
        let missing = Self.historyItems.filter { !items.contains($0) }
        guard !missing.isEmpty else { return }
        items.insert(contentsOf: missing, at: 0)
    }

    mutating func reset() {
        items = Self.defaultItems
    }

    /// One-time migration for installs whose stored layout predates Undo and
    /// Redo being visible by default: adds them once. The flag means a user
    /// who removes them afterwards keeps that choice.
    ///
    /// A layout that already has either control is left alone, as is an
    /// install that has never customised the toolbar (the `@AppStorage`
    /// default already leads with both).
    @discardableResult
    static func migrateUndoRedoIfNeeded(in defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: undoRedoMigrationKey) else { return false }
        defaults.set(true, forKey: undoRedoMigrationKey)
        guard let stored = defaults.string(forKey: storageKey) else { return false }
        let layout = ToolbarLayout(storage: stored)
        guard !layout.hasHistoryItems else { return false }
        var migrated = layout
        migrated.insertHistoryItemsAtFront()
        guard migrated.storage != stored else { return false }
        defaults.set(migrated.storage, forKey: storageKey)
        return true
    }
}
