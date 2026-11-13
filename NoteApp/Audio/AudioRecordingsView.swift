import AudioKit
import SwiftUI

/// Record, play and delete the audio clips attached to one notebook.
struct AudioRecordingsView: View {
    let session: NotebookSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if session.audio.clips.isEmpty {
                    emptyState
                } else {
                    List {
                        if session.audio.isRecording {
                            Section {
                                recordingRow
                            }
                        }
                        Section {
                            ForEach(session.audio.clips) { clip in
                                row(clip)
                            }
                            .onDelete(perform: delete)
                        } footer: {
                            Text("Audio files stay inside this notebook's assets. Deleting a clip only removes it from this list; its file stays in the notebook.")
                        }
                    }
#if os(iOS)
                    .listStyle(.insetGrouped)
#endif
                }
            }
            .navigationTitle("Audio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        session.audio.stopPlayback()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        toggleRecording()
                    } label: {
                        Image(systemName: session.audio.isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.title2)
                            .foregroundStyle(session.audio.isRecording ? Color.red : Color.accentColor)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(session.audio.isBusy)
                    .accessibilityLabel(session.audio.isRecording ? "Stop recording" : "Start recording")
                }
            }
            .task {
                await session.audio.load()
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                session.audio.isRecording ? "Recording…" : "No Recordings",
                systemImage: "waveform"
            )
        } description: {
            Text(
                session.audio.isRecording
                    ? "\(elapsedText) recorded so far. Stop when you are done; the audio is saved with this notebook."
                    : "Record a lecture or a thought while you write. The audio is saved with this notebook."
            )
        } actions: {
            Button {
                toggleRecording()
            } label: {
                Label(
                    session.audio.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: session.audio.isRecording ? "stop.fill" : "record.circle"
                )
                .frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.audio.isBusy)
        }
    }

    private var recordingRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(Color.red)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Recording")
                    .font(.body.weight(.medium))
                Text(elapsedText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                toggleRecording()
            } label: {
                Text("Stop")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(session.audio.isBusy)
        }
        .frame(minHeight: 56)
    }

    private func row(_ clip: AudioClip) -> some View {
        let isPlaying = session.audio.playingClipID == clip.id
        return HStack(spacing: 14) {
            Button {
                session.audio.togglePlayback(clip)
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(
                        (isPlaying ? Color.accentColor : Color.secondary).opacity(0.14),
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Stop playback" : "Play recording")

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.title.isEmpty ? "Recording" : clip.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(duration(clip.durationSeconds)) · \(clip.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isPlaying {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }

            Button(role: .destructive) {
                Task { await session.audio.delete(clip) }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(clip.title.isEmpty ? "recording" : clip.title)")
        }
        .frame(minHeight: 56)
    }

    private var elapsedText: String {
        duration(session.audio.elapsed)
    }

    private func toggleRecording() {
        Task {
            if session.audio.isRecording {
                await session.audio.stopRecording()
            } else {
                await session.audio.startRecording()
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        // Snapshot the clips first: each delete shrinks `clips`, so reading by
        // index while deleting would run out of bounds.
        let targets = offsets.compactMap { index in
            session.audio.clips.indices.contains(index) ? session.audio.clips[index] : nil
        }
        guard !targets.isEmpty else { return }
        Task {
            for clip in targets {
                await session.audio.delete(clip)
            }
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
