#if os(iOS)
import UIKit

/// Holds the page's `InkCanvasView` so its ink stays sharp at any zoom.
///
/// The page is zoomed by a scroll view around it, which only stretches what
/// is inside. PencilKit re-renders ink only for its *own* zoom, and setting
/// `contentScaleFactor` does not make it re-render. So the canvas is sized in
/// screen points, given the zoom as its own `zoomScale`, and shrunk back by a
/// transform: the outer zoom and the transform cancel, and each canvas pixel
/// is a screen pixel. Drawing coordinates stay page points.
///
/// The host is the page's size and stays in the page's place among paper,
/// elements and overlays. Past `InkRenderViewport.pixelBudget` the canvas
/// covers only the page on screen plus a margin, and follows scrolling.
/// While a pinch is in progress the last render stretches, as in every
/// zooming app; it is redrawn sharply once the zoom settles.
public final class InkCanvasHost: UIView {
    public let canvas = InkCanvasView()

    /// Off for a second, magnified view of the page (Zoom View): its canvas
    /// fills the host and zooms to its own `viewport`.
    var managesRenderScale = true {
        didSet { if oldValue != managesRenderScale { invalidate() } }
    }

    var pageSize: CGSize = .zero {
        didSet { if oldValue != pageSize { invalidate() } }
    }

    /// The Pencil or a finger is using a tool: the canvas must not move or
    /// re-zoom under it. A change waits for the tool to lift.
    var isToolActive = false {
        didSet {
            if oldValue, !isToolActive, needsUpdateAfterTool {
                updateRendering(settled: true)
            }
        }
    }

    private var rendered: (rect: CGRect, scale: CGFloat)?
    private var needsUpdateAfterTool = false
    private var lastBounds: CGRect = .zero
    private var observations: [NSKeyValueObservation] = []
    private var scrollViews: [Weak] = []
    private var settleWork: DispatchWorkItem?

    private struct Weak {
        weak var view: UIScrollView?
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    override public func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != lastBounds else { return }
        lastBounds = bounds
        invalidate()
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        observeScrollViews()
        invalidate()
    }

    /// Forgets the current render and lays the canvas out again.
    private func invalidate() {
        rendered = nil
        guard managesRenderScale else {
            canvas.transform = .identity
            canvas.frame = bounds
            canvas.renderViewport = nil
            canvas.fitPageIfNeeded()
            return
        }
        updateRendering(settled: true)
    }

    /// Host points per page point, as the canvas fitted the page before.
    private var pageUnit: CGFloat {
        guard pageSize.width > 0, pageSize.height > 0 else { return 1 }
        return min(bounds.width / pageSize.width, bounds.height / pageSize.height)
    }

    /// Moves or re-zooms the canvas when it no longer covers the page on
    /// screen, and, once scrolling has `settled`, when its zoom is stale.
    private func updateRendering(settled: Bool) {
        guard managesRenderScale, pageSize.width > 0, pageSize.height > 0,
              bounds.width > 0, bounds.height > 0
        else { return }
        if isToolActive || canvas.isDrawingInProgress {
            needsUpdateAfterTool = true
            return
        }
        needsUpdateAfterTool = false

        let unit = pageUnit
        guard let window else {
            // Off screen: plain page-sized canvas, as before zoom handling.
            if rendered == nil { apply(rect: CGRect(origin: .zero, size: pageSize), scale: unit) }
            return
        }
        let onScreen = convert(bounds, to: nil)
        let screenPerHost = onScreen.width / bounds.width
        guard screenPerHost.isFinite, screenPerHost > 0 else { return }
        let scale = unit * screenPerHost
        let visible = visibleRect()
        let visiblePage = CGRect(
            x: visible.minX / unit, y: visible.minY / unit,
            width: visible.width / unit, height: visible.height / unit
        )

        if let rendered {
            let covered = InkRenderViewport.covers(rendered.rect, visible: visiblePage, pageSize: pageSize)
            let sameScale = abs(rendered.scale - scale) / scale < 0.02
            if covered, sameScale || !settled { return }
        }
        let rect = InkRenderViewport.rect(
            pageSize: pageSize,
            visible: visiblePage,
            scale: scale,
            displayScale: window.traitCollection.displayScale > 0 ? window.traitCollection.displayScale : 2
        )
        apply(rect: rect, scale: scale)
    }

    /// Places the canvas over `rect` (page points), rendering at `scale`
    /// screen points per page point.
    private func apply(rect: CGRect, scale: CGFloat) {
        rendered = (rect, scale)
        let unit = pageUnit
        let inHost = CGRect(
            x: rect.minX * unit, y: rect.minY * unit,
            width: rect.width * unit, height: rect.height * unit
        )
        // Canvas points per host point: the canvas is laid out in screen points.
        let factor = scale / unit
        canvas.transform = .identity
        var canvasBounds = canvas.bounds
        // Keep the origin: it is the scroll view's content offset.
        canvasBounds.size = CGSize(width: inHost.width * factor, height: inHost.height * factor)
        canvas.bounds = canvasBounds
        canvas.center = CGPoint(x: inHost.midX, y: inHost.midY)
        canvas.transform = CGAffineTransform(scaleX: 1 / factor, y: 1 / factor)
        canvas.renderViewport = rect
        canvas.fitPageIfNeeded()
    }

    /// The part of the host on screen, in host points: the window, cut down
    /// by every scroll view around the page.
    private func visibleRect() -> CGRect {
        guard let window else { return .null }
        var rect = convert(window.bounds, from: window)
        for scroll in scrollViews.compactMap(\.view) {
            rect = rect.intersection(convert(scroll.bounds, from: scroll))
        }
        return rect.intersection(bounds)
    }

    // MARK: Following the scroll views

    /// Brings the canvas up to date after the page view was updated or
    /// moved: a page host can move into another page's scroll view without
    /// leaving the window.
    func refresh() {
        if ancestorScrollViews().map(ObjectIdentifier.init) != scrollViews.compactMap(\.view).map(ObjectIdentifier.init) {
            observeScrollViews()
        }
        updateRendering(settled: true)
    }

    private func ancestorScrollViews() -> [UIScrollView] {
        guard window != nil else { return [] }
        var found: [UIScrollView] = []
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView { found.append(scroll) }
            ancestor = view.superview
        }
        return found
    }

    private func observeScrollViews() {
        observations.forEach { $0.invalidate() }
        observations = []
        settleWork?.cancel()
        let found = ancestorScrollViews()
        scrollViews = found.map { Weak(view: $0) }
        for scroll in found {
            observations.append(scroll.observe(\.contentOffset) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scrollDidChange() }
            })
            observations.append(scroll.observe(\.zoomScale) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scrollDidChange() }
            })
        }
    }

    private func scrollDidChange() {
        updateRendering(settled: false)
        scheduleSettle()
    }

    /// Re-renders at the new zoom once every scroll view around the page has
    /// come to rest.
    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isScrolling {
                    self.scheduleSettle()
                } else {
                    self.updateRendering(settled: true)
                }
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private var isScrolling: Bool {
        scrollViews.contains { entry in
            guard let scroll = entry.view else { return false }
            return scroll.isDragging || scroll.isDecelerating || scroll.isZooming || scroll.isZoomBouncing
        }
    }

    // MARK: Touches

    /// Touches anywhere on the page still reach the canvas, as when it
    /// covered the whole page, even before it catches up with a scroll.
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled,
              canvas.isUserInteractionEnabled, self.point(inside: point, with: event)
        else { return nil }
        if let hit = canvas.hitTest(convert(point, to: canvas), with: event) { return hit }
        return managesRenderScale ? canvas : nil
    }
}
#endif
