#if os(iOS)
import BoardKit
import NoteCore
import Observation
import SwiftUI
import UIKit

/// The board canvas's visible window: the page points on screen and the zoom
/// scale. Updated by the Pencil canvas on every pan and zoom, read by the grid,
/// the item layer and the zoom pill.
@MainActor
@Observable
final class BoardViewportState {
    /// The visible part of the page, in page points.
    private(set) var visibleRect = CGRect.zero
    /// View points per page point.
    private(set) var zoom: CGFloat = 1

    var isReady: Bool { visibleRect.width > 0 && visibleRect.height > 0 }

    func update(visibleRect: CGRect, zoom: CGFloat) {
        guard visibleRect.width > 0, visibleRect.height > 0, zoom > 0 else { return }
        if abs(visibleRect.minX - self.visibleRect.minX) < 0.01,
           abs(visibleRect.minY - self.visibleRect.minY) < 0.01,
           abs(visibleRect.width - self.visibleRect.width) < 0.01,
           abs(visibleRect.height - self.visibleRect.height) < 0.01,
           abs(zoom - self.zoom) < 0.0001 {
            return
        }
        self.visibleRect = visibleRect
        self.zoom = zoom
    }
}

/// A dot grid in page space, under the transparent ink canvas. Only the dots
/// on screen are drawn; far-out zooms use a wider stride so the grid stays
/// cheap instead of turning into a solid wash.
struct BoardDotGrid: View {
    let viewport: BoardViewportState
    var isVisible = true
    /// Page point that dot 0 lines up with: the board's stored origin.
    var origin = CGPoint.zero

    private static let spacing: CGFloat = 48
    private static let minimumScreenSpacing: CGFloat = 18

    var body: some View {
        let zoom = viewport.zoom
        let visible = viewport.visibleRect
        return Canvas { context, _ in
            guard isVisible, zoom > 0, visible.width > 0, visible.height > 0 else { return }

            var step = Self.spacing
            while step * zoom < Self.minimumScreenSpacing { step *= 2 }

            let radius = min(max(1.1, 1.4 * zoom), 2.4)
            let startX = Self.firstDot(after: visible.minX, origin: origin.x, step: step)
            let startY = Self.firstDot(after: visible.minY, origin: origin.y, step: step)
            var dots = Path()

            for y in stride(from: startY, to: visible.maxY, by: step) {
                let screenY = (y - visible.minY) * zoom
                for x in stride(from: startX, to: visible.maxX, by: step) {
                    let screenX = (x - visible.minX) * zoom
                    dots.addEllipse(in: CGRect(
                        x: screenX - radius,
                        y: screenY - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                }
            }
            context.fill(dots, with: .color(Color.black.opacity(0.16)))
        }
        .background(AppColor.paper(usesDarkPaper: false))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func firstDot(after minimum: CGFloat, origin: CGFloat, step: CGFloat) -> CGFloat {
        guard step > 0 else { return origin }
        return origin + ((minimum - origin) / step).rounded(.up) * step
    }
}

/// The board's objects, culled to what the viewport shows.
///
/// The visible slice is computed here, once per viewport change, so the layer
/// below builds one element per item on screen instead of one per item on the
/// board. It is a child of the canvas so a pan re-runs this body, not the
/// canvas representable or the toolbar around it.
struct BoardVisibleItemLayer: View {
    let board: Board
    let viewport: BoardViewportState
    /// The selected object. It is kept even when it is dragged past the edge,
    /// so its outline and handles never vanish mid-gesture.
    var selectedItemID: UUID?
    let assetsDirectory: URL
    var reduceMotion = false
    /// The item whose text is being typed into above the canvas.
    var editingItemID: UUID?

    /// Screen points of extra room, so an object is built just before its edge
    /// scrolls in rather than on the frame it appears.
    private static let margin: CGFloat = 64

    var body: some View {
        BoardItemLayer(
            items: visibleItems,
            viewport: viewport,
            assetsDirectory: assetsDirectory,
            reduceMotion: reduceMotion,
            editingItemID: editingItemID
        )
    }

    private var visibleItems: [BoardItem] {
        guard viewport.isReady else { return [] }
        let inset = Self.margin / max(viewport.zoom, 0.001)
        let rect = viewport.visibleRect.insetBy(dx: -inset, dy: -inset)
        return board.frameBackedItems(
            in: rect,
            alwaysIncluding: Set([selectedItemID].compactMap { $0 })
        )
    }
}

/// Sticky notes, text, shapes and images in page space, under the ink so a
/// board can be annotated over them.
///
/// `items` is already culled by `BoardVisibleItemLayer`, so this builds only
/// the objects on screen.
struct BoardItemLayer: View {
    let items: [BoardItem]
    let viewport: BoardViewportState
    let assetsDirectory: URL
    var reduceMotion = false
    /// The item whose text is being typed into above the canvas.
    var editingItemID: UUID?

    var body: some View {
        let zoom = viewport.zoom
        let visible = viewport.visibleRect
        return ZStack(alignment: .topLeading) {
            if visible.width > 0 {
                ForEach(items) { item in
                    if let frame = item.frame {
                        BoardItemView(
                            item: item,
                            assetsDirectory: assetsDirectory,
                            hidesText: item.id == editingItemID
                        )
                            .frame(
                                width: max(frame.width, 1),
                                height: max(frame.height, 1),
                                alignment: .topLeading
                            )
                            .scaleEffect(zoom, anchor: .topLeading)
                            .offset(
                                x: (frame.minX - visible.minX) * zoom,
                                y: (frame.minY - visible.minY) * zoom
                            )
                            .transition(transition)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Inserted objects spring in from 90 %; a delete only fades.
    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .opacity
            )
    }
}

// MARK: - Selection geometry

/// One of the four round handles on a selection.
enum BoardResizeCorner: CaseIterable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    /// Where the handle sits in a rectangle, in the rectangle's space.
    func point(in frame: CGRect) -> CGPoint {
        CGPoint(x: isLeft ? frame.minX : frame.maxX, y: isTop ? frame.minY : frame.maxY)
    }

    /// The corner whose handle is within `tolerance` of a point.
    static func corner(
        at point: CGPoint,
        in frame: CGRect,
        tolerance: CGFloat
    ) -> BoardResizeCorner? {
        allCases.first { corner in
            let handle = corner.point(in: frame)
            return abs(point.x - handle.x) <= tolerance && abs(point.y - handle.y) <= tolerance
        }
    }
}

// MARK: - Selection chrome

/// The selection's outline, corner handles, snap guides and floating bar.
/// It exists only while a board object is selected, and only the bar takes
/// touches, so the canvas keeps panning and the Pencil keeps inking.
struct BoardSelectionOverlay: View {
    let item: BoardItem
    let viewport: BoardViewportState
    let guides: [BoardSnapGuide]
    /// The keyboard is up: the bar would sit under it, so the outline stays
    /// and the bar goes.
    var isEditing = false
    let reduceMotion: Bool
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void
    let onColor: (RGBAColor) -> Void
    let onFillColor: (RGBAColor?) -> Void
    let onEditText: () -> Void

    private static let handleSize: CGFloat = 11
    private static let barHalfWidth: CGFloat = 170

    var body: some View {
        GeometryReader { proxy in
            if let frame = item.frame, viewport.isReady {
                let rect = viewRect(frame, in: proxy.size)

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .strokeBorder(Color.selectionBlue, lineWidth: 1.5)
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)

                    ForEach(BoardResizeCorner.allCases, id: \.self) { corner in
                        Circle()
                            .fill(Color.selectionBlue)
                            .frame(width: Self.handleSize, height: Self.handleSize)
                            .offset(
                                x: corner.point(in: rect).x - Self.handleSize / 2,
                                y: corner.point(in: rect).y - Self.handleSize / 2
                            )
                    }

                    ForEach(guides) { guide in
                        Rectangle()
                            .fill(Color.selectionBlue.opacity(0.65))
                            .frame(
                                width: guide.axis == .vertical ? 1 : proxy.size.width,
                                height: guide.axis == .horizontal ? 1 : proxy.size.height
                            )
                            .offset(
                                x: guide.axis == .vertical
                                    ? (guide.position - viewport.visibleRect.minX) * viewport.zoom
                                    : 0,
                                y: guide.axis == .horizontal
                                    ? (guide.position - viewport.visibleRect.minY) * viewport.zoom
                                    : 0
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                if !isEditing {
                    BoardSelectionBar(
                        color: selectedColor,
                        supportsFill: supportsFill,
                        canEditText: isTextLike,
                        onDuplicate: onDuplicate,
                        onDelete: onDelete,
                        onBringToFront: onBringToFront,
                        onSendToBack: onSendToBack,
                        onColor: onColor,
                        onFillColor: onFillColor,
                        onEditText: onEditText
                    )
                    .position(
                        x: min(
                            max(rect.midX, Self.barHalfWidth),
                            max(proxy.size.width - Self.barHalfWidth, Self.barHalfWidth)
                        ),
                        y: rect.minY > 72 ? rect.minY - 32 : rect.minY + rect.height + 32
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.95))
                    )
                }
            }
        }
    }

    private var isTextLike: Bool {
        switch item.content {
        case .text, .sticky: true
        default: false
        }
    }

    /// The colour the bar's palette starts from, when the item has one.
    private var selectedColor: RGBAColor? {
        switch item.content {
        case let .sticky(_, _, color): color
        case let .shape(_, _, strokeColor, _, _): strokeColor
        default: nil
        }
    }

    /// Whether a fill would show: lines and arrows are open paths.
    private var supportsFill: Bool {
        if case let .shape(kind, _, _, _, _) = item.content {
            return kind != .line && kind != .arrow
        }
        return false
    }

    private func viewRect(_ frame: CGRect, in size: CGSize) -> CGRect {
        let visible = viewport.visibleRect
        let zoom = viewport.zoom
        return CGRect(
            x: (frame.minX - visible.minX) * zoom,
            y: (frame.minY - visible.minY) * zoom,
            width: frame.width * zoom,
            height: frame.height * zoom
        )
    }
}

/// The capsule that hugs the selection.
private struct BoardSelectionBar: View {
    let color: RGBAColor?
    /// Whether the item can be filled at all (not a line or an arrow).
    let supportsFill: Bool
    let canEditText: Bool
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onBringToFront: () -> Void
    let onSendToBack: () -> Void
    let onColor: (RGBAColor) -> Void
    let onFillColor: (RGBAColor?) -> Void
    let onEditText: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("Duplicate", "plus.square.on.square", action: onDuplicate)
            button("Delete", "trash", action: onDelete)
            Divider().frame(height: 20)
            button("Bring to Front", "square.3.layers.3d.top.filled", action: onBringToFront)
            button("Send to Back", "square.3.layers.3d.bottom.filled", action: onSendToBack)
            if canEditText || color != nil {
                Divider().frame(height: 20)
            }
            if canEditText {
                button("Edit Text", "character.cursor.ibeam", action: onEditText)
            }
            if color != nil {
                colorMenu
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }

    private func button(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    /// A shape gets a line colour and a fill; a sticky note has one colour.
    private var colorMenu: some View {
        Menu {
            if supportsFill {
                Menu("Line") { swatches { onColor($0) } }
                Menu("Fill") {
                    Button("None") { onFillColor(nil) }
                    Divider()
                    swatches { onFillColor(Self.fill($0)) }
                }
            } else {
                swatches { onColor($0) }
            }
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Colour")
    }

    private func swatches(_ select: @escaping (RGBAColor) -> Void) -> some View {
        ForEach(Array(BoardStickyPalette.colors.enumerated()), id: \.offset) { index, swatch in
            Button(BoardStickyPalette.names[index]) { select(swatch) }
        }
    }

    /// A fill tint: the palette colour, light enough to keep the shape's line
    /// and any ink over it readable.
    private static func fill(_ color: RGBAColor) -> RGBAColor {
        RGBAColor(r: color.r, g: color.g, b: color.b, a: 0.35)
    }
}

/// The in-place editor over a selected sticky note or text box. Its font size
/// follows the zoom so it sits exactly where the text will land.
struct BoardTextEditor: View {
    let frame: CGRect
    let viewport: BoardViewportState
    let isSticky: Bool
    /// The text box's stored font size; a sticky note shrinks its own.
    let textFontSize: CGFloat
    let textColor: Color
    @Binding var text: String
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let zoom = max(viewport.zoom, 0.05)
            let visible = viewport.visibleRect
            let x = (frame.minX - visible.minX) * zoom
            let y = (frame.minY - visible.minY) * zoom
            let height = max(frame.height * zoom, 32)
            let fontSize = isSticky
                ? BoardStickyText.fontSize(for: text, in: frame.size)
                : textFontSize

            ZStack(alignment: .topLeading) {
                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: fontSize * zoom))
                    .foregroundStyle(textColor)
                    .textFieldStyle(.plain)
                    .padding(isSticky ? BoardStickyText.padding * zoom : 2 * zoom)
                    .frame(width: max(frame.width * zoom, 40), height: height, alignment: .topLeading)
                    .offset(x: x, y: y)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
                    .onAppear { isFocused = true }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { onSubmit() }
                    }

                // A hardware keyboard has no dismiss key, and a sticky note's
                // growing text can cover the keyboard's Done button.
                Button("Done", action: onSubmit)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(.regularMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08)) }
                    .offset(x: x, y: y > 44 ? y - 40 : y + height + 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

private extension Color {
    /// The selection chrome's blue, as in Freeform.
    static let selectionBlue = Color(uiColor: .systemBlue)
}

/// The zoom readout at the bottom-left. Tapping it opens the presets and
/// Zoom to Fit, as in Freeform.
struct BoardZoomPill: View {
    let viewport: BoardViewportState
    let onFit: () -> Void
    let onZoom: (CGFloat) -> Void

    private static let presets: [(title: String, zoom: CGFloat)] = [
        ("50%", 0.5),
        ("100%", 1),
        ("200%", 2),
    ]

    var body: some View {
        Menu {
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                onFit()
            }
            Divider()
            ForEach(Self.presets, id: \.title) { preset in
                Button(preset.title) { onZoom(preset.zoom) }
            }
        } label: {
            Text(percentText)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.08))
                }
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom \(percentText)")
        .accessibilityHint("Opens Zoom to Fit and zoom presets")
        .help("Zoom")
    }

    private var percentText: String {
        "\(Int((viewport.zoom * 100).rounded()))%"
    }
}

/// The dot-grid switch at the bottom-right, matching Freeform's.
struct BoardGridToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "circle.grid.3x3.fill" : "circle.grid.3x3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 36)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.08))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Hide Dot Grid" : "Show Dot Grid")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(isOn ? "Hide the dot grid" : "Show a dot grid")
    }
}
#endif
