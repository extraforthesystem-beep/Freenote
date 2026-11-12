import InkKit
import NoteCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The app's appearance choice, stored in the settings. System follows the
/// device.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` follows the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The app's chrome colours. Everything that is not paper goes through the
/// system's semantic colours (or a dynamic provider here), so it follows the
/// appearance; paper keeps its own tokens because it does not.
enum AppColor {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// A notebook page's paper. Pages stay white whatever the appearance,
    /// like paper on a desk; Dark Paper is the opt-in exception.
    static func paper(usesDarkPaper: Bool) -> Color {
        usesDarkPaper ? Color(PaperAppearance.darkPaper) : .white
    }

    /// Text printed on the paper, such as the page number. It reads against
    /// the paper, so it cannot use the interface's label colour: in dark mode
    /// that would be light text on white paper.
    static func pageAnnotation(usesDarkPaper: Bool) -> Color {
        usesDarkPaper ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
    }

    /// The ring around an ink colour dot. It is light on dark chrome so a
    /// black swatch still has an edge, and dark on light chrome.
    static var swatchOutline: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.32)
                : UIColor(white: 0, alpha: 0.20)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.32)
                : NSColor(white: 0, alpha: 0.20)
        })
        #endif
    }
}

extension Color {
    init(_ color: RGBAColor) {
        self.init(red: color.r, green: color.g, blue: color.b, opacity: color.a)
    }
}

extension RGBAColor {
    init(_ color: Color) {
        #if os(iOS)
        let resolved = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))
        #else
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            r: Double(resolved.redComponent),
            g: Double(resolved.greenComponent),
            b: Double(resolved.blueComponent),
            a: Double(resolved.alphaComponent)
        )
        #endif
    }
}

extension PenStyle {
    /// The toolbar label. `PenStyle` itself has no UI.
    var displayName: String {
        switch self {
        case .pen: "Pen"
        case .pencil: "Pencil"
        case .marker: "Marker"
        case .monoline: "Monoline"
        case .fountainPen: "Fountain Pen"
        case .watercolor: "Watercolour"
        case .crayon: "Crayon"
        case .reed: "Reed"
        }
    }

    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        // "highlighter" is kept for the highlighter tool so the two never look alike.
        case .marker: "scribble.variable"
        case .monoline: "pencil.line"
        case .fountainPen: "pencil.and.scribble"
        case .watercolor: "paintbrush.pointed"
        case .crayon: "scribble"
        case .reed: "paintbrush"
        }
    }
}
