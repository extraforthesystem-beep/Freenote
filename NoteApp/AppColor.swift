import InkKit
import NoteCore
import SwiftUI

enum AppColor {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
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
