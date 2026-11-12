import BoardKit
import InkKit
import NoteCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// A small preview of a board's ink, drawn off the main actor.
///
/// Boards are 3,000 points square, so a full-page render is wasteful. The ink
/// is rendered only inside its own bounds at thumbnail resolution instead.
struct BoardThumbnail: View {
    let board: Board
    var side: CGFloat = 52

    @State private var image: CGImage?

    /// Every visible ink item on the board, in draw order.
    private var strokes: [StrokeRecord] {
        board.visibleItems.flatMap { item -> [StrokeRecord] in
            if case let .ink(strokes) = item.content { return strokes }
            return []
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(paperColor)

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                Image(systemName: "scribble.variable")
                    .font(.system(size: side * 0.42))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .task(id: board.updatedAt) {
            await render()
        }
    }

    private var paperColor: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    private func render() async {
        let strokes = self.strokes
        guard !strokes.isEmpty else {
            image = nil
            return
        }
        let bounds = board.bounds()
        guard let bounds, bounds.width > 0, bounds.height > 0 else {
            image = nil
            return
        }
        let pixels = side * 3
        let rendered = await Task.detached(priority: .utility) {
            BoardInkThumbnail.renderer(strokes: strokes, bounds: bounds, pixels: pixels)
        }.value
        guard !Task.isCancelled else { return }
        image = rendered
    }
}

/// Renders ink only; the paper and border are drawn by `BoardThumbnail`.
enum BoardInkThumbnail {
    /// Draws the ink inside a square crop around `bounds`.
    ///
    /// Returns a `CGImage` so the work can run off the main actor and the
    /// caller can build the platform image cheaply.
    nonisolated static func renderer(
        strokes: [StrokeRecord],
        bounds: CGRect,
        pixels: CGFloat
    ) -> CGImage? {
        guard !strokes.isEmpty, pixels > 0 else { return nil }

        let padding = max(bounds.width, bounds.height) * 0.08
        let side = max(bounds.width, bounds.height) + padding * 2
        guard side > 0 else { return nil }
        let crop = CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )

        let drawing = StrokeCodec.drawing(from: strokes)
        let scale = pixels / side
        let image = drawing.image(from: crop, scale: scale)
        #if os(macOS)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }
}
