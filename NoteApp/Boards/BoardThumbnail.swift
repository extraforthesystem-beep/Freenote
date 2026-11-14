import BoardKit
import InkKit
import NoteCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// A small preview of a board: its objects, then its ink over them.
///
/// Boards are 3,000 points square, so a full-page render is wasteful. The ink
/// is rendered only inside a square crop of the board's content at thumbnail
/// resolution instead, and the objects are drawn by the board's own item views
/// in the same crop.
struct BoardThumbnail: View {
    let board: Board
    var side: CGFloat = 52
    /// Folder holding the board's images, drawn with the other objects.
    let assetsDirectory: URL

    @State private var image: CGImage?

    /// Every visible ink item on the board, in draw order.
    private var strokes: [StrokeRecord] {
        board.visibleItems.flatMap { item -> [StrokeRecord] in
            if case let .ink(strokes) = item.content { return strokes }
            return []
        }
    }

    /// The square around the board's content that the thumbnail shows, with a
    /// little room at the edges. The objects and the ink share it, so they line
    /// up as they do on the board.
    private var crop: CGRect? {
        guard let bounds = board.bounds(), bounds.width > 0, bounds.height > 0 else {
            return nil
        }
        let padding = max(bounds.width, bounds.height) * 0.08
        let side = max(bounds.width, bounds.height) + padding * 2
        return CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(paperColor)

            if let crop {
                BoardStaticItemLayer(
                    items: board.frameBackedItems(in: crop),
                    content: crop,
                    scale: side / crop.width,
                    assetsDirectory: assetsDirectory
                )
                .frame(width: side, height: side)

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: side, height: side)
                }
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
        guard !strokes.isEmpty, let crop else {
            image = nil
            return
        }
        let pixels = side * 3
        // A detached task does not inherit this view's `.task` cancellation, so
        // pass it on: a board scrolled out of the list is skipped instead of
        // building a drawing from all its strokes and rasterising it.
        let render = Task.detached(priority: .utility) { () -> CGImage? in
            guard !Task.isCancelled else { return nil }
            return BoardInkThumbnail.renderer(strokes: strokes, crop: crop, pixels: pixels)
        }
        let rendered = await withTaskCancellationHandler {
            await render.value
        } onCancel: {
            render.cancel()
        }
        guard !Task.isCancelled else { return }
        image = rendered
    }
}

/// Renders ink only; the paper, the objects under it and the border are drawn
/// by `BoardThumbnail`.
enum BoardInkThumbnail {
    /// Draws the ink inside `crop`.
    ///
    /// Returns a `CGImage` so the work can run off the main actor and the
    /// caller can build the platform image cheaply.
    nonisolated static func renderer(
        strokes: [StrokeRecord],
        crop: CGRect,
        pixels: CGFloat
    ) -> CGImage? {
        guard !strokes.isEmpty, pixels > 0, crop.width > 0, crop.height > 0 else { return nil }

        let drawing = StrokeCodec.drawing(from: strokes)
        let scale = pixels / crop.width
        let image = drawing.image(from: crop, scale: scale)
        #if os(macOS)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }
}
