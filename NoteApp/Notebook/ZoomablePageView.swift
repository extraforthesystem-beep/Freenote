#if os(iOS)
import Observation
import SwiftUI
import UIKit

/// Drives the zoomable page from SwiftUI toolbar buttons, and reports the
/// zoom the user settled on so the paper can be re-rendered sharply.
@MainActor
@Observable
final class PageZoomController {
    @ObservationIgnored weak var scrollView: UIScrollView?
    @ObservationIgnored private(set) var fitScale: CGFloat = 1
    /// The zoom scale after the last zoom gesture or fit ended. Observed, so a
    /// view reading it updates once per settled zoom, never during a pinch.
    private(set) var settledZoom: CGFloat = 1

    var currentZoom: CGFloat { scrollView?.zoomScale ?? fitScale }

    func fit() {
        guard let scrollView else { return }
        scrollView.setZoomScale(fitScale, animated: true)
    }

    func zoomIn() {
        guard let scrollView else { return }
        scrollView.setZoomScale(min(scrollView.zoomScale * 1.35, scrollView.maximumZoomScale), animated: true)
    }

    func zoomOut() {
        guard let scrollView else { return }
        scrollView.setZoomScale(max(scrollView.zoomScale / 1.35, scrollView.minimumZoomScale), animated: true)
    }

    func updateFit(_ scale: CGFloat) {
        fitScale = scale
    }

    func settle(at scale: CGFloat) {
        // Ignore tiny changes so the paper is not re-rendered for nothing.
        if abs(settledZoom - scale) / max(settledZoom, 0.0001) > 0.05 {
            settledZoom = scale
        }
    }
}

/// Hosts one page in a `UIScrollView` so paper, elements and ink zoom and pan
/// together. The hosted SwiftUI content is exactly one page in size; the scroll
/// view applies the view transform, so page coordinates never change.
struct ZoomablePageView<Content: View>: UIViewRepresentable {
    let pageSize: CGSize
    let controller: PageZoomController?
    /// Empty space kept around the page when it is fitted.
    let fitMargin: CGFloat
    /// Fingers needed to pan. Two keeps a resting palm or finger from moving
    /// the page in the middle of a Pencil stroke.
    let minimumPanTouches: Int
    let content: Content

    init(
        pageSize: CGSize,
        controller: PageZoomController? = nil,
        fitMargin: CGFloat = 0,
        minimumPanTouches: Int = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.pageSize = pageSize
        self.controller = controller
        self.fitMargin = fitMargin
        self.minimumPanTouches = minimumPanTouches
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PageScrollView {
        let scroll = PageScrollView()
        scroll.pageSize = pageSize
        scroll.fitMargin = fitMargin
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.decelerationRate = .fast
        scroll.backgroundColor = .clear
        scroll.clipsToBounds = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.panGestureRecognizer.minimumNumberOfTouches = minimumPanTouches

        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: pageSize)
        scroll.addSubview(host.view)
        scroll.zoomView = host.view
        scroll.contentSize = pageSize
        scroll.onFit = { [weak controller] scale in
            controller?.updateFit(scale)
            controller?.settle(at: scale)
        }
        context.coordinator.host = host
        controller?.scrollView = scroll
        return scroll
    }

    func updateUIView(_ scroll: PageScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.host?.rootView = content
        scroll.panGestureRecognizer.minimumNumberOfTouches = minimumPanTouches

        if scroll.fitMargin != fitMargin {
            scroll.fitMargin = fitMargin
            scroll.setNeedsLayout()
        }
        if scroll.pageSize != pageSize {
            scroll.pageSize = pageSize
            context.coordinator.host?.view.transform = .identity
            context.coordinator.host?.view.frame = CGRect(origin: .zero, size: pageSize)
            scroll.contentSize = pageSize
            scroll.resetZoom()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomablePageView
        var host: UIHostingController<Content>?

        init(parent: ZoomablePageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? PageScrollView)?.centerContent()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            parent.controller?.settle(at: scale)
        }
    }
}

/// A scroll view that fits the page inside its bounds, re-fits when its size
/// changes (rotation, split view) unless the user zoomed in, and keeps the
/// page centred while it is smaller than the viewport.
final class PageScrollView: UIScrollView {
    var pageSize: CGSize = .zero
    var fitMargin: CGFloat = 0
    weak var zoomView: UIView?
    var onFit: ((CGFloat) -> Void)?
    private var didFit = false
    private var lastBoundsSize: CGSize = .zero
    private(set) var lastFit: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1,
              pageSize.width > 0, pageSize.height > 0
        else { return }

        let margin = min(fitMargin, bounds.width / 4, bounds.height / 4)
        let fit = max(min(
            (bounds.width - margin * 2) / pageSize.width,
            (bounds.height - margin * 2) / pageSize.height
        ), 0.01)

        if bounds.size != lastBoundsSize || !didFit {
            // The user was looking at the whole page: keep showing all of it.
            let wasFitted = !didFit || abs(zoomScale - lastFit) / max(lastFit, 0.0001) < 0.02
            lastBoundsSize = bounds.size
            minimumZoomScale = max(fit * 0.5, 0.05)
            maximumZoomScale = max(fit * 8, 1)
            lastFit = fit
            if wasFitted {
                zoomScale = fit
            }
            didFit = true
            centerContent()
            if wasFitted {
                contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
            }
            onFit?(fit)
            return
        }
        centerContent()
    }

    /// Centres the page with insets, so a page smaller than the viewport sits in
    /// the middle and a larger one scrolls edge to edge.
    func centerContent() {
        let size = zoomView?.frame.size ?? CGSize(
            width: pageSize.width * zoomScale,
            height: pageSize.height * zoomScale
        )
        let horizontal = max((bounds.width - size.width) / 2, 0)
        let vertical = max((bounds.height - size.height) / 2, 0)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets {
            contentInset = insets
        }
    }

    func resetZoom() {
        didFit = false
        setNeedsLayout()
    }
}
#endif
