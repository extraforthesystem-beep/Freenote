#if os(iOS)
import InkKit
import NoteCore
import SwiftUI
import UIKit

// MARK: - Design
//
// Zoom View (GoodNotes "Zoom Window", Notability "Zoom") magnifies a band of
// the active page in a panel below the page area, for writing small.
//
// The panel's canvas is a second `PencilCanvasView` of the same page, fed the
// same `session.visibleStrokes` and reporting to the same
// `session.strokesChanged`. It shows only the band through its `viewport`:
// PencilKit's own zoom scale and content offset (scrolling off), so drawing
// coordinates stay page points and no stroke is ever transformed. Tool, layer,
// hold-to-shape, the highlighter-only eraser and finger double-tap undo all
// come with the reused view. The two canvases stay in step through the
// session: a stroke from one comes back to the other as a record with the
// same id, the other canvas adds it (decoding only that stroke), and its
// converter is seeded with it, so the echo is recognised and nothing loops.
// Each canvas keeps its own PencilKit undo stack; the toolbar's undo goes to
// whichever canvas the Pencil touched last (`PencilCanvasController`).
//
// Behind the panel's canvas the page's paper and elements are the same
// `PaperBackground` the page uses, scaled and offset to the band.
//
// The band's geometry (size from the magnification and the panel's aspect,
// advance, wrap, clamp) is `ZoomBand` in InkKit, which is unit tested. Only
// the band's origin is state here, keyed by page, so moving to another page
// starts again at its top-left margin; the size follows the settings and the
// panel's size on every render.
//
// On the page, `ZoomFrameOverlay` outlines the band. Its interior lets every
// touch through to the page canvas; only a grab tab on the top edge (move) and
// a corner handle (resize, which sets the magnification) take touches. A
// long-press recognizer with no delay claims a touch on a handle before the
// page's one-finger scroll can.
//
// Auto-advance: when a new ink stroke from the panel ends in the band's right
// fifth, the band steps on a moment after the Pencil lifts, unless the Pencil
// touches down again first (dotting an i, crossing a t).

/// Where the Zoom View band is, and the panel's measured writing area.
@MainActor
@Observable
final class ZoomViewState {
    /// The band's top-left corner on `pageID`; nil starts at the margins.
    private var origin: CGPoint?
    private var pageID: UUID?
    /// The panel's writing area, which gives the band its aspect.
    var writingSize: CGSize = .zero
    /// The magnification while the frame's corner is being dragged; written
    /// to the settings when the drag ends.
    var liveMagnification: Double?
    /// The panel height while its top edge is being dragged.
    var livePanelHeight: CGFloat?

    @ObservationIgnored private var advanceTask: Task<Void, Never>?
    /// How long after the Pencil lifts the band advances.
    private static let advanceDelay: Duration = .milliseconds(350)

    func band(for page: Page, magnification: Double) -> ZoomBand? {
        guard writingSize.width > 1, writingSize.height > 1 else { return nil }
        return ZoomBand(
            pageSize: CGSize(width: page.width, height: page.height),
            magnification: magnification,
            panelAspect: writingSize.width / writingSize.height,
            origin: pageID == page.id ? origin : nil
        )
    }

    func update(page: Page, magnification: Double, _ change: (inout ZoomBand) -> Void) {
        guard var band = band(for: page, magnification: magnification) else { return }
        change(&band)
        origin = band.rect.origin
        pageID = page.id
    }

    /// Advances once the Pencil has stayed up for a moment.
    func scheduleAdvance(_ advance: @escaping @MainActor () -> Void) {
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: Self.advanceDelay)
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    /// The Pencil touched the panel again: the stroke is not the last one.
    func cancelAdvance() {
        advanceTask?.cancel()
        advanceTask = nil
    }
}

// MARK: - Panel

/// The panel under the page: a bar with the band buttons (its top edge
/// resizes the panel), then the magnified band with the canvas on top.
struct ZoomWindowPanel<Canvas: View>: View {
    let page: Page
    let band: ZoomBand?
    let assetsDirectory: URL?
    let height: CGFloat
    let showsAdvanceArea: Bool
    /// The band's paper is dark paper.
    var usesDarkPaper: Bool = false
    let onWritingSizeChange: (CGSize) -> Void
    /// The new panel height while dragging the bar, and whether the drag ended.
    let onResize: (CGFloat, Bool) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onNewLine: () -> Void
    let onClose: () -> Void
    @ViewBuilder let canvas: (ZoomBand) -> Canvas

    static var barHeight: CGFloat { 40 }
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            bar
            writingArea
        }
        .frame(height: height)
        .background(AppColor.groupedBackground)
    }

    private var bar: some View {
        HStack(spacing: 2) {
            barButton("Move Left", systemImage: "chevron.left", action: onBack)
            barButton("Move Right", systemImage: "chevron.right", action: onForward)
            barButton("New Line", systemImage: "arrow.turn.down.left", action: onNewLine)
            Spacer(minLength: 0)
            if let band {
                Text(String(format: "%.1f×", band.pageSize.width / max(band.rect.width, 1)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(format: "Magnification %.1f", band.pageSize.width / max(band.rect.width, 1)))
            }
            barButton("Close Zoom View", systemImage: "xmark", action: onClose)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) { Divider() }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartHeight ?? height
                    dragStartHeight = start
                    onResize(start - value.translation.height, false)
                }
                .onEnded { value in
                    let start = dragStartHeight ?? height
                    dragStartHeight = nil
                    onResize(start - value.translation.height, true)
                }
        )
        .accessibilityAction(named: "Make Taller") { onResize(height + 60, true) }
        .accessibilityAction(named: "Make Shorter") { onResize(height - 60, true) }
    }

    private func barButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private var writingArea: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let band, band.rect.width > 0 {
                    if showsAdvanceArea {
                        advanceArea(width: proxy.size.width * ZoomBand.advanceAreaFraction)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                    canvas(band)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            // The paper is far larger than the panel; as a background it
            // cannot change the panel's layout.
            .background(alignment: .topLeading) {
                if let band, band.rect.width > 0 {
                    let scale = band.scale(panelWidth: proxy.size.width)
                    PaperBackground(
                        page: page,
                        assetsDirectory: assetsDirectory,
                        zoomScale: scale,
                        usesDarkPaper: usesDarkPaper
                    )
                        .frame(width: page.width * scale, height: page.height * scale)
                        .offset(x: -band.rect.minX * scale, y: -band.rect.minY * scale)
                        .allowsHitTesting(false)
                } else {
                    AppColor.paper(usesDarkPaper: usesDarkPaper)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onWritingSizeChange)
    }

    /// The right part of the band: a stroke that ends here moves the band on.
    private func advanceArea(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.07))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                    .padding(8)
            }
            .frame(width: width)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Frame on the page

/// The band's outline on the page, in page points. Only the grab tab and the
/// corner handle take touches.
struct ZoomFrameOverlay: UIViewRepresentable {
    let band: CGRect
    let showsAdvanceArea: Bool
    /// The band's new origin while the tab is dragged, and whether it ended.
    let onMove: (CGPoint, Bool) -> Void
    /// The band's new width while the corner is dragged, and whether it ended.
    let onResize: (CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> ZoomFrameView {
        let view = ZoomFrameView()
        update(view)
        return view
    }

    func updateUIView(_ view: ZoomFrameView, context: Context) {
        update(view)
    }

    private func update(_ view: ZoomFrameView) {
        view.onMove = onMove
        view.onResize = onResize
        if view.band != band || view.showsAdvanceArea != showsAdvanceArea {
            view.band = band
            view.showsAdvanceArea = showsAdvanceArea
            view.setNeedsLayout()
        }
    }
}

final class ZoomFrameView: UIView {
    var band: CGRect = .zero
    var showsAdvanceArea = true
    var onMove: ((CGPoint, Bool) -> Void)?
    var onResize: ((CGFloat, Bool) -> Void)?

    private enum Handle { case move, resize }
    private var activeHandle: Handle?
    private var startBand: CGRect = .zero
    private var startPoint: CGPoint = .zero

    private let frameLayer = CAShapeLayer()
    private let advanceLayer = CAShapeLayer()
    private let tabLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()

    /// On-screen points per page point, so handles keep a finger's size
    /// whatever the page zoom.
    private var screenScale: CGFloat {
        let scale = convert(CGRect(x: 0, y: 0, width: 1, height: 1), to: nil).width
        return scale > 0.01 ? scale : 1
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        for shape in [advanceLayer, frameLayer, tabLayer, handleLayer] {
            layer.addSublayer(shape)
        }
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        addGestureRecognizer(press)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func tabRect(scale: CGFloat) -> CGRect {
        let size = CGSize(width: 64 / scale, height: 30 / scale)
        return CGRect(x: band.midX - size.width / 2, y: band.minY - size.height / 2, width: size.width, height: size.height)
    }

    private func handleRect(scale: CGFloat) -> CGRect {
        let side = 44 / scale
        return CGRect(x: band.maxX - side / 2, y: band.maxY - side / 2, width: side, height: side)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard band.width > 0, !isHidden, isUserInteractionEnabled else { return nil }
        let scale = screenScale
        return handle(at: point, scale: scale) == nil ? nil : self
    }

    private func handle(at point: CGPoint, scale: CGFloat) -> Handle? {
        if handleRect(scale: scale).contains(point) { return .resize }
        if tabRect(scale: scale).contains(point) { return .move }
        return nil
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = screenScale
        let tint = tintColor ?? .systemBlue
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        frameLayer.path = UIBezierPath(rect: band).cgPath
        frameLayer.fillColor = tint.withAlphaComponent(0.06).cgColor
        frameLayer.strokeColor = tint.withAlphaComponent(0.9).cgColor
        frameLayer.lineWidth = 1.5 / scale

        advanceLayer.isHidden = !showsAdvanceArea
        let areaWidth = band.width * ZoomBand.advanceAreaFraction
        advanceLayer.path = UIBezierPath(rect: CGRect(
            x: band.maxX - areaWidth, y: band.minY, width: areaWidth, height: band.height
        )).cgPath
        advanceLayer.fillColor = tint.withAlphaComponent(0.08).cgColor

        let tab = CGRect(x: band.midX - 18 / scale, y: band.minY - 3 / scale, width: 36 / scale, height: 6 / scale)
        tabLayer.path = UIBezierPath(roundedRect: tab, cornerRadius: 3 / scale).cgPath
        tabLayer.fillColor = tint.cgColor

        let radius = 8 / scale
        handleLayer.path = UIBezierPath(
            ovalIn: CGRect(x: band.maxX - radius, y: band.maxY - radius, width: radius * 2, height: radius * 2)
        ).cgPath
        handleLayer.fillColor = UIColor.white.cgColor
        handleLayer.strokeColor = tint.cgColor
        handleLayer.lineWidth = 2 / scale

        CATransaction.commit()
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            activeHandle = handle(at: point, scale: screenScale)
            startBand = band
            startPoint = point
        case .changed, .ended:
            let ended = gesture.state == .ended
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            switch activeHandle {
            case .move:
                onMove?(CGPoint(x: startBand.minX + dx, y: startBand.minY + dy), ended)
            case .resize:
                onResize?(startBand.width + dx, ended)
            case nil:
                break
            }
            if ended { activeHandle = nil }
        case .cancelled, .failed:
            switch activeHandle {
            case .move: onMove?(startBand.origin, true)
            case .resize: onResize?(startBand.width, true)
            case nil: break
            }
            activeHandle = nil
        default:
            break
        }
    }
}

// MARK: - Options

/// Zoom View settings, shown from the toolbar button and in Settings.
struct ZoomViewOptions: View {
    /// Shown as a Close button when set (the toolbar popover).
    var onClose: (() -> Void)?

    @AppStorage(AppSettings.Key.zoomAutoAdvance) private var autoAdvance = true
    @AppStorage(AppSettings.Key.zoomMagnification) private var magnification = ZoomBand.defaultMagnification

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if onClose != nil {
                Text("Zoom View")
                    .font(.headline)
            }
            ZoomViewSettingsRows(autoAdvance: $autoAdvance, magnification: $magnification)
            if let onClose {
                Button("Close Zoom View", systemImage: "xmark.circle", action: onClose)
            }
        }
    }
}

/// The two Zoom View settings, shared by the popover and the Settings form.
struct ZoomViewSettingsRows: View {
    @Binding var autoAdvance: Bool
    @Binding var magnification: Double

    var body: some View {
        Toggle("Auto-Advance", isOn: $autoAdvance)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Magnification")
                Spacer()
                Text(String(format: "%.1f×", ZoomBand.clampedMagnification(magnification)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { ZoomBand.clampedMagnification(magnification) },
                    set: { magnification = $0 }
                ),
                in: ZoomBand.magnificationRange,
                step: 0.1
            )
            .accessibilityLabel("Magnification")
        }
    }
}
#endif
