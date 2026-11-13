import Foundation

/// Formatting for a text-box element. It is stored beside the text content so
/// old pages that only have a font name and size still decode.
public struct TextStyle: Codable, Hashable, Sendable {
    public enum Alignment: String, Codable, Hashable, Sendable, CaseIterable {
        case leading
        case center
        case trailing
        case justified
    }

    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderline: Bool
    public var alignment: Alignment
    public var lineSpacing: Double

    public init(
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        alignment: Alignment = .leading,
        lineSpacing: Double = 2
    ) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.alignment = alignment
        self.lineSpacing = lineSpacing
    }

    public static let regular = TextStyle()
}
