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

    private enum CodingKeys: String, CodingKey {
        case isBold, isItalic, isUnderline, alignment, lineSpacing
    }

    /// Every field has a model default, so a style written by a build that only
    /// knew some of them still reads as a complete style.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isUnderline = try container.decodeIfPresent(Bool.self, forKey: .isUnderline) ?? false
        alignment = try container.decodeIfPresent(Alignment.self, forKey: .alignment) ?? .leading
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 2
    }

    public static let regular = TextStyle()
}
