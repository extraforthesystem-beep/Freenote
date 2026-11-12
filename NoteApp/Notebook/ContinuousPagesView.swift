#if os(iOS)
import InkKit
import NoteCore
import PencilKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - Design
//
// `PagedNotebookView` shows every page of a notebook in one UIKit scroll
// container, in one of two modes:
//
// - Vertical (seamless): one `UIScrollView` zooms a single "stack" view that
//   holds the pages top to bottom with a 16 pt gap. Zoom applies to the whole
//   stack, so pages keep their positions relative to each other. Fit is
//   fit-to-width.
// - Horizontal (single page): a paging `UIScrollView` with one cell per page;
//   each cell is a `PageScrollView` (the same zoom view the single page used),
//   so zoom belongs to the page and a zoomed page pans to its edge before the
//   outer scroll view pages (UIKit's nested scroll hand-off).
//
// Each page is a `PageSlotView` (white paper with a shadow) in page points.
// Only the active page (`session.page`) hosts the live SwiftUI page content
// (paper, PencilKit canvas, elements, laser, tape) through one
// `UIHostingController`, whose view moves into the active slot. Other slots
// show an image rendered off the main actor with `PageRenderer`, cached in
// `PageImageCache` by notebook token + page id at a scale that follows the
// settled zoom.
//
// Slots are created lazily for the pages near the viewport (plus the active
// page) and dropped as they scroll away, so a 300-page notebook only has a
// handful of views. Page sizes are learned as pages are read; unread pages are
// assumed to match the first page seen, and a size that turns out different
// re-lays the stack out around the page in the middle of the screen.
//
// The active page changes when a user scroll or zoom settles (the page nearest
// the viewport centre, or the one shown in horizontal mode), or when a Pencil
// or finger tap lands on another page; that calls `session.goToPage`, which
// commits the pending save first. A page change from elsewhere (thumbnails,
// page pill, Go To Page, add/delete) scrolls to the new page instead.
//
// First stroke on another page: the live canvas only reaches a page once
// `goToPage` has loaded it, so a Pencil that lands on an inactive page would
// lose the stroke it starts. The slot catches it instead (capture and replay):
// its `InkCaptureRecognizer` records the touch samples in page points (with
// force, altitude and azimuth) and draws them as a plain `CAShapeLayer`
// preview while the page activates. Once the new page's canvas is on screen
// in that slot, each captured stroke becomes a `PKStroke`
// (`CapturedStrokeBuilder`, with the pen or highlighter chosen at touch-down)
// and is appended through `PencilCanvasController.appendStroke`: one undo step
// on that page's canvas, reported through `onStrokesChanged` like any drawn
// stroke, so it lands on the page's active layer and is saved. A Pencil still
// down when the canvas arrives keeps being captured until it lifts. Strokes
// written before the canvas arrives queue up in order. Only the pen and the
// highlighter are replayed; an eraser, the lasso or link taps just activate
// the page. Fingers are captured only when Draw with Finger is on (always in
// the simulator, like the canvas). A stroke whose page never becomes active
// (another page was touched straight after) or that a locked layer refuses is
// dropped after a few seconds, with its preview.
//
// Alternatives weighed: activating pages earlier while scrolling helps only
// sometimes and still loses the stroke when it doesn't; a live canvas on every
// visible page costs a PencilKit canvas (and its undo stack and tile memory)
// per page, which a base iPad cannot spare at high zoom. The capture works the
// same in both scroll modes, so a Pencil straight after a page turn in
// horizontal mode is covered too.

/// What a stroke on a page that is still loading becomes.
struct InkCapture {
    /// The pen or highlighter in use; `nil` when the Pencil does not ink
    /// (eraser, lasso, read only), so a touch only activates the page.
    let tool: InkTool?
    /// Finger touches ink as well (Draw with Finger).
    let drawsWithFinger: Bool
    /// Drives the live canvas that receives the replayed stroke.
    let canvas: PencilCanvasController
}

/// Where the inactive pages' images come from.
struct PageImageSource {
    let notebookID: UUID
    let store: LibraryStore
    let assetsDirectory: URL?
    /// Changes when pages other than the active one were rewritten in bulk.
    let token: UUID
}

struct PagedNotebookView<Content: View>: UIViewRepresentable {
    let mode: PageScrollMode
    let pageOrder: [UUID]
    let activePage: Page
    let source: PageImageSource
    let controller: PageZoomController
    /// Empty space kept beside the page(s) when fitted.
    let fitMargin: CGFloat
    /// Fingers needed to scroll, zoom-pan or page. The Pencil never scrolls.
    let panTouches: Int
    let inkCapture: InkCapture
    let onActivate: @MainActor (Int) async -> Void
    let content: Content

    init(
        mode: PageScrollMode,
        pageOrder: [UUID],
        activePage: Page,
        source: PageImageSource,
        controller: PageZoomController,
        fitMargin: CGFloat,
        panTouches: Int,
        inkCapture: InkCapture,
        onActivate: @escaping @MainActor (Int) async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.mode = mode
        self.pageOrder = pageOrder
        self.activePage = activePage
        self.source = source
        self.controller = controller
        self.fitMargin = fitMargin
        self.panTouches = panTouches
        self.inkCapture = inkCapture
        self.onActivate = onActivate
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PagesView {
        let view: PagesView = mode == .vertical ? VerticalPagesView() : HorizontalPagesView()
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.host = host
        view.hostView = host.view
        view.controller = controller
        apply(to: view)
        return view
    }

    func updateUIView(_ view: PagesView, context: Context) {
        // Before the new content goes in, so a page being left can still be
        // snapshotted as it looks.
        apply(to: view)
        context.coordinator.host?.rootView = content
    }

    private func apply(to view: PagesView) {
        view.fitMargin = fitMargin
        view.panTouches = panTouches
        view.inkCapture = inkCapture
        view.onActivate = onActivate
        view.update(pageOrder: pageOrder, activePage: activePage, source: source)
    }

    @MainActor
    final class Coordinator {
        var host: UIHostingController<Content>?
    }
}

// MARK: - Shared page bookkeeping

/// The pages, the active page and the image pipeline shared by both modes.
/// Subclasses own the scroll views and decide where slots go.
class PagesView: UIView {
    static let gap: CGFloat = 16
    /// Fingers and trackpad/mouse scroll; never the Pencil.
    static let scrollTouchTypes = [
        NSNumber(value: UITouch.TouchType.direct.rawValue),
        NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
    ]

    struct LayoutAnchor {
        let pageID: UUID
        /// Mode specific: where that page sat on screen.
        let offset: CGFloat
    }

    var hostView: UIView?
    weak var controller: PageZoomController?
    var fitMargin: CGFloat = 20
    var panTouches = 2 {
        didSet { if oldValue != panTouches { panTouchesDidChange() } }
    }
    var onActivate: (@MainActor (Int) async -> Void)?
    var inkCapture: InkCapture? {
        didSet {
            if oldValue?.capturesFingers != inkCapture?.capturesFingers {
                for slot in slots.values { slot.capturesFingers = inkCapture?.capturesFingers ?? false }
            }
        }
    }

    private(set) var pageOrder: [UUID] = []
    private(set) var activePageID: UUID?
    private var activePage: Page?
    private var source: PageImageSource?
    private var sizes: [UUID: CGSize] = [:]
    private var defaultSize = CGSize(width: 595, height: 842)
    var slots: [UUID: PageSlotView] = [:]

    /// Pages this view asked the session to activate, so their arrival does
    /// not scroll the view back.
    private var requestedIDs: Set<UUID> = []
    private var pendingActivationID: UUID?
    private var activationTask: Task<Void, Never>?

    /// A stroke caught on a page before its canvas arrived (see Design).
    private struct CapturedStroke {
        let pageID: UUID
        let samples: [CapturedInkSample]
        let tool: InkTool
        /// The canvas on screen when the stroke began, which belongs to
        /// another page: the stroke waits for a newer one.
        weak var staleCanvas: InkCanvasView?
        let capturedAt: ContinuousClock.Instant
    }

    private static let captureTimeout: Duration = .seconds(5)
    /// The canvas on screen as each page's current capture began.
    private var canvasAtTouchDown: [UUID: WeakCanvas] = [:]
    private var capturedStrokes: [CapturedStroke] = []
    private var strokeCommitTask: Task<Void, Never>?

    private var renderQueue: [UUID] = []
    private var renderOverrides: [UUID: Page] = [:]
    private var renderTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func pageSize(at index: Int) -> CGSize {
        sizes[pageOrder[index]] ?? defaultSize
    }

    var activeIndex: Int? {
        activePageID.flatMap { pageOrder.firstIndex(of: $0) }
    }

    var displayScale: CGFloat {
        let scale = traitCollection.displayScale
        return scale > 0 ? scale : 2
    }

    /// Rounds a render scale up to half steps, so small zoom changes reuse an
    /// image, and caps it to keep bitmaps reasonable.
    static func quantized(_ scale: CGFloat) -> CGFloat {
        min(max((scale * 2).rounded(.up) / 2, 1), 3)
    }

    // MARK: Updates from SwiftUI

    func update(pageOrder newOrder: [UUID], activePage newPage: Page, source newSource: PageImageSource) {
        let anchor = layoutAnchor()
        var layoutChanged = false

        if let old = source, old.token != newSource.token || old.notebookID != newSource.notebookID {
            // Other pages were rewritten: what was known about them is stale.
            sizes.removeAll()
            renderOverrides.removeAll()
            for slot in slots.values { slot.renderedScale = 0 }
            layoutChanged = true
        }
        source = newSource

        if newOrder != pageOrder {
            pageOrder = newOrder
            layoutChanged = true
        }
        let size = CGSize(width: newPage.width, height: newPage.height)
        if sizes[newPage.id] != size {
            if sizes.isEmpty { defaultSize = size }
            sizes[newPage.id] = size
            layoutChanged = true
        }

        let previousID = activePageID
        let activeChanged = previousID != newPage.id
        if activeChanged, let previousID, let leaving = activePage, leaving.id == previousID,
           newOrder.contains(previousID) {
            // Keep the page being left on screen as it looks now, then redraw
            // it from the in-memory copy, which may hold ink not yet on disk.
            if let slot = slots[previousID] {
                if let snapshot = hostView?.snapshotView(afterScreenUpdates: false) {
                    slot.showPlaceholder(snapshot)
                }
                slot.renderedScale = 0
            }
            PageImageCache.remove(key(for: previousID, source: newSource))
            renderOverrides[previousID] = leaving
        }
        activePage = newPage
        activePageID = newPage.id

        if layoutChanged {
            relayout(keeping: anchor)
        }
        if activeChanged {
            refreshSlots()
            for slot in slots.values { configure(slot) }
            activePageDidChange()
            if requestedIDs.remove(newPage.id) == nil {
                requestedIDs.removeAll()
                scrollToActivePage(animated: previousID != nil)
            }
        }
        controller?.scrollView = zoomingScrollView
        scheduleRenders()
    }

    // MARK: Subclass hooks

    /// The scroll view the zoom buttons drive.
    var zoomingScrollView: UIScrollView? { nil }
    func layoutAnchor() -> LayoutAnchor? { nil }
    func relayout(keeping anchor: LayoutAnchor?) {}
    /// Creates, positions and drops slots for the pages near the viewport.
    func refreshSlots() {}
    func activePageDidChange() {}
    func scrollToActivePage(animated: Bool) {}
    func panTouchesDidChange() {}
    /// Pages to keep rendered, most important first.
    func renderPriority() -> [UUID] { [] }
    func desiredRenderScale() -> CGFloat { Self.quantized(displayScale) }

    // MARK: Slots

    func makeSlot(for pageID: UUID) -> PageSlotView {
        let slot = PageSlotView(pageID: pageID)
        slot.onActivate = { [weak self] id in
            self?.requestActivation(of: id)
        }
        slot.onStrokeBegan = { [weak self] id in
            self?.strokeBegan(on: id)
        }
        slot.onStrokeEnded = { [weak self] id, samples, tool in
            self?.strokeEnded(on: id, samples: samples, tool: tool)
        }
        slot.capturesFingers = inkCapture?.capturesFingers ?? false
        slots[pageID] = slot
        configure(slot)
        return slot
    }

    func dropSlot(_ pageID: UUID) {
        slots[pageID]?.removeFromSuperview()
        slots[pageID] = nil
    }

    func configure(_ slot: PageSlotView) {
        let isActive = slot.pageID == activePageID
        slot.isActive = isActive
        if isActive {
            if let hostView {
                if hostView.superview !== slot { slot.addSubview(hostView) }
                hostView.frame = slot.bounds
            }
        } else if let source, let cached = PageImageCache.entry(key(for: slot.pageID, source: source)),
                  cached.scale > slot.renderedScale {
            slot.show(cached.image, scale: cached.scale)
        }
    }

    // MARK: Activation

    func requestActivation(of pageID: UUID) {
        guard pageID != activePageID, pageOrder.contains(pageID) else { return }
        requestedIDs.insert(pageID)
        pendingActivationID = pageID
        guard activationTask == nil else { return }
        // One page load at a time; a newer request replaces a queued one.
        activationTask = Task { [weak self] in
            while let self, let pageID = self.pendingActivationID {
                self.pendingActivationID = nil
                guard pageID != self.activePageID,
                      let index = self.pageOrder.firstIndex(of: pageID)
                else { continue }
                await self.onActivate?(index)
            }
            self?.activationTask = nil
        }
    }

    // MARK: Strokes on a loading page

    /// A Pencil (or drawing finger) landed on an inactive page: activate it,
    /// and return the tool to catch the stroke with, if it inks.
    private func strokeBegan(on pageID: UUID) -> InkTool? {
        requestActivation(of: pageID)
        guard let capture = inkCapture, let tool = capture.tool else { return nil }
        canvasAtTouchDown[pageID] = WeakCanvas(canvas: capture.canvas.canvas)
        return tool
    }

    private func strokeEnded(on pageID: UUID, samples: [CapturedInkSample], tool: InkTool) {
        let stale = canvasAtTouchDown.removeValue(forKey: pageID)?.canvas
        capturedStrokes.append(CapturedStroke(
            pageID: pageID,
            samples: samples,
            tool: tool,
            staleCanvas: stale,
            capturedAt: .now
        ))
        commitCapturedStrokes()
        guard strokeCommitTask == nil, !capturedStrokes.isEmpty else { return }
        // The canvas appears once SwiftUI has rebuilt the page content, a
        // frame or a few after the page loads.
        strokeCommitTask = Task { [weak self] in
            while let self, !self.capturedStrokes.isEmpty {
                try? await Task.sleep(for: .milliseconds(16))
                self.commitCapturedStrokes()
            }
            self?.strokeCommitTask = nil
        }
    }

    /// Hands captured strokes to their page's canvas once it is on screen,
    /// in the order they were drawn; drops strokes that waited too long.
    private func commitCapturedStrokes() {
        guard !capturedStrokes.isEmpty else { return }
        let now = ContinuousClock.now
        var waiting: [CapturedStroke] = []
        var finishedPages = Set<UUID>()
        for stroke in capturedStrokes {
            if let canvas = liveCanvas(for: stroke) {
                if let pkStroke = CapturedStrokeBuilder.stroke(from: stroke.samples, tool: stroke.tool) {
                    canvas.appendStroke(pkStroke)
                }
                finishedPages.insert(stroke.pageID)
            } else if now - stroke.capturedAt > Self.captureTimeout || !pageOrder.contains(stroke.pageID) {
                finishedPages.insert(stroke.pageID)
            } else {
                waiting.append(stroke)
            }
        }
        capturedStrokes = waiting
        for pageID in finishedPages where !waiting.contains(where: { $0.pageID == pageID }) {
            slots[pageID]?.clearCapturedInk()
        }
    }

    /// The controller of the canvas for `stroke`'s page, once that canvas is
    /// the live one in the page's slot.
    private func liveCanvas(for stroke: CapturedStroke) -> PencilCanvasController? {
        guard stroke.pageID == activePageID,
              let controller = inkCapture?.canvas,
              let canvas = controller.canvas,
              canvas !== stroke.staleCanvas,
              canvas.window != nil,
              let slot = slots[stroke.pageID],
              canvas.isDescendant(of: slot)
        else { return nil }
        return controller
    }

    // MARK: Rendering

    private func key(for pageID: UUID, source: PageImageSource) -> String {
        "\(source.notebookID.uuidString)/\(source.token.uuidString)/\(pageID.uuidString)"
    }

    /// Queues renders for nearby pages whose image is missing or too coarse.
    /// Cheap when nothing is needed, so it can run on every update.
    func scheduleRenders() {
        guard let source else { return }
        let scale = desiredRenderScale()
        var queue: [UUID] = []
        for pageID in renderPriority() where pageID != activePageID {
            guard let slot = slots[pageID] else { continue }
            if slot.renderedScale >= scale * 0.8 { continue }
            if let cached = PageImageCache.entry(key(for: pageID, source: source)),
               cached.scale >= scale * 0.8,
               renderOverrides[pageID] == nil {
                slot.show(cached.image, scale: cached.scale)
                continue
            }
            queue.append(pageID)
        }
        renderQueue = queue
        // A leaving page that scrolled away is read from disk when it returns;
        // the session saves it before loading the next page.
        renderOverrides = renderOverrides.filter { queue.contains($0.key) }
        guard renderTask == nil, !renderQueue.isEmpty else { return }
        renderTask = Task { [weak self] in
            while let self, !self.renderQueue.isEmpty {
                let pageID = self.renderQueue.removeFirst()
                await self.render(pageID)
            }
            self?.renderTask = nil
        }
    }

    private func render(_ pageID: UUID) async {
        guard let source, slots[pageID] != nil, pageID != activePageID else { return }
        let page: Page
        if let override = renderOverrides.removeValue(forKey: pageID) {
            page = override
        } else {
            guard let loaded = try? await source.store.loadPage(pageID, in: source.notebookID) else { return }
            page = loaded
        }
        guard self.source?.token == source.token, self.source?.notebookID == source.notebookID else { return }
        learnSize(of: page)

        let scale = desiredRenderScale()
        let assetsDirectory = source.assetsDirectory
        let image = await Task.detached(priority: .userInitiated) {
            PageRenderer.image(page: page, assetsDirectory: assetsDirectory, scale: scale)
        }.value
        guard let image,
              self.source?.token == source.token,
              self.source?.notebookID == source.notebookID
        else { return }
        PageImageCache.store(image, scale: scale, key: key(for: pageID, source: source))
        if pageID != activePageID {
            slots[pageID]?.show(image, scale: scale)
        }
    }

    private func learnSize(of page: Page) {
        let size = CGSize(width: page.width, height: page.height)
        guard sizes[page.id] != size else { return }
        let anchor = layoutAnchor()
        sizes[page.id] = size
        relayout(keeping: anchor)
    }
}

// MARK: - Vertical (seamless)

final class VerticalPagesView: PagesView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let stack = UIView()
    /// Page frames in stack coordinates (unzoomed page points).
    private var frames: [CGRect] = []
    private var stackSize: CGSize = .zero
    private var didFit = false
    private var lastBoundsSize: CGSize = .zero
    private var lastFit: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.delegate = self
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = true
        scroll.bouncesZoom = true
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.panGestureRecognizer.allowedTouchTypes = PagesView.scrollTouchTypes
        scroll.panGestureRecognizer.minimumNumberOfTouches = panTouches
        stack.backgroundColor = .clear
        scroll.addSubview(stack)
        addSubview(scroll)
    }

    override var zoomingScrollView: UIScrollView? { scroll }

    override func panTouchesDidChange() {
        scroll.panGestureRecognizer.minimumNumberOfTouches = panTouches
    }

    private func fitScale() -> CGFloat {
        let margin = min(fitMargin, bounds.width / 4)
        return max((bounds.width - margin * 2) / max(stackSize.width, 1), 0.01)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        guard bounds.width > 1, bounds.height > 1, !frames.isEmpty else { return }

        if bounds.size != lastBoundsSize || !didFit {
            let isFirstFit = !didFit
            let anchor = isFirstFit ? nil : layoutAnchor()
            // The user was looking at the full width: keep showing all of it.
            let wasFitted = isFirstFit || abs(scroll.zoomScale - lastFit) / max(lastFit, 0.0001) < 0.02
            let fit = fitScale()
            lastBoundsSize = bounds.size
            lastFit = fit
            scroll.minimumZoomScale = max(fit * 0.5, 0.05)
            scroll.maximumZoomScale = max(fit * 8, 1)
            if wasFitted {
                scroll.zoomScale = fit
            }
            didFit = true
            syncStackGeometry()
            controller?.updateFit(fit)
            controller?.settle(at: scroll.zoomScale)
            if let anchor {
                restore(anchor)
            } else {
                scrollToActivePage(animated: false)
            }
            refreshSlots()
            scheduleRenders()
            return
        }
        centerContent()
        refreshSlots()
    }

    /// Keeps the stack view, content size and insets in step with the stack
    /// size at the current zoom.
    private func syncStackGeometry() {
        let zoom = scroll.zoomScale
        stack.bounds = CGRect(origin: .zero, size: stackSize)
        stack.center = CGPoint(x: stackSize.width * zoom / 2, y: stackSize.height * zoom / 2)
        scroll.contentSize = CGSize(width: stackSize.width * zoom, height: stackSize.height * zoom)
        centerContent()
    }

    private func centerContent() {
        let size = stack.frame.size
        let horizontal = max((bounds.width - size.width) / 2, 0)
        let vertical = max((bounds.height - size.height) / 2, 0)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if scroll.contentInset != insets {
            scroll.contentInset = insets
        }
    }

    private func setOffsetY(_ y: CGFloat, animated: Bool) {
        let minY = -scroll.contentInset.top
        let maxY = max(scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height, minY)
        let target = CGPoint(x: scroll.contentOffset.x, y: min(max(y, minY), maxY))
        if abs(target.y - scroll.contentOffset.y) > 0.5 {
            scroll.setContentOffset(target, animated: animated)
        }
    }

    /// The page whose slot (with half the gap on each side) holds `y`, in
    /// stack coordinates, or the nearest page.
    private func pageIndex(atY y: CGFloat) -> Int? {
        guard !frames.isEmpty else { return nil }
        var low = 0
        var high = frames.count - 1
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].maxY + Self.gap / 2 < y {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private var visibleStackRect: CGRect {
        scroll.convert(scroll.bounds, to: stack)
    }

    private func centreIndex() -> Int? {
        guard didFit, frames.count == pageOrder.count else { return nil }
        return pageIndex(atY: visibleStackRect.midY)
    }

    // MARK: Layout

    override func layoutAnchor() -> LayoutAnchor? {
        guard let index = centreIndex() else { return nil }
        return LayoutAnchor(
            pageID: pageOrder[index],
            offset: frames[index].minY * scroll.zoomScale - scroll.contentOffset.y
        )
    }

    private func restore(_ anchor: LayoutAnchor) {
        guard let index = pageOrder.firstIndex(of: anchor.pageID), index < frames.count else { return }
        setOffsetY(frames[index].minY * scroll.zoomScale - anchor.offset, animated: false)
    }

    override func relayout(keeping anchor: LayoutAnchor?) {
        var width: CGFloat = 1
        for index in pageOrder.indices {
            width = max(width, pageSize(at: index).width)
        }
        var y = Self.gap
        var newFrames: [CGRect] = []
        newFrames.reserveCapacity(pageOrder.count)
        for index in pageOrder.indices {
            let size = pageSize(at: index)
            newFrames.append(CGRect(x: (width - size.width) / 2, y: y, width: size.width, height: size.height))
            y += size.height + Self.gap
        }
        let widthChanged = stackSize.width != width
        frames = newFrames
        stackSize = CGSize(width: width, height: y)

        if didFit, widthChanged {
            let fit = fitScale()
            let wasFitted = abs(scroll.zoomScale - lastFit) / max(lastFit, 0.0001) < 0.02
            lastFit = fit
            scroll.minimumZoomScale = max(fit * 0.5, 0.05)
            scroll.maximumZoomScale = max(fit * 8, 1)
            if wasFitted { scroll.zoomScale = fit }
            controller?.updateFit(fit)
        }
        syncStackGeometry()
        if let anchor { restore(anchor) }
        refreshSlots()
        setNeedsLayout()
    }

    override func refreshSlots() {
        guard didFit, !frames.isEmpty, frames.count == pageOrder.count else {
            // Before the first fit only the active page is needed.
            if frames.count == pageOrder.count, let index = activeIndex {
                place(index)
            }
            return
        }
        let rect = visibleStackRect
        let prefetch = rect.height * 0.5
        guard let first = pageIndex(atY: rect.minY - prefetch),
              let last = pageIndex(atY: rect.maxY + prefetch)
        else { return }
        var wanted = Set(pageOrder[first...last])
        let active = activeIndex
        if let active { wanted.insert(pageOrder[active]) }
        for pageID in Array(slots.keys) where !wanted.contains(pageID) {
            dropSlot(pageID)
        }
        var created = false
        for index in first...last {
            created = place(index) || created
        }
        if let active, !(first...last).contains(active) {
            created = place(active) || created
        }
        if created { scheduleRenders() }
    }

    /// Positions the slot for `index`, creating it if needed. Returns whether
    /// it was created.
    @discardableResult
    private func place(_ index: Int) -> Bool {
        let pageID = pageOrder[index]
        var created = false
        let slot: PageSlotView
        if let existing = slots[pageID] {
            slot = existing
        } else {
            slot = makeSlot(for: pageID)
            stack.addSubview(slot)
            created = true
        }
        if slot.frame != frames[index] {
            slot.frame = frames[index]
            if slot.isActive { hostView?.frame = slot.bounds }
        }
        return created
    }

    override func scrollToActivePage(animated: Bool) {
        guard didFit, let index = activeIndex, index < frames.count else { return }
        let target = (frames[index].minY - Self.gap) * scroll.zoomScale
        // Already showing the top of the page: leave the view where it is.
        if abs(target - scroll.contentOffset.y) < 1 { return }
        setOffsetY(target, animated: animated)
        refreshSlots()
    }

    override func renderPriority() -> [UUID] {
        guard let centre = centreIndex() else { return [] }
        return slots.keys
            .compactMap { id in pageOrder.firstIndex(of: id).map { (id, abs($0 - centre)) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    override func desiredRenderScale() -> CGFloat {
        Self.quantized(scroll.zoomScale * displayScale)
    }

    // MARK: Settling

    /// A user scroll or zoom came to rest: the page in the middle becomes the
    /// page being edited.
    private func userScrollDidSettle() {
        if let index = centreIndex() {
            requestActivation(of: pageOrder[index])
        }
        scheduleRenders()
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        stack
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refreshSlots()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        refreshSlots()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        controller?.settle(at: scale)
        userScrollDidSettle()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { userScrollDidSettle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userScrollDidSettle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // A programmatic scroll (to the active page) does not pick a page.
        scheduleRenders()
    }
}

// MARK: - Horizontal (single page)

final class HorizontalPagesView: PagesView, UIScrollViewDelegate {
    private let pager = UIScrollView()
    private var cells: [UUID: PageScrollView] = [:]
    private var lastBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        pager.delegate = self
        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.showsVerticalScrollIndicator = false
        pager.alwaysBounceVertical = false
        pager.backgroundColor = .clear
        pager.contentInsetAdjustmentBehavior = .never
        pager.decelerationRate = .fast
        pager.panGestureRecognizer.allowedTouchTypes = PagesView.scrollTouchTypes
        pager.panGestureRecognizer.minimumNumberOfTouches = panTouches
        addSubview(pager)
    }

    private var stride: CGFloat { pager.bounds.width }

    override var zoomingScrollView: UIScrollView? {
        activePageID.flatMap { cells[$0] }
    }

    override func panTouchesDidChange() {
        pager.panGestureRecognizer.minimumNumberOfTouches = panTouches
        for cell in cells.values {
            cell.panGestureRecognizer.minimumNumberOfTouches = panTouches
        }
    }

    /// The page the pager is showing (nearest, while it moves).
    private func currentIndex() -> Int? {
        guard !pageOrder.isEmpty else { return nil }
        guard stride > 1 else { return activeIndex ?? 0 }
        let index = Int((pager.contentOffset.x / stride).rounded())
        return min(max(index, 0), pageOrder.count - 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1 else { return }
        if bounds.size != lastBoundsSize {
            // Keep the page on screen through rotation and split view.
            let index = lastBoundsSize == .zero ? activeIndex : currentIndex()
            lastBoundsSize = bounds.size
            pager.frame = bounds.insetBy(dx: -Self.gap / 2, dy: 0)
            updateContentSize()
            if let index {
                pager.contentOffset = CGPoint(x: CGFloat(index) * stride, y: 0)
            }
            for (pageID, cell) in cells {
                if let index = pageOrder.firstIndex(of: pageID) {
                    cell.frame = cellFrame(at: index)
                }
            }
            refreshSlots()
            activePageDidChange()
            scheduleRenders()
        }
    }

    private func updateContentSize() {
        pager.contentSize = CGSize(width: stride * CGFloat(pageOrder.count), height: bounds.height)
    }

    private func cellFrame(at index: Int) -> CGRect {
        CGRect(x: CGFloat(index) * stride + Self.gap / 2, y: 0, width: bounds.width, height: bounds.height)
    }

    override func layoutAnchor() -> LayoutAnchor? {
        guard let index = currentIndex(), stride > 1 else { return nil }
        return LayoutAnchor(pageID: pageOrder[index], offset: 0)
    }

    override func relayout(keeping anchor: LayoutAnchor?) {
        guard stride > 1 else { return }
        updateContentSize()
        if let anchor, let index = pageOrder.firstIndex(of: anchor.pageID) {
            pager.contentOffset = CGPoint(x: CGFloat(index) * stride, y: 0)
        } else if let index = currentIndex() {
            pager.contentOffset = CGPoint(x: CGFloat(index) * stride, y: 0)
        }
        for pageID in Array(cells.keys) where !pageOrder.contains(pageID) {
            dropCell(pageID)
        }
        for (pageID, cell) in cells {
            guard let index = pageOrder.firstIndex(of: pageID) else { continue }
            cell.frame = cellFrame(at: index)
            fitSlot(in: cell, size: pageSize(at: index))
        }
        refreshSlots()
    }

    override func refreshSlots() {
        guard stride > 1, let current = currentIndex() else { return }
        var indices = Set((current - 1)...(current + 1)).filter { pageOrder.indices.contains($0) }
        if let active = activeIndex { indices.insert(active) }
        let wanted = Set(indices.map { pageOrder[$0] })
        for pageID in Array(cells.keys) where !wanted.contains(pageID) {
            dropCell(pageID)
        }
        var created = false
        for index in indices where cells[pageOrder[index]] == nil {
            makeCell(at: index)
            created = true
        }
        if created { scheduleRenders() }
    }

    private func makeCell(at index: Int) {
        let pageID = pageOrder[index]
        let size = pageSize(at: index)
        let cell = PageScrollView()
        cell.delegate = self
        cell.showsHorizontalScrollIndicator = false
        cell.showsVerticalScrollIndicator = false
        cell.bouncesZoom = true
        cell.decelerationRate = .fast
        cell.backgroundColor = .clear
        cell.clipsToBounds = true
        cell.contentInsetAdjustmentBehavior = .never
        cell.panGestureRecognizer.allowedTouchTypes = PagesView.scrollTouchTypes
        cell.panGestureRecognizer.minimumNumberOfTouches = panTouches
        cell.fitMargin = fitMargin
        cell.frame = cellFrame(at: index)

        let slot = makeSlot(for: pageID)
        cell.addSubview(slot)
        cell.zoomView = slot
        cell.pageSize = size
        slot.frame = CGRect(origin: .zero, size: size)
        cell.contentSize = size
        configure(slot)
        cell.onFit = { [weak self, weak cell] fit in
            guard let self, let cell, self.activePageID == pageID else { return }
            self.controller?.updateFit(fit)
            self.controller?.settle(at: cell.zoomScale)
        }
        cells[pageID] = cell
        pager.addSubview(cell)
    }

    private func dropCell(_ pageID: UUID) {
        dropSlot(pageID)
        cells[pageID]?.removeFromSuperview()
        cells[pageID] = nil
    }

    private func fitSlot(in cell: PageScrollView, size: CGSize) {
        guard cell.pageSize != size, let slot = cell.zoomView else { return }
        cell.pageSize = size
        slot.transform = .identity
        slot.frame = CGRect(origin: .zero, size: size)
        cell.contentSize = size
        if let slot = slot as? PageSlotView, slot.isActive {
            hostView?.frame = slot.bounds
        }
        cell.resetZoom()
    }

    override func activePageDidChange() {
        guard let pageID = activePageID, let cell = cells[pageID] else { return }
        controller?.scrollView = cell
        guard cell.lastFit > 0 else { return }
        controller?.updateFit(cell.lastFit)
        controller?.settle(at: cell.zoomScale)
    }

    override func scrollToActivePage(animated: Bool) {
        guard stride > 1, let index = activeIndex else { return }
        let target = CGPoint(x: CGFloat(index) * stride, y: 0)
        guard abs(pager.contentOffset.x - target.x) > 0.5 else { return }
        let isNeighbour = abs((currentIndex() ?? index) - index) == 1
        pager.setContentOffset(target, animated: animated && isNeighbour)
        refreshSlots()
    }

    override func renderPriority() -> [UUID] {
        guard let current = currentIndex() else { return [] }
        return cells.keys
            .compactMap { id in pageOrder.firstIndex(of: id).map { (id, abs($0 - current)) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    override func desiredRenderScale() -> CGFloat {
        guard let current = currentIndex() else { return Self.quantized(displayScale) }
        let size = pageSize(at: current)
        let margin = min(fitMargin, bounds.width / 4, bounds.height / 4)
        let fit = min(
            (bounds.width - margin * 2) / max(size.width, 1),
            (bounds.height - margin * 2) / max(size.height, 1)
        )
        return Self.quantized(fit * displayScale)
    }

    private func pagerDidSettle() {
        if let index = currentIndex() {
            requestActivation(of: pageOrder[index])
        }
        scheduleRenders()
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        scrollView === pager ? nil : (scrollView as? PageScrollView)?.zoomView
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === pager { refreshSlots() }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        (scrollView as? PageScrollView)?.centerContent()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scrollView === zoomingScrollView {
            controller?.settle(at: scale)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === pager, !decelerate { pagerDidSettle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === pager { pagerDidSettle() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if scrollView === pager { scheduleRenders() }
    }
}

// MARK: - Page slot

/// One page's paper: white with a shadow, showing either a rendered image or,
/// for the active page, the live page content added by `PagesView`.
final class PageSlotView: UIView, UIGestureRecognizerDelegate {
    let pageID: UUID
    var onActivate: ((UUID) -> Void)?
    /// A stroke began on this (inactive) page; returns the ink to catch it with.
    var onStrokeBegan: ((UUID) -> InkTool?)?
    var onStrokeEnded: ((UUID, [CapturedInkSample], InkTool) -> Void)?
    /// The scale of the image shown; 0 when it is missing or stale.
    var renderedScale: CGFloat = 0

    private let imageView = UIImageView()
    private var placeholder: UIView?
    private let pencilDown = InkCaptureRecognizer()
    private let fingerTap = UITapGestureRecognizer()
    /// Previews of caught strokes, above the live content until replayed.
    private let inkPreview = UIView()
    private var liveStrokeLayer: CAShapeLayer?
    private var liveStrokeTool: InkTool?

    /// Whether a finger touch is caught as ink (Draw with Finger) rather
    /// than only tapping the page active.
    var capturesFingers = false {
        didSet {
            var types = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            if capturesFingers { types.append(NSNumber(value: UITouch.TouchType.direct.rawValue)) }
            pencilDown.allowedTouchTypes = types
        }
    }

    var isActive = false {
        didSet {
            guard oldValue != isActive else { return }
            imageView.isHidden = isActive
            placeholder?.isHidden = isActive
            // The capture recognizer stays on: a stroke that began while the
            // page loaded must reach its end. It ignores touches that start
            // on the active page, which belong to the live canvas.
            fingerTap.isEnabled = !isActive
        }
    }

    init(pageID: UUID) {
        self.pageID = pageID
        super.init(frame: .zero)
        // Paper is white whatever the appearance.
        backgroundColor = .white
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

        imageView.contentMode = .scaleToFill
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)

        inkPreview.isUserInteractionEnabled = false
        inkPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(inkPreview)

        // A Pencil touching another page makes it the active page at once,
        // and its stroke is caught until that page's canvas arrives.
        pencilDown.addTarget(self, action: #selector(pencilTouched(_:)))
        pencilDown.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilDown.cancelsTouchesInView = false
        pencilDown.delaysTouchesEnded = false
        pencilDown.shouldBegin = { [weak self] in self.map { !$0.isActive } ?? false }
        pencilDown.delegate = self
        addGestureRecognizer(pencilDown)

        fingerTap.addTarget(self, action: #selector(fingerTapped(_:)))
        fingerTap.allowedTouchTypes = PagesView.scrollTouchTypes
        fingerTap.cancelsTouchesInView = false
        addGestureRecognizer(fingerTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        placeholder?.frame = bounds
        inkPreview.frame = bounds
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }

    func show(_ image: UIImage, scale: CGFloat) {
        imageView.image = image
        renderedScale = scale
        placeholder?.removeFromSuperview()
        placeholder = nil
    }

    /// Keeps caught ink above the live page content when it moves in.
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        if subview !== inkPreview { bringSubviewToFront(inkPreview) }
    }

    /// Removes the previews of strokes that were replayed or dropped. A
    /// stroke still being drawn keeps its preview.
    func clearCapturedInk() {
        for layer in inkPreview.layer.sublayers ?? [] where layer !== liveStrokeLayer {
            layer.removeFromSuperlayer()
        }
    }

    /// Shows `view` above the image until the next rendered image arrives.
    func showPlaceholder(_ view: UIView) {
        placeholder?.removeFromSuperview()
        view.frame = bounds
        view.isUserInteractionEnabled = false
        view.isHidden = isActive
        insertSubview(view, aboveSubview: imageView)
        placeholder = view
    }

    @objc private func pencilTouched(_ gesture: InkCaptureRecognizer) {
        switch gesture.state {
        case .began:
            liveStrokeTool = onStrokeBegan?(pageID)
            if let tool = liveStrokeTool {
                let layer = CAShapeLayer()
                layer.fillColor = nil
                layer.strokeColor = tool.color.previewColor.cgColor
                layer.lineWidth = CGFloat(tool.width)
                layer.lineCap = .round
                layer.lineJoin = .round
                inkPreview.layer.addSublayer(layer)
                liveStrokeLayer = layer
            }
            updateLiveStroke(gesture.samples)
        case .changed:
            updateLiveStroke(gesture.samples)
        case .ended:
            updateLiveStroke(gesture.samples)
            let layer = liveStrokeLayer
            liveStrokeLayer = nil
            if let tool = liveStrokeTool, !gesture.samples.isEmpty {
                onStrokeEnded?(pageID, gesture.samples, tool)
            } else {
                layer?.removeFromSuperlayer()
            }
            liveStrokeTool = nil
        default:
            liveStrokeLayer?.removeFromSuperlayer()
            liveStrokeLayer = nil
            liveStrokeTool = nil
        }
    }

    private func updateLiveStroke(_ samples: [CapturedInkSample]) {
        guard let layer = liveStrokeLayer, let first = samples.first else { return }
        let path = UIBezierPath()
        path.move(to: first.location)
        // A dot still shows: a zero-length segment draws a round cap.
        path.addLine(to: first.location)
        for sample in samples.dropFirst() {
            path.addLine(to: sample.location)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.path = path.cgPath
        CATransaction.commit()
    }

    @objc private func fingerTapped(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended { onActivate?(pageID) }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Stroke capture

extension InkCapture {
    var capturesFingers: Bool {
        guard tool != nil else { return false }
        #if targetEnvironment(simulator)
        // The canvas draws with any input in the simulator.
        return true
        #else
        return drawsWithFinger
        #endif
    }
}

/// Holds the canvas on screen at a touch-down without keeping it alive.
private struct WeakCanvas {
    weak var canvas: InkCanvasView?
}

private extension RGBAColor {
    var previewColor: UIColor {
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

/// Follows one touch from touch-down to lift and records its samples
/// (coalesced, in the view's coordinates). Begins at once, never cancels
/// other gestures, and gives up when a second touch makes it a pinch or pan.
final class InkCaptureRecognizer: UIGestureRecognizer {
    private(set) var samples: [CapturedInkSample] = []
    /// Asked at touch-down; `false` lets the touch pass untracked.
    var shouldBegin: (() -> Bool)?
    private weak var trackedTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if trackedTouch != nil {
            // A second touch: not ink.
            state = state == .possible ? .failed : .cancelled
            return
        }
        guard touches.count == 1, let touch = touches.first, shouldBegin?() ?? true else {
            state = .failed
            return
        }
        trackedTouch = touch
        samples = []
        record(touch, event: event)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        record(touch, event: event)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        record(touch, event: event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        state = .cancelled
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
        samples = []
    }

    private func record(_ touch: UITouch, event: UIEvent) {
        let touches = event.coalescedTouches(for: touch) ?? [touch]
        for sample in touches {
            let maximum = sample.maximumPossibleForce
            let pressure: CGFloat? = sample.type == .pencil && maximum > 0 ? sample.force / maximum : nil
            let location = sample.preciseLocation(in: view)
            // Coalesced touches repeat the last sample on lift.
            if let last = samples.last, last.location == location, last.time == sample.timestamp { continue }
            samples.append(CapturedInkSample(
                location: location,
                time: sample.timestamp,
                force: sample.force,
                pressure: pressure,
                altitude: sample.altitudeAngle,
                azimuth: sample.azimuthAngle(in: view)
            ))
        }
    }
}

// MARK: - Image cache

/// Rendered pages, evicted under memory pressure or past the cost limit.
@MainActor
enum PageImageCache {
    final class Entry {
        let image: UIImage
        let scale: CGFloat

        init(image: UIImage, scale: CGFloat) {
            self.image = image
            self.scale = scale
        }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    static func entry(_ key: String) -> Entry? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, scale: CGFloat, key: String) {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        cache.setObject(Entry(image: image, scale: scale), forKey: key as NSString, cost: Int(pixels * 4))
    }

    static func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}
#endif
