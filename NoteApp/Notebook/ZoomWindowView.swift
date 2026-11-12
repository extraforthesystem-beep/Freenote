#if os(iOS)
import InkKit
import NoteCore
import SwiftUI

// MARK: - Design
//
// Zoom View shows a magnified band of the active page in a panel under the
// page area; writing in the panel inks the page.
//
// The panel hosts a second `PencilCanvasView` over the *same* stroke records
// as the page canvas, in page coordinates. The canvas is a `PKCanvasView`
// (a scroll view), so instead of transforming strokes it is given a
// `viewport`: it zooms so the band fills its width and scrolls to the band's
// corner, with scrolling off. Records therefore round-trip unchanged (same
// ids, same coordinates, same active layer), and both canvases report through
// `session.strokesChanged`, the path every edit already takes.
//
// The two canvases do not fight: only the canvas being touched produces a
// change, and the other one receives it as new input. Each canvas's
// coordinator keeps a signature of the records it last exchanged, so input it
// already shows is not echoed back, and strokes appended elsewhere are decoded
// and appended without rebuilding the drawing.
//
// Undo: each PencilKit canvas owns its undo stack. While the panel is open the
// toolbar's undo controller drives the panel canvas, so undo removes panel
// strokes; two-finger double-tap on the page still undoes page strokes.
//
// Geometry (band size, advance, wrap, clamp) lives in `NoteCore.ZoomBand`.
// The paper and elements under the panel's ink are the page's own
// `PaperBackground`, scaled and offset to the band.

/// The band and the auto-advance bookkeeping, shared by the panel and the
/// frame drawn on the page.
@MainActor
@Observable
final class ZoomViewModel {
    /// The band for `pageID`; nil until the panel has a size.
    private(set) var band: ZoomBand?
    private(set) var pageID: UUID?

    /// Where the last stroke written in the panel ended, in page points.
    @ObservationIgnored private var lastStrokeEnd: CGPoint?
    /// When the Pencil last lifted with no stroke reported yet.
    @ObservationIgnored private var liftedAt: Date?

    /// Starts a band at the top-left margin when the page changed, otherwise
    /// follows the panel's shape.
    func sync(page: Page, aspect: Double, magnification: Double) {
        let size = CGSize(width: page.width, height: page.height)
        if pageID != page.id || band?.pageSize != size || band == nil {
            band = ZoomBand(pageSize: size, magnification: magnification, aspect: aspect)
            pageID = page.id
            lastStrokeEnd = nil
            liftedAt = nil
        } else if let band, abs(band.rect.height / max(band.rect.width, 1) - aspect) > 0.001 {
            self.band?.setAspect(aspect)
        }
    }

    func band(for page: Page) -> ZoomBand? {
        pageID == page.id ? band : nil
    }

    func advance() { band?.advance() }
    func moveBack() { band?.moveBack() }
    func newLine() { band?.newLine() }
    func move(to origin: CGPoint) { band?.move(to: origin) }
    func resize(toWidth width: Double) { band?.resize(toWidth: width) }
    func setMagnification(_ value: Double) { band?.setMagnification(value) }

    // MARK: Auto-advance

    /// The panel canvas reported `records`; `before` are the stroke ids the
    /// page had. Remembers where a newly written stroke ended.
    func noteStrokes(_ records: [StrokeRecord], before: Set<UUID>, autoAdvance: Bool) {
        guard let added = records.last(where: { !before.contains($0.id) }),
              let end = ZoomBand.endPoint(of: added)
        else { return }
        lastStrokeEnd = end
        if let liftedAt, Date().timeIntervalSince(liftedAt) < 0.6 {
            finishStroke(autoAdvance: autoAdvance)
        }
    }

    /// The Pencil lifted. The stroke may be reported a moment before or
    /// after this, so whichever comes second decides.
    func penLifted(drawsInk: Bool, autoAdvance: Bool) {
        guard drawsInk else {
            lastStrokeEnd = nil
            return
        }
        if lastStrokeEnd != nil {
            finishStroke(autoAdvance: autoAdvance)
        } else {
            liftedAt = Date()
        }
    }

    private func finishStroke(autoAdvance: Bool) {
        defer {
            lastStrokeEnd = nil
            liftedAt = nil
        }
        guard autoAdvance, let end = lastStrokeEnd, let band, band.isInAdvanceArea(end) else { return }
        withAnimation(.easeOut(duration: 0.18)) { self.band?.advance() }
    }
}

/// The bottom panel: a magnified band of the page with a live canvas on top.
struct ZoomWindowPanel<Canvas: View>: View {
    let page: Page
    let assetsDirectory: URL?
    @Bindable var zoom: ZoomViewModel
    /// The pane height the panel shares with the page area.
    let availableHeight: CGFloat
    let onClose: () -> Void
    /// The panel's canvas for a band (page points).
    @ViewBuilder let canvas: (CGRect) -> Canvas

    @AppStorage(AppSettings.Key.zoomViewAutoAdvance) private var autoAdvance = true
    @AppStorage(AppSettings.Key.zoomViewMagnification) private var magnification = ZoomBand.defaultMagnification
    @AppStorage(AppSettings.Key.zoomViewPanelFraction) private var panelFraction = 0.35
    @State private var dragStartHeight: CGFloat?

    private static var barHeight: CGFloat { 40 }
    private static var minimumHeight: CGFloat { 140 }

    private var panelHeight: CGFloat {
        let maximum = max(Self.minimumHeight, availableHeight * 0.7)
        return min(max(availableHeight * panelFraction, Self.minimumHeight), maximum)
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            GeometryReader { proxy in
                bandView(size: proxy.size)
                    .onAppear { syncBand(size: proxy.size) }
                    .onChange(of: proxy.size) { _, size in syncBand(size: size) }
                    .onChange(of: page.id) { syncBand(size: proxy.size) }
                    .onChange(of: magnification) { _, value in
                        if let band = zoom.band, abs(band.magnification - value) > 0.01 {
                            zoom.setMagnification(value)
                        }
                    }
            }
        }
        .frame(height: panelHeight)
        .background(AppColor.groupedBackground)
    }

    // MARK: Band

    private func syncBand(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        zoom.sync(page: page, aspect: size.height / size.width, magnification: magnification)
    }

    @ViewBuilder
    private func bandView(size: CGSize) -> some View {
        if let band = zoom.band(for: page), size.width > 0 {
            let scale = band.panelScale(panelWidth: size.width)
            ZStack(alignment: .topLeading) {
                PaperBackground(
                    page: NotebookPane.removingTape(from: page),
                    assetsDirectory: assetsDirectory,
                    zoomScale: scale
                )
                .frame(width: page.width, height: page.height)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: -band.rect.minX * scale, y: -band.rect.minY * scale)
                .allowsHitTesting(false)

                if autoAdvance {
                    advanceArea(width: size.width * ZoomBand.advanceAreaFraction, height: size.height)
                        .frame(width: size.width, height: size.height, alignment: .trailing)
                        .allowsHitTesting(false)
                }

                canvas(band.rect)
                    .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        } else {
            Color.white
        }
    }

    private func advanceArea(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.07))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                    .padding(.bottom, 6)
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 2) {
            ToolbarIconButton("Move Left", systemImage: "chevron.left") {
                withAnimation(.easeOut(duration: 0.18)) { zoom.moveBack() }
            }
            ToolbarIconButton("Move Right", systemImage: "chevron.right") {
                withAnimation(.easeOut(duration: 0.18)) { zoom.advance() }
            }
            ToolbarIconButton("New Line", systemImage: "return") {
                withAnimation(.easeOut(duration: 0.18)) { zoom.newLine() }
            }
            Spacer(minLength: 8)
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 44, height: 5)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            ToolbarIconButton(
                autoAdvance ? "Auto-Advance, on" : "Auto-Advance, off",
                systemImage: "arrow.right.to.line",
                isSelected: autoAdvance,
                help: "Auto-Advance: move on when writing reaches the right edge"
            ) {
                autoAdvance.toggle()
            }
            ToolbarIconButton("Close Zoom View", systemImage: "xmark", action: onClose)
        }
        .padding(.horizontal, 6)
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        // Drag the bar to make the panel taller or shorter.
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStartHeight ?? panelHeight
                    dragStartHeight = start
                    guard availableHeight > 0 else { return }
                    let height = start - value.translation.height
                    let maximum = max(Self.minimumHeight, availableHeight * 0.7)
                    panelFraction = min(max(height, Self.minimumHeight), maximum) / availableHeight
                }
                .onEnded { _ in dragStartHeight = nil }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zoom View")
    }
}

/// The band's outline on the page, with a handle to move it (top left) and
/// one to resize it (bottom right). Drawn in page points inside the page
/// content; the inside lets touches through to the page canvas.
struct ZoomBandFrame: View {
    let band: ZoomBand
    /// The page's zoom, so lines and handles keep their on-screen size.
    let pageZoom: CGFloat
    let onMove: (CGPoint) -> Void
    let onResize: (Double) -> Void
    let onResizeEnded: () -> Void

    @State private var moveStart: CGPoint?
    @State private var resizeStart: Double?

    static let coordinateSpace = "zoomBandPage"

    var body: some View {
        let zoom = max(pageZoom, 0.1)
        let handle = 30 / zoom
        let rect = band.rect
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.06))
                .overlay(
                    Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2 / zoom)
                )
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.07))
                        .frame(width: rect.width * ZoomBand.advanceAreaFraction)
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)

            handleView(systemImage: "arrow.up.and.down.and.arrow.left.and.right", size: handle)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(moveGesture)
                .accessibilityLabel("Move Zoom View band")

            handleView(systemImage: "arrow.up.left.and.arrow.down.right", size: handle)
                .offset(x: rect.maxX - handle, y: rect.maxY - handle)
                .gesture(resizeGesture)
                .accessibilityLabel("Resize Zoom View band")
        }
    }

    private func handleView(systemImage: String, size: CGFloat) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: size * 0.2))
            .contentShape(Rectangle())
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                let start = moveStart ?? band.rect.origin
                moveStart = start
                onMove(CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
            }
            .onEnded { _ in moveStart = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                let start = resizeStart ?? band.rect.width
                resizeStart = start
                onResize(start + value.translation.width)
            }
            .onEnded { _ in
                resizeStart = nil
                onResizeEnded()
            }
    }
}

/// Zoom View options, shown when the active Zoom View button is tapped again.
struct ZoomViewSettingsPopover: View {
    let onClose: () -> Void

    @AppStorage(AppSettings.Key.zoomViewAutoAdvance) private var autoAdvance = true
    @AppStorage(AppSettings.Key.zoomViewMagnification) private var magnification = ZoomBand.defaultMagnification

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Zoom View").font(.headline)
            Toggle("Auto-Advance", isOn: $autoAdvance)
            VStack(alignment: .leading, spacing: 4) {
                Text("Magnification \(magnification, format: .number.precision(.fractionLength(1)))×")
                    .font(.subheadline)
                Slider(
                    value: $magnification,
                    in: ZoomBand.minimumMagnification...ZoomBand.maximumMagnification,
                    step: 0.1
                )
            }
            Button("Close Zoom View", role: .destructive, action: onClose)
        }
        .padding()
        .frame(width: 280)
    }
}
#endif
