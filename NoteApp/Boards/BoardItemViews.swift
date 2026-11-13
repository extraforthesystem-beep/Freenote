import BoardKit
import NoteCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The six pastel card colours the board's sticky notes offer.
enum BoardStickyPalette {
    static let names = ["Yellow", "Pink", "Blue", "Green", "Purple", "Orange"]

    static let colors: [RGBAColor] = [
        RGBAColor(r: 1.00, g: 0.94, b: 0.60),
        RGBAColor(r: 1.00, g: 0.80, b: 0.86),
        RGBAColor(r: 0.76, g: 0.88, b: 0.99),
        RGBAColor(r: 0.79, g: 0.94, b: 0.72),
        RGBAColor(r: 0.87, g: 0.83, b: 0.98),
        RGBAColor(r: 1.00, g: 0.87, b: 0.70),
    ]

    static var defaultColor: RGBAColor { colors[0] }
}

/// The default size of a sticky note, as in Freeform.
let boardStickySize = CGSize(width: 200, height: 200)

/// One frame-backed item on the board, drawn at its own size by the caller.
struct BoardItemView: View {
    let item: BoardItem
    let assetsDirectory: URL
    /// The in-place editor draws the text while a note is being typed into, so
    /// the view underneath only keeps its paper.
    var hidesText = false

    var body: some View {
        switch item.content {
        case let .text(string, _, fontSize, color):
            Text(hidesText ? "" : string)
                .font(.system(size: CGFloat(fontSize)))
                .foregroundStyle(Color(color))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        case let .sticky(string, frame, color):
            StickyNoteElementView(
                text: hidesText ? "" : string,
                color: color,
                fontSize: BoardStickyText.fontSize(for: string, in: frame.size)
            )
        case let .shape(kind, _, strokeColor, fillColor, lineWidth):
            BoardShapeView(
                kind: kind,
                stroke: Color(strokeColor),
                fill: fillColor.map { Color($0) },
                lineWidth: CGFloat(lineWidth)
            )
        case let .image(assetName, _):
            BoardAssetImage(assetName: assetName, assetsDirectory: assetsDirectory)
        case .ink, .connector:
            EmptyView()
        }
    }
}

/// Shrinks sticky-note text until it fits the card, rather than spilling over
/// its edge. The estimate only needs to be close: it drives a font size, and
/// the smallest size is still readable.
enum BoardStickyText {
    static let padding: CGFloat = 12
    private static let maximum: CGFloat = 18
    private static let minimum: CGFloat = 9

    static func fontSize(for text: String, in box: CGSize) -> CGFloat {
        guard !text.isEmpty, box.width > 1, box.height > 1 else { return maximum }

        let availableWidth = max(box.width - padding * 2, 1)
        let availableHeight = max(box.height - padding * 2, 1)
        var candidate = maximum

        while candidate > minimum {
            let charactersPerLine = max(1, Int(availableWidth / (candidate * 0.52)))
            var lines = 0
            for line in text.components(separatedBy: .newlines) {
                lines += max(1, Int((Double(line.count) / Double(charactersPerLine)).rounded(.up)))
            }
            if CGFloat(lines) * candidate * 1.25 <= availableHeight {
                return candidate
            }
            candidate -= 1
        }
        return minimum
    }
}

struct BoardShapeView: View {
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

/// A board image, read from the board assets folder on either platform.
struct BoardAssetImage: View {
    let assetName: String
    let assetsDirectory: URL

    var body: some View {
        Group {
            #if os(iOS)
            if let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                placeholder
            }
            #else
            if let image = NSImage(contentsOf: assetsDirectory.appendingPathComponent(assetName)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                placeholder
            }
            #endif
        }
    }

    private var path: String {
        assetsDirectory.appendingPathComponent(assetName).path
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.secondary.opacity(0.10))
            .overlay {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
    }
}

/// Frame-backed items laid out inside a world rectangle, for the Mac's static
/// render. The iOS canvas uses `BoardItemLayer` instead, which follows the
/// viewport.
struct BoardStaticItemLayer: View {
    let items: [BoardItem]
    /// The world rectangle the layer covers.
    let content: CGRect
    let scale: CGFloat
    let assetsDirectory: URL

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                if let frame = item.frame {
                    BoardItemView(item: item, assetsDirectory: assetsDirectory)
                        .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                        .scaleEffect(scale, anchor: .topLeading)
                        // The scaled view takes the size it is drawn at, so a
                        // container much smaller than the item (a thumbnail)
                        // still places it at its offset.
                        .frame(
                            width: max(frame.width * scale, 0.01),
                            height: max(frame.height * scale, 0.01),
                            alignment: .topLeading
                        )
                        .offset(
                            x: (frame.minX - content.minX) * scale,
                            y: (frame.minY - content.minY) * scale
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension BoardShapeKind {
    /// The Insert menu's name for this shape.
    var displayName: String {
        switch self {
        case .rectangle: "Rectangle"
        case .roundedRectangle: "Rounded Rectangle"
        case .ellipse: "Ellipse"
        case .triangle: "Triangle"
        case .line: "Line"
        case .arrow: "Arrow"
        case .star: "Star"
        }
    }

    /// The Insert menu's symbol for this shape.
    var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .roundedRectangle: "rectangle.roundedtop"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .star: "star"
        }
    }
}
