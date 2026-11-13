import CoreGraphics

/// Which part of a page the live canvas renders, at the zoom it is seen at.
///
/// PencilKit draws ink sharply only at its own zoom scale. A page zoomed by
/// an outer scroll view stretches the canvas's bitmap instead, so the canvas
/// is given the zoom itself (see `InkCanvasHost`). Rendering a whole page at
/// 8× would need hundreds of megabytes, so past a pixel budget the canvas
/// covers only the part of the page on screen plus a margin.
public enum InkRenderViewport {
    /// Pixels the canvas may cover: about 48 MB of tiles.
    public static let pixelBudget: CGFloat = 12_000_000
    /// Extra page kept rendered on each side of the visible part, as a
    /// fraction of its size, so a short pan shows sharp ink straight away.
    public static let margin: CGFloat = 0.25

    /// The page rect (page points) the canvas should render.
    ///
    /// - Parameters:
    ///   - pageSize: The page, in page points.
    ///   - visible: The part of the page on screen, in page points. It may
    ///     reach past the page, or miss it, while the page scrolls away.
    ///   - scale: Screen points per page point.
    ///   - displayScale: Pixels per screen point.
    public static func rect(
        pageSize: CGSize,
        visible: CGRect,
        scale: CGFloat,
        displayScale: CGFloat,
        budget: CGFloat = pixelBudget,
        margin: CGFloat = margin
    ) -> CGRect {
        let page = CGRect(origin: .zero, size: pageSize)
        guard page.width > 0, page.height > 0 else { return page }
        let density = max(scale * displayScale, 0.0001)
        let maxArea = budget / (density * density)
        if page.width * page.height <= maxArea { return page }

        var seen = visible.intersection(page)
        if seen.isNull || seen.width < 1 || seen.height < 1 {
            seen = nearestPiece(of: page, to: visible)
        }
        let seenArea = seen.width * seen.height
        guard seenArea < maxArea else { return seen.integral.intersection(page) }

        // Grow by the margin, or by as much of it as the budget allows.
        let growth = min(margin, (sqrt(maxArea / seenArea) - 1) / 2)
        let grown = seen.insetBy(dx: -seen.width * growth, dy: -seen.height * growth)
        return grown.integral.intersection(page)
    }

    /// Whether `rendered` still holds every part of the page on screen.
    public static func covers(_ rendered: CGRect, visible: CGRect, pageSize: CGSize) -> Bool {
        let seen = visible.intersection(CGRect(origin: .zero, size: pageSize))
        if seen.isNull || seen.width < 1 || seen.height < 1 { return true }
        return rendered.insetBy(dx: -0.5, dy: -0.5).contains(seen)
    }

    /// A piece of the page as large as `visible` (or the page), nearest to it.
    private static func nearestPiece(of page: CGRect, to visible: CGRect) -> CGRect {
        guard !visible.isNull, visible.width > 0, visible.height > 0 else {
            return CGRect(x: 0, y: 0, width: min(page.width, 512), height: min(page.height, 512))
        }
        let width = min(visible.width, page.width)
        let height = min(visible.height, page.height)
        let x = min(max(visible.midX - width / 2, 0), page.width - width)
        let y = min(max(visible.midY - height / 2, 0), page.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
