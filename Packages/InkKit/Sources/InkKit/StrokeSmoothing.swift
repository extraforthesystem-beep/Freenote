import CoreGraphics
import Foundation
import PencilKit

/// Smooths a freshly drawn stroke's centre line before it is stored.
///
/// Each control point is pulled towards the midpoint of its neighbours, which
/// removes hand tremor without rounding off deliberate corners. The stroke's
/// width, pressure, tilt, opacity, mask, identity and transform are kept, so a
/// smoothed stroke looks like the same pen, only steadier. The first and last
/// points never move: a stroke still starts and ends where the Pencil did.
public enum StrokeSmoothing {
    /// The largest share of the neighbours' midpoint a point moves towards in
    /// one pass, at strength 100.
    static let maximumWeight: Double = 0.4

    /// The number of smoothing passes at a strength. Two passes at the top of
    /// the range steady a shaky line without turning writing into soup.
    static func passes(forAmount amount: Double) -> Int {
        amount > 0.5 ? 2 : 1
    }

    /// `stroke` smoothed at `strength` (0...100), or nil when there is nothing
    /// to do.
    public static func smoothed(_ stroke: PKStroke, strength: Double) -> PKStroke? {
        let amount = min(max(strength, 0), 100) / 100
        let path = stroke.path
        guard amount > 0, path.count >= 3 else { return nil }

        let weight = maximumWeight * amount
        var locations = path.map(\.location)
        for _ in 0..<passes(forAmount: amount) {
            var moved = locations
            for index in 1..<(locations.count - 1) {
                let midpoint = CGPoint(
                    x: (locations[index - 1].x + locations[index + 1].x) / 2,
                    y: (locations[index - 1].y + locations[index + 1].y) / 2
                )
                moved[index] = CGPoint(
                    x: locations[index].x + (midpoint.x - locations[index].x) * weight,
                    y: locations[index].y + (midpoint.y - locations[index].y) * weight
                )
            }
            locations = moved
        }

        var points: [PKStrokePoint] = []
        points.reserveCapacity(path.count)
        for index in 0..<path.count {
            let point = path[index]
            points.append(
                PKStrokePoint(
                    location: locations[index],
                    timeOffset: point.timeOffset,
                    size: point.size,
                    opacity: point.opacity,
                    force: point.force,
                    azimuth: point.azimuth,
                    altitude: point.altitude,
                    secondaryScale: point.secondaryScale,
                    threshold: point.threshold,
                    lateralJitter: point.lateralJitter
                )
            )
        }

        let smoothedPath = PKStrokePath(
            controlPoints: points,
            creationDate: path.creationDate,
            id: path.id
        )
        return PKStroke(
            ink: stroke.ink,
            path: smoothedPath,
            transform: stroke.transform,
            mask: stroke.mask,
            randomSeed: stroke.randomSeed,
            id: stroke.id,
            renderGroupID: stroke.renderGroupID,
            renderState: stroke.renderState
        )
    }
}
