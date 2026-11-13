import AudioKit
import SwiftUI

/// Controls for the recording being listened to: play or pause, scrub, and fade
/// ink that the recording has not reached yet.
struct NowPlayingBar: View {
    let audio: NotebookAudio

    /// The position under the reader's finger while they scrub; nil otherwise.
    @State private var scrubSeconds: TimeInterval?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    if audio.isPlaying {
                        audio.pausePlayback()
                    } else {
                        audio.resumePlayback()
                    }
                } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(.thinMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audio.isPlaying ? "Pause recording" : "Play recording")

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(Self.timeLabel(position)) / \(Self.timeLabel(duration))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                followButton

                Button {
                    audio.stopPlayback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Stop playback")
            }

            Slider(value: scrubBinding, in: 0...max(duration, 0.1)) { editing in
                guard !editing else { return }
                if let scrubSeconds {
                    audio.seek(to: scrubSeconds)
                    self.scrubSeconds = nil
                }
            }
            .tint(.accentColor)
            .frame(height: 20)
            .accessibilityLabel("Playback position")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private var followButton: some View {
        Button {
            audio.followsPlayhead.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: audio.followsPlayhead ? "eye.fill" : "eye")
                    .font(.system(size: 12, weight: .semibold))
                Text("Follow")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .foregroundStyle(audio.followsPlayhead ? Color.accentColor : Color.secondary)
            .background(
                (audio.followsPlayhead ? Color.accentColor : Color.secondary)
                    .opacity(audio.followsPlayhead ? 0.16 : 0.08),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Follow the playhead")
        .accessibilityValue(audio.followsPlayhead ? "On" : "Off")
        .accessibilityHint("Fades ink the recording has not reached yet")
    }

    private var title: String {
        guard let clip = audio.activeClip else { return "Recording" }
        return clip.title.isEmpty ? "Recording" : clip.title
    }

    private var duration: TimeInterval {
        audio.activeClip?.durationSeconds ?? 0
    }

    private var position: TimeInterval {
        scrubSeconds ?? audio.playheadSeconds
    }

    private var scrubBinding: Binding<TimeInterval> {
        Binding(
            get: { position },
            set: { value in scrubSeconds = value }
        )
    }

    /// Minutes and seconds, as the recordings list shows them.
    static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
