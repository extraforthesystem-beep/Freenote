import Foundation

/// Which engine drew a stroke and with which ink.
public struct StrokeTool: Codable, Hashable, Sendable {
    /// For example `"pencilkit"` or `"metal"`.
    public var engine: String
    public var inkType: String
    public var color: RGBAColor
    public var width: Double
    /// True for a translucent marker stroke drawn as a highlighter. It is
    /// stored separately from `inkType` because PencilKit has no highlighter
    /// ink type; the stroke is a marker underneath.
    public var isHighlighter: Bool

    public init(
        engine: String,
        inkType: String,
        color: RGBAColor,
        width: Double,
        isHighlighter: Bool = false
    ) {
        self.engine = engine
        self.inkType = inkType
        self.color = color
        self.width = width
        self.isHighlighter = isHighlighter
    }

    private enum CodingKeys: String, CodingKey {
        case engine, inkType, color, width, isHighlighter
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engine = try container.decode(String.self, forKey: .engine)
        inkType = try container.decode(String.self, forKey: .inkType)
        color = try container.decode(RGBAColor.self, forKey: .color)
        width = try container.decode(Double.self, forKey: .width)
        // Files written before the highlighter tool existed have no key.
        isHighlighter = try container.decodeIfPresent(Bool.self, forKey: .isHighlighter) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(engine, forKey: .engine)
        try container.encode(inkType, forKey: .inkType)
        try container.encode(color, forKey: .color)
        try container.encode(width, forKey: .width)
        try container.encode(isHighlighter, forKey: .isHighlighter)
    }
}
