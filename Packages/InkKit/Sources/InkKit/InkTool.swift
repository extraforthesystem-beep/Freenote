import CoreGraphics
import Foundation
import NoteCore
import PencilKit

#if os(iOS)
import UIKit
/// The platform colour PencilKit uses for ink.
public typealias InkPlatformColor = UIColor
#else
import AppKit
/// The platform colour PencilKit uses for ink.
public typealias InkPlatformColor = NSColor
#endif

// MARK: - PenStyle

/// The eight Apple inks, with raw values that are stable on disk.
///
/// The raw value is *not* PencilKit's raw value: PencilKit uses
/// `com.apple.ink.reedcalligraphy`-style strings, which are stored in
/// `StrokeRecord.tool.inkType`. These names are the app's own vocabulary.
public enum PenStyle: String, CaseIterable, Codable, Hashable, Sendable {
    case pen
    case pencil
    case marker
    case monoline
    case fountainPen
    case watercolor
    case crayon
    case reed

    public var inkType: PKInk.InkType {
        switch self {
        case .pen: .pen
        case .pencil: .pencil
        case .marker: .marker
        case .monoline: .monoline
        case .fountainPen: .fountainPen
        case .watercolor: .watercolor
        case .crayon: .crayon
        case .reed: .reed
        }
    }

    public init?(inkType: PKInk.InkType) {
        switch inkType {
        case .pen: self = .pen
        case .pencil: self = .pencil
        case .marker: self = .marker
        case .monoline: self = .monoline
        case .fountainPen: self = .fountainPen
        case .watercolor: self = .watercolor
        case .crayon: self = .crayon
        case .reed: self = .reed
        default: return nil
        }
    }

    /// Apple's own default width for the ink, in points.
    public var defaultWidth: Double {
        Double(inkType.defaultWidth)
    }

    /// The widths PencilKit accepts for this ink, in points.
    public var widthRange: ClosedRange<Double> {
        let range = inkType.validWidthRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }
}

// MARK: - PenLineStyle

/// How a pen's stroke is broken up along its length. The dash is stored as the
/// stroke's mask (see `StrokeDash`), so it stays one stroke on disk.
public enum PenLineStyle: String, CaseIterable, Codable, Hashable, Sendable {
    case solid
    case dashed
    case dotted

    public var displayName: String {
        switch self {
        case .solid: "Solid"
        case .dashed: "Dashed"
        case .dotted: "Dotted"
        }
    }
}

// MARK: - InkTool

/// A pen choice: ink style, sRGB colour and nominal width.
public struct InkTool: Codable, Hashable, Sendable {
    public var style: PenStyle
    public var color: RGBAColor
    public var width: Double
    /// Draws a translucent marker as a highlighter. PencilKit has no
    /// highlighter ink type, so this flag is the app's own vocabulary and is
    /// stored on every stroke.
    public var isHighlighter: Bool
    /// Solid, dashed or dotted. Highlighters are always solid: a translucent
    /// marker is already broken up by what shows through it.
    public var lineStyle: PenLineStyle

    public init(
        _ style: PenStyle,
        color: RGBAColor = .black,
        width: Double? = nil,
        isHighlighter: Bool = false,
        lineStyle: PenLineStyle = .solid
    ) {
        self.style = style
        self.color = color
        self.width = width ?? style.defaultWidth
        self.isHighlighter = isHighlighter
        self.lineStyle = isHighlighter ? .solid : lineStyle
    }

    public static let pen = InkTool(.pen)
    public static let highlighter = InkTool(
        .marker,
        color: RGBAColor(r: 1, g: 0.86, b: 0.2, a: 0.35),
        width: 24,
        isHighlighter: true
    )

    public var inkType: PKInk.InkType { isHighlighter ? .marker : style.inkType }

    /// The widths PencilKit accepts for this tool. A highlighter is a marker,
    /// so it shares the marker's range.
    public var widthRange: ClosedRange<Double> {
        let range = inkType.validWidthRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    /// The PencilKit tool for this pen. A highlighter is a marker with the
    /// stored translucent colour; a normal pen keeps its exact colour.
    public var inkingTool: PKInkingTool {
        PKInkingTool(inkType, color: color.inkColor, width: CGFloat(width))
    }

    private enum CodingKeys: String, CodingKey {
        case style, color, width, isHighlighter, lineStyle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decode(PenStyle.self, forKey: .style)
        color = try container.decode(RGBAColor.self, forKey: .color)
        width = try container.decode(Double.self, forKey: .width)
        // Presets saved before the highlighter existed have no key.
        isHighlighter = try container.decodeIfPresent(Bool.self, forKey: .isHighlighter) ?? false
        // Presets saved before dashed ink existed have no key.
        lineStyle = try container.decodeIfPresent(PenLineStyle.self, forKey: .lineStyle) ?? .solid
        if isHighlighter { lineStyle = .solid }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(color, forKey: .color)
        try container.encode(width, forKey: .width)
        try container.encode(isHighlighter, forKey: .isHighlighter)
        try container.encode(lineStyle, forKey: .lineStyle)
    }
}

// MARK: - Colour conversion

public extension RGBAColor {
    /// Reads a platform colour as sRGB. `nil` when the colour has no RGB
    /// components (a pattern colour); PencilKit stores ink colours as sRGB, so
    /// this only rejects colours PencilKit itself could not hold either.
    init?(srgb color: InkPlatformColor) {
        self.init(cgColor: color.cgColor)
    }

    init?(cgColor: CGColor) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 4
        else { return nil }
        self.init(
            r: Double(components[0]),
            g: Double(components[1]),
            b: Double(components[2]),
            a: Double(components[3])
        )
    }

    /// The colour as a PencilKit ink colour. Always sRGB, so a saved colour is
    /// stable: PencilKit normalises ink colours to sRGB on its own.
    var inkColor: InkPlatformColor {
        #if os(iOS)
        // `UIColor(red:green:blue:alpha:)` is extended sRGB, which does not
        // convert back to exactly the same sRGB components.
        UIColor(cgColor: CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)))
        #else
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        #endif
    }
}
