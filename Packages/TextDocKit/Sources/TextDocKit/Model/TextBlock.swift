import Foundation

/// A straight-alpha sRGB colour used by a text style override.
public struct TextColor: Codable, Hashable, Sendable {
    /// Red component in the range 0...1.
    public var red: Double
    /// Green component in the range 0...1.
    public var green: Double
    /// Blue component in the range 0...1.
    public var blue: Double
    /// Alpha component in the range 0...1.
    public var alpha: Double

    /// Creates a colour from straight sRGB components.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Opaque black.
    public static let black = TextColor(red: 0, green: 0, blue: 0)
    /// Opaque white.
    public static let white = TextColor(red: 1, green: 1, blue: 1)
}

/// Horizontal alignment for a block's text. Named to avoid colliding with
/// SwiftUI's `TextAlignment` in an app target.
public enum TextBlockAlignment: String, Codable, Hashable, Sendable, CaseIterable {
    /// Align to the leading edge.
    case leading
    /// Center on the line.
    case center
    /// Align to the trailing edge.
    case trailing
    /// Justify both edges.
    case justified
}

/// Per-block style overrides. A `nil` property means "inherit the document default".
public struct TextStyle: Codable, Hashable, Sendable {
    /// Bold override.
    public var isBold: Bool?
    /// Italic override.
    public var isItalic: Bool?
    /// Underline override.
    public var isUnderline: Bool?
    /// Text colour override.
    public var color: TextColor?
    /// Horizontal alignment override.
    public var alignment: TextBlockAlignment?
    /// Font size in points.
    public var fontSize: Double?

    /// Creates an override set; every property defaults to inheriting.
    public init(
        isBold: Bool? = nil,
        isItalic: Bool? = nil,
        isUnderline: Bool? = nil,
        color: TextColor? = nil,
        alignment: TextBlockAlignment? = nil,
        fontSize: Double? = nil
    ) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.color = color
        self.alignment = alignment
        self.fontSize = fontSize
    }
}

/// The content of a block. The enum cases are the supported document vocabulary.
public enum TextBlockKind: Codable, Hashable, Sendable {
    /// A heading with a level in the range 1...6; values outside it are kept but
    /// clamped when exported to Markdown.
    case heading(level: Int, text: String)
    /// A paragraph of running text; newlines inside `text` are preserved.
    case paragraph(text: String)
    /// An unordered list.
    case bulletList(items: [String])
    /// An ordered list; numbering is implicit in item order.
    case numberedList(items: [String])
    /// A block quotation; newlines inside `text` are preserved.
    case quote(text: String)
    /// A code block with an optional language identifier.
    case code(text: String, language: String?)
    /// A referenced image. `width` is in points; the layout caller supplies the height.
    case image(assetName: String, width: Double)
    /// A horizontal rule.
    case divider
    /// A checklist with independently checked items.
    case checklist(items: [ChecklistItem])
}

/// A stable, string-backed tag for a block kind, useful for layout and rendering
/// without switching over associated values.
public enum TextBlockKindTag: String, Codable, Hashable, Sendable, CaseIterable {
    /// A heading.
    case heading
    /// A paragraph.
    case paragraph
    /// An unordered list.
    case bulletList
    /// An ordered list.
    case numberedList
    /// A block quotation.
    case quote
    /// A fenced code block.
    case code
    /// An image.
    case image
    /// A horizontal rule.
    case divider
    /// A checklist.
    case checklist
}

extension TextBlockKind {
    /// The tag for this kind.
    public var tag: TextBlockKindTag {
        switch self {
        case .heading: .heading
        case .paragraph: .paragraph
        case .bulletList: .bulletList
        case .numberedList: .numberedList
        case .quote: .quote
        case .code: .code
        case .image: .image
        case .divider: .divider
        case .checklist: .checklist
        }
    }

    /// The plain text content of the block, without list markers or checkbox glyphs.
    /// Images and dividers have no text.
    public var text: String {
        switch self {
        case let .heading(_, text): text
        case let .paragraph(text): text
        case let .bulletList(items): items.joined(separator: "\n")
        case let .numberedList(items): items.joined(separator: "\n")
        case let .quote(text): text
        case let .code(text, _): text
        case .image, .divider: ""
        case let .checklist(items): items.map(\.text).joined(separator: "\n")
        }
    }
}

/// One reflowable block of a text document.
public struct TextBlock: Codable, Hashable, Identifiable, Sendable {
    /// Stable identity, preserved across saves, edits and moves.
    public var id: UUID
    /// The block's content.
    public var kind: TextBlockKind
    /// Optional overrides layered over the document default style.
    public var style: TextStyle?

    /// Creates a block with a fresh identity unless one is supplied.
    public init(id: UUID = UUID(), kind: TextBlockKind, style: TextStyle? = nil) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    /// The tag for this block's kind.
    public var tag: TextBlockKindTag { kind.tag }

    /// The plain text content of the block, without list markers or checkbox glyphs.
    public var text: String { kind.text }
}
