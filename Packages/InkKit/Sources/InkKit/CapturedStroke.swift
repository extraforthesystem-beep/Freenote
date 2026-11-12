import CoreGraphics
import Foundation
import PencilKit

/// One touch sample of a stroke drawn where no live canvas was listening
/// (a page that was not active yet), in page points.
public struct InkSample: Hashable, Sendable {
    public var location: CGPoint
    /// The touch timestamp, in seconds (any epoch; only differences matter).
    public var timestamp: TimeInterval
    /// `UITouch.force`, where 1 is an average touch. `nil` when the input
    /// reports no force (a finger without force sensing, a mouse).
    public var force: CGFloat?
    /// Radians from the page plane; π/2 is upright.
    public var altitude: CGFloat
    /// Radians in page coordinates.
    public var azimuth: CGFloat

    public init(
        location: CGPoint,
        timestamp: TimeInterval,
        force: CGFloat? = nil,
        altitude: CGFloat = .pi / 2,
        azimuth: CGFloat = 0
    ) {
        self.location = location
        self.timestamp = timestamp
        self.force = force
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// Turns captured touch samples into a PencilKit stroke, so ink drawn before
/// the page's canvas was ready can be added to it afterwards.
///
/// The widths approximate PencilKit's own: pressure-sensitive inks swell and
/// thin around the nominal width with force, uniform inks keep it.
public enum CapturedStroke {
    /// Inks whose width follows pressure.
    public static func isPressureSensitive(_ inkType: PKInk.InkType) -> Bool {
        switch inkType {
        case .pen, .fountainPen, .watercolor, .crayon, .reed: true
        default: false
        }
    }

    /// The point diameter for a sample: the nominal `width` at an average
    /// force (or with no force at all), between half and one and a half
    /// times it at the extremes.
    public static func pointWidth(nominal width: CGFloat, force: CGFloat?, inkType: PKInk.InkType) -> CGFloat {
        guard let force, isPressureSensitive(inkType) else { return width }
        let scale = min(max(0.75 + 0.25 * force, 0.5), 1.5)
        return width * scale
    }

    /// Stroke points for the samples, with time offsets from the first one.
    public static func strokePoints(
        from samples: [InkSample],
        width: CGFloat,
        inkType: PKInk.InkType
    ) -> [PKStrokePoint] {
        guard let start = samples.first?.timestamp else { return [] }
        var lastOffset: TimeInterval = 0
        return samples.map { sample in
            // Coalesced touches can arrive with equal stamps; never go back.
            let offset = max(sample.timestamp - start, lastOffset)
            lastOffset = offset
            let diameter = pointWidth(nominal: width, force: sample.force, inkType: inkType)
            return PKStrokePoint(
                location: sample.location,
                timeOffset: offset,
                size: CGSize(width: diameter, height: diameter),
                opacity: 1,
                force: sample.force ?? 1,
                azimuth: sample.azimuth,
                altitude: sample.altitude
            )
        }
    }

    /// The stroke for the samples drawn with `ink` at nominal `width`, or
    /// `nil` when there are no samples.
    public static func stroke(
        from samples: [InkSample],
        ink: PKInk,
        width: CGFloat,
        creationDate: Date = Date()
    ) -> PKStroke? {
        let points = strokePoints(from: samples, width: width, inkType: ink.inkType)
        guard !points.isEmpty else { return nil }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: creationDate))
    }
}
