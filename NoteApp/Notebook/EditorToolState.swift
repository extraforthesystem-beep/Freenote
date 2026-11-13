import Foundation
import InkKit
import NoteCore
import Observation

/// The one tool the editor is using. Everything that used to be separate
/// flags (canvas mode, element editing) is derived from this.
enum EditorTool: String, CaseIterable, Hashable, Sendable {
    case pen
    case highlighter
    case eraser
    case lasso
    case laser
    case elements
    case links

    /// Tools that put ink on the active layer, or change ink on it.
    var editsInk: Bool {
        switch self {
        case .pen, .highlighter, .eraser, .lasso: true
        case .laser, .elements, .links: false
        }
    }

    var drawsInk: Bool { self == .pen || self == .highlighter }

    var displayName: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        case .laser: "Laser Pointer"
        case .elements: "Select Elements"
        case .links: "Follow Links"
        }
    }

    /// The one key that selects the tool with a hardware keyboard, as shown in
    /// the tool's tooltip. Tools without a key are opened from the toolbar.
    var shortcut: String? {
        switch self {
        case .pen: "P"
        case .highlighter: "H"
        case .eraser: "E"
        case .lasso: "V"
        case .laser: "L"
        case .elements, .links: nil
        }
    }
}

/// What the laser pointer leaves on the page: a dot under the pointer, or a
/// short trail that fades after the pointer lifts.
enum LaserMode: String, CaseIterable, Hashable, Sendable {
    case dot
    case line

    var displayName: String {
        switch self {
        case .dot: "Dot"
        case .line: "Line"
        }
    }
}

/// Stroke or pixel erasing. App-side so the tool state also builds where
/// InkKit's canvas types do not exist (macOS).
enum EraserMode: String, Hashable, Sendable {
    case stroke
    case pixel
}

/// The editor's tool, pens, eraser and colours. Writes to `UserDefaults` are
/// debounced so dragging a slider does not encode JSON on every tick.
@MainActor
@Observable
final class EditorToolState {
    var tool: EditorTool {
        didSet {
            guard tool != oldValue else { return }
            previousTool = oldValue
            if tool.drawsInk { lastInkTool = tool }
            scheduleSave()
        }
    }
    /// Reading only: the canvas takes no ink and the tools are disabled. Per
    /// open notebook, in memory only.
    var isReadOnly = false
    /// Reading Mode: Read Only with the chrome hidden and tap zones to turn the
    /// page. Per open notebook, in memory only.
    var isReadingMode = false
    /// Zoom View: a magnified band of the page to write in, in a panel below
    /// the page. Per open notebook, in memory only; hidden in Read Only.
    var isZoomViewShown = false
    /// The tool that was active before the current one, so erasing can go back.
    private(set) var previousTool: EditorTool = .pen
    private(set) var penStyle: PenStyle
    private(set) var presets: PenPresets
    private(set) var eraserKind: EraserMode
    private(set) var eraserWidth: Double
    private(set) var laserMode: LaserMode
    /// The eight colours the pen shows in the toolbar.
    private(set) var penFavorites: ColorFavorites
    /// The eight colours the highlighter shows in the toolbar.
    private(set) var highlighterFavorites: ColorFavorites
    /// The last eight colours used by either ink tool, newest first.
    private(set) var recentColors: ColorRecents
    /// The three width slots the pen shows in the toolbar.
    private(set) var penWidthPresets: WidthPresets
    /// The three width slots the highlighter shows in the toolbar.
    private(set) var highlighterWidthPresets: WidthPresets
    /// Saved pens: style, colour and width. Owns its own persistence.
    let favoritePens: FavoritePens
    /// Bumped when the Apple Pencil asks for the colour palette. The toolbar
    /// opens its pen popover and nothing else reads it.
    private(set) var paletteRequestID = 0
    /// The ink tool colour and width changes go to when no ink tool is active.
    @ObservationIgnored private var lastInkTool: EditorTool = .pen
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let eraserWidths: [Double] = [6, 12, 24, 48]
    static let highlighterAlpha = 0.35
    /// Shared with the eraser popover's `@AppStorage` toggle.
    static let eraserAutoDeselectKey = "eraserAutoDeselect"

    private enum Keys {
        static let tool = "noteapp.editor.tool"
        static let penStyle = "noteapp.editor.penStyle"
        static let eraserKind = "noteapp.editor.eraserKind"
        static let eraserWidth = "noteapp.editor.eraserWidth"
        static let laserMode = "noteapp.editor.laserMode"
        static let penFavorites = "noteapp.editor.penFavorites.v1"
        static let highlighterFavorites = "noteapp.editor.highlighterFavorites.v1"
        static let penWidthPresets = "noteapp.editor.penWidthPresets.v1"
        static let highlighterWidthPresets = "noteapp.editor.highlighterWidthPresets.v1"
        static let recentColors = "noteapp.editor.recentColors.v1"
        /// The pre-palette list of five recent colours, migrated once.
        static let legacySwatches = "noteapp.editor.swatches.v1"
    }

    init(defaults: UserDefaults = .standard) {
        presets = PenPresets.load()
        favoritePens = FavoritePens(defaults: defaults)
        penStyle = defaults.string(forKey: Keys.penStyle).flatMap(PenStyle.init(rawValue:)) ?? .pen
        eraserKind = defaults.string(forKey: Keys.eraserKind).flatMap(EraserMode.init(rawValue:)) ?? .stroke
        laserMode = defaults.string(forKey: Keys.laserMode).flatMap(LaserMode.init(rawValue:)) ?? .line
        let storedWidth = defaults.double(forKey: Keys.eraserWidth)
        eraserWidth = storedWidth > 0 ? storedWidth : 12

        let legacySwatches = defaults.data(forKey: Keys.legacySwatches)
            .flatMap { try? JSONDecoder().decode([RGBAColor].self, from: $0) }

        if let data = defaults.data(forKey: Keys.penFavorites),
           let stored = try? JSONDecoder().decode(ColorFavorites.self, from: data) {
            penFavorites = stored
        } else if let legacySwatches {
            // The old recents become the first pen favourites.
            penFavorites = ColorFavorites(migrating: legacySwatches, defaults: InkColorDefaults.pen)
        } else {
            penFavorites = ColorFavorites(InkColorDefaults.pen)
        }

        if let data = defaults.data(forKey: Keys.highlighterFavorites),
           let stored = try? JSONDecoder().decode(ColorFavorites.self, from: data) {
            highlighterFavorites = stored
        } else {
            highlighterFavorites = ColorFavorites(InkColorDefaults.highlighter)
        }

        if let data = defaults.data(forKey: Keys.recentColors),
           let stored = try? JSONDecoder().decode(ColorRecents.self, from: data) {
            recentColors = stored
        } else {
            recentColors = ColorRecents(legacySwatches ?? [])
        }

        if let data = defaults.data(forKey: Keys.penWidthPresets),
           let stored = try? JSONDecoder().decode(WidthPresets.self, from: data) {
            penWidthPresets = stored
        } else {
            penWidthPresets = WidthPresets(WidthPresetDefaults.pen)
        }

        if let data = defaults.data(forKey: Keys.highlighterWidthPresets),
           let stored = try? JSONDecoder().decode(WidthPresets.self, from: data) {
            highlighterWidthPresets = stored
        } else {
            highlighterWidthPresets = WidthPresets(WidthPresetDefaults.highlighter)
        }

        tool = Self.restoredTool(in: defaults)
        if tool.drawsInk { lastInkTool = tool }
        previousTool = tool.drawsInk ? tool : .pen
    }

    /// The tool a newly opened notebook starts with. Remembering is a setting;
    /// tools that do not edit ink and an eraser that would deselect itself fall
    /// back to the pen.
    private static func restoredTool(in defaults: UserDefaults) -> EditorTool {
        guard AppSettings.bool(AppSettings.Key.rememberLastTool, default: true, in: defaults),
              let stored = defaults.string(forKey: Keys.tool).flatMap(EditorTool.init(rawValue:))
        else { return .pen }
        switch stored {
        case .pen, .highlighter, .lasso:
            return stored
        case .eraser:
            return defaults.bool(forKey: Self.eraserAutoDeselectKey) ? .pen : .eraser
        case .laser, .elements, .links:
            return .pen
        }
    }

    // MARK: - Derived

    var penTool: InkTool { clamped(presets.tool(for: penStyle)) }
    var highlighterTool: InkTool { clamped(presets.highlighter) }

    /// A stored width is clamped into the ink's own range, which PencilKit
    /// enforces anyway.
    private func clamped(_ tool: InkTool) -> InkTool {
        var result = tool
        result.width = PenWidth.clamp(result.width, to: tool.widthRange)
        return result
    }

    /// The ink tool the toolbar edits: the current one, or the last one used
    /// while erasing, lassoing or in another non-drawing tool.
    var activeInkTool: EditorTool {
        tool.drawsInk ? tool : lastInkTool
    }

    /// The favourites of the active ink tool.
    var favoriteColors: ColorFavorites {
        activeInkTool == .highlighter ? highlighterFavorites : penFavorites
    }

    /// The ink tool shown on the canvas and edited by colour and width.
    var inkTool: InkTool {
        activeInkTool == .highlighter ? highlighterTool : penTool
    }

    #if os(iOS)
    var canvasMode: CanvasMode {
        switch tool {
        case .pen, .highlighter, .elements: .ink
        case .eraser: .eraser(eraserKind == .stroke ? .stroke : .pixel, width: eraserWidth)
        case .lasso: .lasso
        case .laser: .disabled
        case .links: .links
        }
    }
    #endif

    /// Three quick widths for whatever the width dots currently change. The
    /// eraser keeps its own fixed sizes; the ink tools have editable slots,
    /// clamped into the current style's range.
    var widthPresets: [Double] {
        if tool == .eraser { return [8, 20, 44] }
        return activeWidthPresets.clamped(to: inkWidthRange)
    }

    private var activeWidthPresets: WidthPresets {
        activeInkTool == .highlighter ? highlighterWidthPresets : penWidthPresets
    }

    var currentWidth: Double {
        tool == .eraser ? eraserWidth : inkTool.width
    }

    var inkWidthRange: ClosedRange<Double> {
        inkTool.widthRange
    }

    func isCurrentColor(_ color: RGBAColor) -> Bool {
        let current = inkTool.color
        return abs(current.r - color.r) < 0.01
            && abs(current.g - color.g) < 0.01
            && abs(current.b - color.b) < 0.01
    }

    // MARK: - Changes

    func selectPenStyle(_ style: PenStyle) {
        penStyle = style
        tool = .pen
        scheduleSave()
    }

    func setEraser(kind: EraserMode) {
        eraserKind = kind
        tool = .eraser
        scheduleSave()
    }

    func setEraserWidth(_ width: Double) {
        eraserWidth = width
        tool = .eraser
        scheduleSave()
    }

    func setLaserMode(_ mode: LaserMode) {
        laserMode = mode
        tool = .laser
        scheduleSave()
    }

    /// Called when the pencil or finger lifts after using the current tool.
    /// With Auto-Deselect on, erasing returns to the tool used before it.
    func didEndToolGesture() {
        guard tool == .eraser, previousTool != .eraser,
              UserDefaults.standard.bool(forKey: Self.eraserAutoDeselectKey)
        else { return }
        tool = previousTool
    }

    /// A double-tap on the Apple Pencil's side. The canvas resolves `.system`
    /// to the user's Apple Pencil preference before calling this.
    func handlePencilDoubleTap(_ action: PencilDoubleTapAction) {
        guard !isReadOnly else { return }
        switch action {
        case .off, .system:
            break
        case .eraser:
            // A second double-tap goes back to the tool used before erasing.
            if tool == .eraser {
                tool = previousTool == .eraser ? .pen : previousTool
            } else {
                tool = .eraser
            }
        case .previousTool:
            guard previousTool != tool else { return }
            tool = previousTool
        case .colorPalette:
            paletteRequestID &+= 1
        }
    }

    /// Changes the colour of the active ink tool. Picking a colour while
    /// erasing or selecting goes back to the last pen, as in other note apps.
    func setColor(_ color: RGBAColor) {
        if !tool.drawsInk { tool = lastInkTool }
        var updated = inkTool
        var newColor = color
        newColor.a = updated.isHighlighter ? Self.highlighterAlpha : 1
        updated.color = newColor
        presets.update(updated)
        recentColors.record(newColor)
        scheduleSave()
    }

    // MARK: - Favourite colours

    /// Adds the colour to the active ink tool's favourites. Fails when the
    /// eight slots are full.
    @discardableResult
    func addFavoriteColor(_ color: RGBAColor) -> Bool {
        var favorites = favoriteColors
        guard favorites.add(color) else { return false }
        setFavorites(favorites)
        return true
    }

    /// Swaps one favourite for another, keeping its place in the row. If the
    /// colour is already another favourite, the two slots trade places so the
    /// row never shows the same colour twice and never shifts.
    func replaceFavoriteColor(at index: Int, with color: RGBAColor) {
        var favorites = favoriteColors
        guard favorites.colors.indices.contains(index) else { return }
        if let existing = favorites.index(of: color), existing != index {
            // The colour is already another favourite: the two slots trade
            // places, so the row keeps its length and nothing shifts.
            favorites.swapAt(index, existing)
        } else {
            guard favorites.replace(at: index, with: color) else { return }
        }
        setFavorites(favorites)
        // The palette shows the new colour in its Recent row straight away.
        recentColors.record(color)
    }

    /// Moves a favourite to another slot, shifting the ones it passes. Dragging
    /// a swatch and the VoiceOver Move Left/Right actions both come here.
    func moveFavoriteColor(from source: Int, to destination: Int) {
        var favorites = favoriteColors
        guard favorites.move(from: source, to: destination) else { return }
        setFavorites(favorites)
    }

    /// Leaves the seven remaining favourites in place; the toolbar then shows
    /// a free slot.
    func removeFavoriteColor(at index: Int) {
        var favorites = favoriteColors
        guard favorites.remove(at: index) else { return }
        setFavorites(favorites)
    }

    func isFavoriteColor(_ color: RGBAColor) -> Bool {
        favoriteColors.contains(color)
    }

    /// A spoken colour name for VoiceOver, e.g. "Blue".
    func colorName(for color: RGBAColor) -> String {
        ColorPalette.name(for: color)
    }

    private func setFavorites(_ favorites: ColorFavorites) {
        if activeInkTool == .highlighter {
            highlighterFavorites = favorites
        } else {
            penFavorites = favorites
        }
        scheduleSave()
    }

    /// Sets the width of the eraser when erasing, otherwise of the ink tool.
    func setWidth(_ width: Double) {
        if tool == .eraser {
            eraserWidth = width
        } else {
            if !tool.drawsInk { tool = lastInkTool }
            var updated = inkTool
            updated.width = min(max(width, inkWidthRange.lowerBound), inkWidthRange.upperBound)
            presets.update(updated)
        }
        scheduleSave()
    }

    // MARK: - Width presets

    /// Saves a width into one of the active ink tool's slots and applies it.
    /// The eraser's fixed sizes are not editable.
    func setWidthPreset(at index: Int, to width: Double) {
        guard tool != .eraser else { return }
        let clamped = PenWidth.clamp(width, to: inkWidthRange)
        if activeInkTool == .highlighter {
            highlighterWidthPresets.setWidth(clamped, at: index, range: inkWidthRange)
        } else {
            penWidthPresets.setWidth(clamped, at: index, range: inkWidthRange)
        }
        setWidth(clamped)
    }

    /// Restores the active ink tool's three default widths.
    func resetWidthPresets() {
        guard tool != .eraser else { return }
        if activeInkTool == .highlighter {
            highlighterWidthPresets = WidthPresets(WidthPresetDefaults.highlighter)
        } else {
            penWidthPresets = WidthPresets(WidthPresetDefaults.pen)
        }
        scheduleSave()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes presets at once, e.g. when the editor closes.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        recentColors.record(inkTool.color)
        presets.save()
        favoritePens.save()
        let defaults = UserDefaults.standard
        defaults.set(tool.rawValue, forKey: Keys.tool)
        defaults.set(penStyle.rawValue, forKey: Keys.penStyle)
        defaults.set(eraserKind.rawValue, forKey: Keys.eraserKind)
        defaults.set(eraserWidth, forKey: Keys.eraserWidth)
        defaults.set(laserMode.rawValue, forKey: Keys.laserMode)
        if let data = try? JSONEncoder().encode(penFavorites) {
            defaults.set(data, forKey: Keys.penFavorites)
        }
        if let data = try? JSONEncoder().encode(highlighterFavorites) {
            defaults.set(data, forKey: Keys.highlighterFavorites)
        }
        if let data = try? JSONEncoder().encode(recentColors) {
            defaults.set(data, forKey: Keys.recentColors)
        }
        if let data = try? JSONEncoder().encode(penWidthPresets) {
            defaults.set(data, forKey: Keys.penWidthPresets)
        }
        if let data = try? JSONEncoder().encode(highlighterWidthPresets) {
            defaults.set(data, forKey: Keys.highlighterWidthPresets)
        }
    }
}
