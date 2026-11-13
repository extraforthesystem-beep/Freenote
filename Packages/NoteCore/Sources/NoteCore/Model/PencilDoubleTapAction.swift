import Foundation

/// What a double-tap on the side of the Apple Pencil does in the editor.
///
/// The stored raw values are stable on disk. `system` follows the user's
/// Apple Pencil preference; the canvas resolves it before calling the app.
public enum PencilDoubleTapAction: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    /// Follow `UIPencilInteraction.preferredTapAction`.
    case system
    case eraser
    case previousTool
    case colorPalette
    case off

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "System Default"
        case .eraser: "Switch to Eraser"
        case .previousTool: "Switch to Previous Tool"
        case .colorPalette: "Show Colour Palette"
        case .off: "Off"
        }
    }
}
