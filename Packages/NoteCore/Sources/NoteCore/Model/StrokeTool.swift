import Foundation

/// Which engine drew a stroke and with which ink.
public struct StrokeTool: Codable, Hashable, Sendable {
    /// For example `"pencilkit"` or `"metal"`.
    public var engine: String
    public var inkType: String
    public var color: RGBAColor
    public var width: Double

    public init(engine: String, inkType: String, color: RGBAColor, width: Double) {
        self.engine = engine
        self.inkType = inkType
        self.color = color
        self.width = width
    }
}
