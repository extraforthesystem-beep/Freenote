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

    /// The `kind` prefix of a template backed by an imported picture. The file
    /// lives in the notebook's assets under its own name, so a page that names
    /// it keeps rendering wherever the notebook is moved.
    public static let customKindPrefix = "custom:"

    /// The asset file this template draws, when it is a custom template.
    /// Nil for every built-in kind.
    public var customAssetName: String? {
        guard kind.hasPrefix(Self.customKindPrefix) else { return nil }
        let name = kind.dropFirst(Self.customKindPrefix.count)
        return name.isEmpty ? nil : String(name)
    }

    /// A template drawn from `assetName` in the notebook's assets, scaled to
    /// fit the page.
    public static func custom(assetName: String) -> PageTemplate {
        PageTemplate(
            kind: customKindPrefix + assetName,
            spacing: 0,
            lineColor: RGBAColor(r: 0.8, g: 0.8, b: 0.8),
            paperColor: .white
        )
    }
}
