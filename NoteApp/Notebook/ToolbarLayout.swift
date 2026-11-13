import Foundation

/// One item that can be shown in the editor toolbar. The pen chip is not an
/// item: it is always first and cannot be removed.
nonisolated enum ToolbarItemID: String, CaseIterable, Codable, Identifiable, Sendable {
    case highlighter, eraser, lasso, elements, insert
    case laser, zoomView, followLinks, ruler, shapes
    case textBox, image, stickyNote, addPage, search, favoritePens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        case .elements: "Select Elements"
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
        }
    }

    var systemImage: String {
        switch self {
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        case .elements: "cursorarrow.rays"
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
        }
    }
}

/// Which toolbar items are shown, in order, stored as a comma-separated list of
/// raw values in `UserDefaults` (key `toolbar.items.v1`).
nonisolated struct ToolbarLayout: Equatable, Sendable {
    /// The key `@AppStorage` writes to.
    static let storageKey = "toolbar.items.v1"

    /// Pen chip, Highlighter, Eraser, Lasso, Select Elements, Insert.
    static let defaultItems: [ToolbarItemID] = [.highlighter, .eraser, .lasso, .elements, .insert]

    /// `defaultItems` as the stored string, for `@AppStorage` defaults.
    static var defaultStorage: String {
        defaultItems.map(\.rawValue).joined(separator: ",")
    }

    private(set) var items: [ToolbarItemID]

    init(items: [ToolbarItemID] = ToolbarLayout.defaultItems) {
        self.items = items
    }

    /// Reads the stored string. Unknown and duplicate ids are dropped; an
    /// empty or unusable string falls back to the default items.
    init(storage: String) {
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

    mutating func reset() {
        items = Self.defaultItems
    }
}
