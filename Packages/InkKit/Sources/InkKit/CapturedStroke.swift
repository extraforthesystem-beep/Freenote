import CoreGraphics
import Foundation
import PencilKit

/// One touch sample taken outside a live canvas, in page points.
///
/// The paged notebook catches the first stroke on a page whose canvas is
/// still loading as samples, then turns them into a `PKStroke` once the
/// canvas is there (see `ContinuousPagesView.swift`).
public struct CapturedInkSample: Hashable, Sendable {
    public var location: CGPoint
    /// Seconds, on the touch clock (`UITouch.timestamp`).
    public var time: TimeInterval
    /// The touch's raw force; 0 when the device reports none.
    public var force: CGFloat
    /// Force as a fraction of the device maximum (0...1), or `nil` when the
    /// touch has no pressure (a finger on most iPads).
    public var pressure: CGFloat?
    public var altitude: CGFloat
    public var azimuth: CGFloat

    public init(
        location: CGPoint,
        time: TimeInterval,
        force: CGFloat = 0,
        pressure: CGFloat? = nil,
        altitude: CGFloat = .pi / 2,
        azimuth: CGFloat = 0
    ) {
        self.location = location
        self.time = time
        self.force = force
        self.pressure = pressure
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// Turns captured samples into a stroke drawn with an `InkTool`.
public enum CapturedStrokeBuilder {
    /// The width of one point: pressure-sensitive inks go from half to one
    /// and a half times the nominal width, with a medium press drawing the
    /// nominal width. Monoline, markers and highlighters keep an even width,
    /// as do touches without pressure.
    public static func width(for tool: InkTool, pressure: CGFloat?) -> CGFloat {
        let nominal = CGFloat(max(tool.width, 0.1))
        guard let pressure, respondsToPressure(tool) else { return nominal }
        let clamped = min(max(pressure, 0), 1)
        return nominal * (0.5 + clamped)
    }

    static func respondsToPressure(_ tool: InkTool) -> Bool {
        if tool.isHighlighter { return false }
        switch tool.style {
        case .monoline, .marker: return false
        case .pen, .pencil, .fountainPen, .watercolor, .crayon, .reed: return true
        }
    }

    /// The stroke for `samples`, or `nil` when there are none.
    ///
    /// `PKStrokePath` is a cubic B-spline over its points, which would pull
    /// the ends inwards; the first and last points are repeated so the stroke
    /// starts and ends where the touch did. A single sample (a dot) becomes a
    /// stroke with its own end points.
    public static func stroke(from samples: [CapturedInkSample], tool: InkTool) -> PKStroke? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let points = samples.map { point(for: $0, start: first.time, tool: tool) }
        let startPoint = points[0]
        let endPoint = point(for: last, start: first.time, tool: tool)
        let controlPoints = [startPoint, startPoint] + points + [endPoint, endPoint]
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        let ink = PKInk(tool.inkType, color: tool.color.inkColor)
        return PKStroke(ink: ink, path: path)
    }

    static func point(for sample: CapturedInkSample, start: TimeInterval, tool: InkTool) -> PKStrokePoint {
        let width = width(for: tool, pressure: sample.pressure)
        return PKStrokePoint(
            location: sample.location,
            timeOffset: max(sample.time - start, 0),
            size: CGSize(width: width, height: width),
            opacity: 1,
            force: max(sample.force, 0),
            azimuth: sample.azimuth,
            altitude: sample.altitude
        )
    }
}
