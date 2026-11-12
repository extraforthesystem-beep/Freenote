import CoreGraphics
import Foundation

/// The rectangle of a page that Zoom View magnifies, in page points.
///
/// Pure geometry: where the band starts, how it moves when writing reaches
/// the advance area, how it wraps to the next line, and how it stays on the
/// page. The panel shows the band scaled to its own width, so the band's
/// aspect ratio always matches the panel's (`aspect` = height / width).
public struct ZoomBand: Hashable, Sendable {
    public static let minimumMagnification: Double = 1.5
    public static let maximumMagnification: Double = 5
    public static let defaultMagnification: Double = 2.5
    /// Left and right margin, and the top start position, as a fraction of
    /// the page width.
    public static let marginFraction: Double = 0.05
    /// How far one advance moves the band, as a fraction of its width.
    public static let advanceFraction: Double = 0.6
    /// The right part of the band where a finished stroke moves it on.
    public static let advanceAreaFraction: Double = 0.2

    public private(set) var pageSize: CGSize
    public private(set) var rect: CGRect

    /// A band at the top-left margin of the page.
    public init(pageSize: CGSize, magnification: Double, aspect: Double) {
        self.pageSize = pageSize
        let width = Self.width(for: magnification, pageWidth: pageSize.width)
        let margin = pageSize.width * Self.marginFraction
        rect = CGRect(x: margin, y: margin, width: width, height: width * Self.sane(aspect))
        clamp()
    }

    /// Page width over band width: how much bigger the band looks than the
    /// page at the same on-screen width.
    public var magnification: Double {
        rect.width > 0 ? pageSize.width / rect.width : Self.defaultMagnification
    }

    public var leftMargin: Double { pageSize.width * Self.marginFraction }
    public var rightMargin: Double { pageSize.width * (1 - Self.marginFraction) }

    /// The advance area in page points: the right part of the band.
    public var advanceArea: CGRect {
        let width = rect.width * Self.advanceAreaFraction
        return CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height)
    }

    /// Whether a stroke that ended at `point` (page points) should move the band on.
    public func isInAdvanceArea(_ point: CGPoint) -> Bool {
        point.x >= advanceArea.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// Scale from page points to panel points for a panel `panelWidth` wide.
    public func panelScale(panelWidth: Double) -> Double {
        rect.width > 0 ? panelWidth / rect.width : 1
    }

    /// A page point seen in a panel `panelWidth` wide.
    public func panelPoint(fromPage point: CGPoint, panelWidth: Double) -> CGPoint {
        let scale = panelScale(panelWidth: panelWidth)
        return CGPoint(x: (point.x - rect.minX) * scale, y: (point.y - rect.minY) * scale)
    }

    /// A panel point mapped back onto the page.
    public func pagePoint(fromPanel point: CGPoint, panelWidth: Double) -> CGPoint {
        let scale = panelScale(panelWidth: panelWidth)
        return CGPoint(x: rect.minX + point.x / scale, y: rect.minY + point.y / scale)
    }

    // MARK: - Moving

    /// Moves right by `advanceFraction` of the width, stopping at the right
    /// margin; a band already at the right margin starts the next line.
    public mutating func advance() {
        let limit = max(rightMargin, rect.width + leftMargin)
        if rect.maxX >= limit - 0.5 {
            newLine()
            return
        }
        rect.origin.x = min(rect.minX + rect.width * Self.advanceFraction, limit - rect.width)
        clamp()
    }

    /// Moves left by `advanceFraction` of the width, stopping at the page edge.
    public mutating func moveBack() {
        rect.origin.x -= rect.width * Self.advanceFraction
        clamp()
    }

    /// Back to the left margin, one band height down. At the bottom of the
    /// page the band stays at the bottom.
    public mutating func newLine() {
        rect.origin.x = leftMargin
        rect.origin.y += rect.height
        clamp()
    }

    /// Places the band's top-left corner, kept on the page.
    public mutating func move(to origin: CGPoint) {
        rect.origin = origin
        clamp()
    }

    /// Changes the magnification, keeping the top-left corner.
    public mutating func setMagnification(_ magnification: Double) {
        let width = Self.width(for: magnification, pageWidth: pageSize.width)
        let aspect = rect.width > 0 ? rect.height / rect.width : 0.35
        rect.size = CGSize(width: width, height: width * aspect)
        clamp()
    }

    /// Resizes from the bottom-right corner to `width`, keeping the aspect.
    public mutating func resize(toWidth width: Double) {
        setMagnification(width > 0 ? pageSize.width / width : Self.maximumMagnification)
    }

    /// The panel changed shape: keep the width, follow its aspect.
    public mutating func setAspect(_ aspect: Double) {
        rect.size.height = rect.width * Self.sane(aspect)
        clamp()
    }

    /// Where a stroke ended on the page: its last point through its transform.
    public static func endPoint(of stroke: StrokeRecord) -> CGPoint? {
        guard let last = stroke.points.last else { return nil }
        let t = stroke.transform.count == StrokeRecord.transformElementCount
            ? stroke.transform : StrokeRecord.identityTransform
        return CGPoint(
            x: t[0] * last.x + t[2] * last.y + t[4],
            y: t[1] * last.x + t[3] * last.y + t[5]
        )
    }

    // MARK: - Helpers

    public static func clampedMagnification(_ value: Double) -> Double {
        guard value.isFinite else { return defaultMagnification }
        return min(max(value, minimumMagnification), maximumMagnification)
    }

    private static func width(for magnification: Double, pageWidth: Double) -> Double {
        pageWidth / clampedMagnification(magnification)
    }

    private static func sane(_ aspect: Double) -> Double {
        guard aspect.isFinite, aspect > 0 else { return 0.35 }
        return min(aspect, 4)
    }

    /// Keeps the band on the page; a band taller than the page sits at the top.
    private mutating func clamp() {
        let maxX = max(0, pageSize.width - rect.width)
        let maxY = max(0, pageSize.height - rect.height)
        rect.origin.x = min(max(rect.origin.x, 0), maxX)
        rect.origin.y = min(max(rect.origin.y, 0), maxY)
    }
}
