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
}

// MARK: - InkTool

/// A pen choice: ink style, sRGB colour and nominal width.
public struct InkTool: Codable, Hashable, Sendable {
    public var style: PenStyle
    public var color: RGBAColor
    public var width: Double

    public init(_ style: PenStyle, color: RGBAColor = .black, width: Double? = nil) {
        self.style = style
        self.color = color
        self.width = width ?? style.defaultWidth
    }

    public static let pen = InkTool(.pen)

    public var inkType: PKInk.InkType { style.inkType }

    /// The PencilKit tool for this pen.
    public var inkingTool: PKInkingTool {
        PKInkingTool(style.inkType, color: color.inkColor, width: CGFloat(width))
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
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        #else
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        #endif
    }
}
