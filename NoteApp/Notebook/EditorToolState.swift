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
    /// The tool that was active before the current one, so erasing can go back.
    private(set) var previousTool: EditorTool = .pen
    private(set) var penStyle: PenStyle
    private(set) var presets: PenPresets
    private(set) var eraserKind: EraserMode
    private(set) var eraserWidth: Double
    private(set) var laserMode: LaserMode
    /// Most recent first. Starts with the standard colours.
    private(set) var swatches: [RGBAColor]
    /// The ink tool colour and width changes go to when no ink tool is active.
    @ObservationIgnored private var lastInkTool: EditorTool = .pen
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let swatchCount = 5
    static let standardColors: [RGBAColor] = [
        .black,
        RGBAColor(r: 0.0, g: 0.36, b: 0.86),
        RGBAColor(r: 0.85, g: 0.13, b: 0.15),
        RGBAColor(r: 0.09, g: 0.56, b: 0.27),
        RGBAColor(r: 0.96, g: 0.55, b: 0.05),
    ]
    static let eraserWidths: [Double] = [6, 12, 24, 48]
    static let highlighterAlpha = 0.35
    /// Shared with the eraser popover's `@AppStorage` toggle.
    static let eraserAutoDeselectKey = "eraserAutoDeselect"

    private enum Keys {
        static let penStyle = "noteapp.editor.penStyle"
        static let eraserKind = "noteapp.editor.eraserKind"
        static let eraserWidth = "noteapp.editor.eraserWidth"
        static let laserMode = "noteapp.editor.laserMode"
        static let swatches = "noteapp.editor.swatches.v1"
    }

    init(defaults: UserDefaults = .standard) {
        presets = PenPresets.load()
        penStyle = defaults.string(forKey: Keys.penStyle).flatMap(PenStyle.init(rawValue:)) ?? .pen
        eraserKind = defaults.string(forKey: Keys.eraserKind).flatMap(EraserMode.init(rawValue:)) ?? .stroke
        laserMode = defaults.string(forKey: Keys.laserMode).flatMap(LaserMode.init(rawValue:)) ?? .line
        let storedWidth = defaults.double(forKey: Keys.eraserWidth)
        eraserWidth = storedWidth > 0 ? storedWidth : 12
        if let data = defaults.data(forKey: Keys.swatches),
           let stored = try? JSONDecoder().decode([RGBAColor].self, from: data),
           !stored.isEmpty {
            swatches = Array(stored.prefix(Self.swatchCount))
        } else {
            swatches = Self.standardColors
        }
        tool = .pen
    }

    // MARK: - Derived

    var penTool: InkTool { presets.tool(for: penStyle) }
    var highlighterTool: InkTool { presets.highlighter }

    /// The ink tool shown on the canvas and edited by colour and width.
    var inkTool: InkTool {
        let target = tool.drawsInk ? tool : lastInkTool
        return target == .highlighter ? highlighterTool : penTool
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

    /// Three quick widths for whatever the width dots currently change.
    var widthPresets: [Double] {
        if tool == .eraser { return [8, 20, 44] }
        let ink = inkTool
        if ink.isHighlighter { return [12, 24, 40] }
        let base = ink.style.defaultWidth
        return [base * 0.6, base, base * 1.8].map { min(max($0, inkWidthRange.lowerBound), inkWidthRange.upperBound) }
    }

    var currentWidth: Double {
        tool == .eraser ? eraserWidth : inkTool.width
    }

    var inkWidthRange: ClosedRange<Double> {
        inkTool.isHighlighter ? 8...60 : 1...40
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

    /// Changes the colour of the active ink tool. Picking a colour while
    /// erasing or selecting goes back to the last pen, as in other note apps.
    func setColor(_ color: RGBAColor) {
        if !tool.drawsInk { tool = lastInkTool }
        var updated = inkTool
        var newColor = color
        newColor.a = updated.isHighlighter ? Self.highlighterAlpha : 1
        updated.color = newColor
        presets.update(updated)
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
        rememberSwatch(inkTool.color)
        presets.save()
        let defaults = UserDefaults.standard
        defaults.set(penStyle.rawValue, forKey: Keys.penStyle)
        defaults.set(eraserKind.rawValue, forKey: Keys.eraserKind)
        defaults.set(eraserWidth, forKey: Keys.eraserWidth)
        defaults.set(laserMode.rawValue, forKey: Keys.laserMode)
        if let data = try? JSONEncoder().encode(swatches) {
            defaults.set(data, forKey: Keys.swatches)
        }
    }

    /// A custom colour becomes the first swatch; a colour already shown stays put.
    private func rememberSwatch(_ color: RGBAColor) {
        var opaque = color
        opaque.a = 1
        let isShown = swatches.contains {
            abs($0.r - opaque.r) < 0.01 && abs($0.g - opaque.g) < 0.01 && abs($0.b - opaque.b) < 0.01
        }
        guard !isShown else { return }
        swatches.insert(opaque, at: 0)
        swatches = Array(swatches.prefix(Self.swatchCount))
    }
}
