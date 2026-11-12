import Foundation

/// One sample of a stroke: position, timing and the stylus state at that sample.
public struct StrokePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    /// Seconds since the stroke's `createdAt`.
    public var timeOffset: Double
    public var width: Double
    public var height: Double
    public var opacity: Double
    public var force: Double
    public var azimuth: Double
    public var altitude: Double
    public var secondaryScale: Double

    public init(
        x: Double,
        y: Double,
        timeOffset: Double,
        width: Double,
        height: Double,
        opacity: Double,
        force: Double,
        azimuth: Double,
        altitude: Double,
        secondaryScale: Double
    ) {
        self.x = x
        self.y = y
        self.timeOffset = timeOffset
        self.width = width
        self.height = height
        self.opacity = opacity
        self.force = force
        self.azimuth = azimuth
        self.altitude = altitude
        self.secondaryScale = secondaryScale
    }
}
