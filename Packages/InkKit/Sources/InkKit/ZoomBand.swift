import CoreGraphics
import NoteCore

/// The rectangle of a page that Zoom View magnifies, and how it moves.
///
/// Pure geometry in page points, so it is tested without UIKit. The band
/// always has the aspect of the panel's writing area, so the panel shows
/// exactly the band. Magnification is relative to the page fitted to the
/// panel's width: at 2.5× the band is 1/2.5 of the page width.
///
/// Writing moves left to right: `advance()` steps right by 60% of the band,
/// first stopping flush with the right margin, then wraps to the left margin
/// one band lower ("next line"). At the bottom of the page it stays put.
public struct ZoomBand: Equatable, Sendable {
    public static let magnificationRange: ClosedRange<Double> = 1.5...5
    public static let defaultMagnification = 2.5
    /// Left and right writing margins, as a fraction of the page width. The
    /// first line also starts this far from the top.
    public static let marginFraction: CGFloat = 0.05
    /// How far one advance moves, as a fraction of the band width.
    public static let advanceFraction: CGFloat = 0.6
    /// The right part of the band where a finished stroke advances it.
    public static let advanceAreaFraction: CGFloat = 0.2

    public let pageSize: CGSize
    /// The band in page points, always inside the page.
    public private(set) var rect: CGRect

    /// A band of the given magnification for a panel of `panelAspect`
    /// (width / height), at `origin` or, when nil, at the top-left margins.
    public init(pageSize: CGSize, magnification: Double, panelAspect: CGFloat, origin: CGPoint? = nil) {
        self.pageSize = pageSize
        let size = Self.size(pageSize: pageSize, magnification: magnification, panelAspect: panelAspect)
        let margin = pageSize.width * Self.marginFraction
        rect = CGRect(origin: origin ?? CGPoint(x: margin, y: margin), size: size)
        rect.origin = clamped(rect.origin)
    }

    /// The band size for a magnification, clamped to the allowed range and
    /// shrunk (keeping the aspect) when it would not fit the page.
    public static func size(pageSize: CGSize, magnification: Double, panelAspect: CGFloat) -> CGSize {
        guard pageSize.width > 0, pageSize.height > 0, panelAspect > 0, panelAspect.isFinite else {
            return .zero
        }
        let magnification = clampedMagnification(magnification)
        var width = pageSize.width / CGFloat(magnification)
        var height = width / panelAspect
        if height > pageSize.height {
            height = pageSize.height
            width = height * panelAspect
        }
        return CGSize(width: width, height: height)
    }

    public static func clampedMagnification(_ value: Double) -> Double {
        guard value.isFinite else { return defaultMagnification }
        return min(max(value, magnificationRange.lowerBound), magnificationRange.upperBound)
    }

    /// The magnification a band `width` points wide stands for, clamped.
    public static func magnification(forWidth width: CGFloat, pageWidth: CGFloat) -> Double {
        guard width > 0 else { return magnificationRange.upperBound }
        return clampedMagnification(Double(pageWidth / width))
    }

    // MARK: - Moving

    /// The left edge a new line starts at.
    public var lineStartX: CGFloat {
        min(pageSize.width * Self.marginFraction, maxOriginX)
    }

    /// The furthest right the band goes before wrapping: flush with the
    /// right margin, or with the page edge when the band is wider than the
    /// space between the margins.
    public var lineEndX: CGFloat {
        let flush = pageSize.width * (1 - Self.marginFraction) - rect.width
        return min(max(flush, lineStartX), maxOriginX)
    }

    private var maxOriginX: CGFloat { max(0, pageSize.width - rect.width) }
    private var maxOriginY: CGFloat { max(0, pageSize.height - rect.height) }

    /// Moves the band's top-left corner, keeping the band on the page.
    public mutating func move(to origin: CGPoint) {
        rect.origin = clamped(origin)
    }

    /// One step right; at the right margin, the next line. Returns false when
    /// the band could not move (the last line is full).
    @discardableResult
    public mutating func advance() -> Bool {
        if rect.minX >= lineEndX - 0.5 {
            return newLine()
        }
        rect.origin.x = min(rect.minX + rect.width * Self.advanceFraction, lineEndX)
        return true
    }

    /// One step left; at the left margin, the end of the line above.
    @discardableResult
    public mutating func back() -> Bool {
        if rect.minX <= lineStartX + 0.5 {
            guard rect.minY > 0.5 else { return false }
            rect.origin = clamped(CGPoint(x: lineEndX, y: rect.minY - rect.height))
            return true
        }
        rect.origin.x = max(rect.minX - rect.width * Self.advanceFraction, lineStartX)
        return true
    }

    /// The left margin, one band lower. Returns false at the bottom of the
    /// page, where the band stays where it is.
    @discardableResult
    public mutating func newLine() -> Bool {
        guard rect.minY < maxOriginY - 0.5 else { return false }
        rect.origin = clamped(CGPoint(x: lineStartX, y: rect.minY + rect.height))
        return true
    }

    // MARK: - Mapping

    /// Whether a point on the page lies in the band's advance area: its right
    /// fifth, at the band's height.
    public func isInAdvanceArea(_ point: CGPoint) -> Bool {
        let area = CGRect(
            x: rect.maxX - rect.width * Self.advanceAreaFraction,
            y: rect.minY,
            width: rect.width * Self.advanceAreaFraction,
            height: rect.height
        )
        return area.contains(point)
    }

    /// Screen points per page point in a panel `panelWidth` wide.
    public func scale(panelWidth: CGFloat) -> CGFloat {
        rect.width > 0 ? panelWidth / rect.width : 1
    }

    public func panelPoint(fromPage point: CGPoint, panelWidth: CGFloat) -> CGPoint {
        let scale = scale(panelWidth: panelWidth)
        return CGPoint(x: (point.x - rect.minX) * scale, y: (point.y - rect.minY) * scale)
    }

    public func pagePoint(fromPanel point: CGPoint, panelWidth: CGFloat) -> CGPoint {
        let scale = scale(panelWidth: panelWidth)
        return CGPoint(x: rect.minX + point.x / scale, y: rect.minY + point.y / scale)
    }

    /// Where a stroke ended on the page: its last point through its transform.
    public static func endPoint(of record: StrokeRecord) -> CGPoint? {
        guard let last = record.points.last else { return nil }
        let t = record.transform.count == StrokeRecord.transformElementCount
            ? record.transform
            : StrokeRecord.identityTransform
        return CGPoint(
            x: t[0] * last.x + t[2] * last.y + t[4],
            y: t[1] * last.x + t[3] * last.y + t[5]
        )
    }

    private func clamped(_ origin: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, 0), maxOriginX),
            y: min(max(origin.y, 0), maxOriginY)
        )
    }
}
