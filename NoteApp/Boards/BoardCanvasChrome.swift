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

/// Text, shape and image items in page space, under the ink so a board can be
/// annotated over them. Phase 2 adds selection and editing; this layer only
/// draws.
struct BoardItemLayer: View {
    let items: [BoardItem]
    let viewport: BoardViewportState
    let assetsDirectory: URL

    var body: some View {
        let zoom = viewport.zoom
        let visible = viewport.visibleRect
        return ZStack(alignment: .topLeading) {
            if visible.width > 0 {
                ForEach(items) { item in
                    if let frame = item.frame, frame.intersects(visible) {
                        BoardItemView(item: item, assetsDirectory: assetsDirectory)
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
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BoardItemView: View {
    let item: BoardItem
    let assetsDirectory: URL

    var body: some View {
        switch item.content {
        case let .text(string, _, fontSize, color):
            Text(string)
                .font(.system(size: CGFloat(fontSize)))
                .foregroundStyle(Color(color))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        case let .shape(kind, _, strokeColor, fillColor, lineWidth):
            BoardShapeView(
                kind: kind,
                stroke: Color(strokeColor),
                fill: fillColor.map { Color($0) },
                lineWidth: CGFloat(lineWidth)
            )
        case let .image(assetName, _):
            BoardImageView(assetName: assetName, assetsDirectory: assetsDirectory)
        case .ink, .connector:
            EmptyView()
        }
    }
}

private struct BoardShapeView: View {
    let kind: BoardShapeKind
    let stroke: Color
    let fill: Color?
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let inset = max(lineWidth, 0) / 2
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            guard rect.width > 0, rect.height > 0 else { return }
            let path = Self.path(for: kind, in: rect)
            if let fill {
                context.fill(path, with: .color(fill))
            }
            context.stroke(
                path,
                with: .color(stroke),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private static func path(for kind: BoardShapeKind, in rect: CGRect) -> Path {
        switch kind {
        case .rectangle:
            return Path(rect)
        case .roundedRectangle:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.12)
        case .ellipse:
            return Path(ellipseIn: rect)
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        case .line:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        case .arrow:
            var path = Path()
            let start = CGPoint(x: rect.minX, y: rect.maxY)
            let end = CGPoint(x: rect.maxX, y: rect.minY)
            path.move(to: start)
            path.addLine(to: end)
            let head = min(rect.width, rect.height) * 0.2
            path.move(to: CGPoint(x: end.x - head, y: end.y))
            path.addLine(to: end)
            path.addLine(to: CGPoint(x: end.x, y: end.y + head))
            return path
        case .star:
            var path = Path()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outer = min(rect.width, rect.height) / 2
            let inner = outer * 0.42
            for index in 0..<10 {
                let radius = index.isMultiple(of: 2) ? outer : inner
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                let point = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            return path
        }
    }
}

private struct BoardImageView: View {
    let assetName: String
    let assetsDirectory: URL

    var body: some View {
        if let image = UIImage(contentsOfFile: assetsDirectory.appendingPathComponent(assetName).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .overlay {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
        }
    }
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
