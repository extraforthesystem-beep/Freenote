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
}
