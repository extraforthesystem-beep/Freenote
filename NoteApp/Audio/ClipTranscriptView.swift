import AudioKit
import SwiftUI

/// The words spoken in one recording, timed to its playback. Tapping a line
/// plays the audio from that moment.
struct ClipTranscriptView: View {
    let session: NotebookSession
    let clip: AudioClip
    /// Runs after a transcript is stored, so its words can join the search index.
    var onTranscriptStored: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if session.audio.isTranscribing(clip) {
                    ProgressView("Transcribing on device…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let transcript = session.audio.transcript(for: clip),
                          !transcript.segments.isEmpty {
                    lines(transcript)
                } else {
                    emptyState
                }
            }
            .navigationTitle(clip.title.isEmpty ? "Transcript" : clip.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if session.audio.transcript(for: clip) != nil {
                        Button {
                            transcribe()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(session.audio.isTranscribing(clip))
                        .accessibilityLabel("Transcribe again")
                    }
                }
            }
            .alert("Audio error", isPresented: Binding(
                get: { session.audio.errorText != nil },
                set: { if !$0 { session.audio.errorText = nil } }
            )) {
                Button("OK", role: .cancel) { session.audio.errorText = nil }
            } message: {
                Text(session.audio.errorText ?? "")
            }
        }
    }

    private func lines(_ transcript: Transcript) -> some View {
        List {
            Section {
                ForEach(transcript.segments) { segment in
                    TranscriptLine(
                        audio: session.audio,
                        clipID: clip.id,
                        segment: segment,
                        onPlay: { play(from: segment.startSeconds) }
                    )
                }
            } footer: {
                Text("Tap a line to play the recording from that moment.")
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        #endif
    }

    private func play(from offset: TimeInterval) {
        session.audio.play(
            clip,
            from: offset,
            strokes: session.visibleStrokes
        )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Transcript", systemImage: "text.quote")
        } description: {
            Text("Recognise the speech in this recording on device. The words join the notebook's search.")
        } actions: {
            Button {
                transcribe()
            } label: {
                Label("Transcribe", systemImage: "waveform.badge.magnifyingglass")
                    .frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.audio.isTranscribing(clip))
        }
    }

    /// Recognises the clip, then lets the owner refresh the search index.
    private func transcribe() {
        Task {
            await session.audio.transcribe(clip)
            guard session.audio.transcript(for: clip) != nil else { return }
            onTranscriptStored()
        }
    }
}

/// One timed line. It reads the playhead itself, so the four-times-a-second
/// position redraws this row and not the whole transcript.
private struct TranscriptLine: View {
    let audio: NotebookAudio
    let clipID: UUID
    let segment: TranscriptSegment
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(NowPlayingBar.timeLabel(segment.startSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                Text(segment.text)
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .accessibilityLabel(
            "Play from \(NowPlayingBar.timeLabel(segment.startSeconds)): \(segment.text)"
        )
    }

    /// The line the playhead is inside, while this clip is the one playing.
    private var isCurrent: Bool {
        guard audio.playingClipID == clipID else { return false }
        let time = audio.playheadSeconds
        return time >= segment.startSeconds && time < segment.endSeconds
    }
}
