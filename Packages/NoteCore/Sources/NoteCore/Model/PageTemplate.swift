import Foundation

/// The printed background of a page.
public struct PageTemplate: Codable, Hashable, Sendable {
    /// For example `"blank"`, `"ruled"`, `"grid"` or `"dotted"`.
    public var kind: String
    /// Distance between rules or grid lines, in page points.
    public var spacing: Double
    public var lineColor: RGBAColor
    public var paperColor: RGBAColor

    public init(kind: String, spacing: Double, lineColor: RGBAColor, paperColor: RGBAColor) {
        self.kind = kind
        self.spacing = spacing
        self.lineColor = lineColor
        self.paperColor = paperColor
    }

    public static let blank = PageTemplate(
        kind: "blank",
        spacing: 0,
        lineColor: RGBAColor(r: 0.8, g: 0.8, b: 0.8),
        paperColor: .white
    )
}
