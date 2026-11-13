import Foundation

/// Placement of a page element: an axis-aligned box in page points, rotated about its centre.
public struct ElementFrame: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Radians, clockwise, about the centre of the box.
    public var rotation: Double

    public init(x: Double, y: Double, width: Double, height: Double, rotation: Double = 0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, width, height, rotation
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
    }
}
