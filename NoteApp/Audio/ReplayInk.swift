import NoteCore
import SwiftUI

/// Ink and the audio playhead: which strokes belong to the moment being played,
/// and how the ones ahead of it look.
enum ReplayInk {
    /// How much of its colour an ink stroke keeps while it is still ahead of
    /// the recording.
    static let fadeAlpha = 0.18
    /// The faintest a highlighter may become; a highlighter is already
    /// translucent, so a plain multiply would erase it.
    static let minimumFadeAlpha = 0.06

    /// The strokes written after `cutoff`, faded, so the page shows where the
    /// recording has not reached yet. Every other stroke is returned as it is.
    static func fading(_ strokes: [StrokeRecord], after cutoff: Date) -> [StrokeRecord] {
        strokes.map { stroke in
            guard stroke.createdAt > cutoff else { return stroke }
            var faded = stroke
            faded.tool.color.a = max(
                minimumFadeAlpha,
                stroke.tool.color.a * fadeAlpha
            )
            return faded
        }
    }
}

/// The dot that shows where the audio playhead meets the ink.
struct NowPlayingMarker: View {
    let point: CGPoint

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 34, height: 34)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 11, height: 11)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
                }
        }
        .position(x: point.x, y: point.y)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
