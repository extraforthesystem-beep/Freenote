import AudioKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Record, play and delete the audio clips attached to one notebook.
struct AudioRecordingsView: View {
    let session: NotebookSession
    /// Runs after a clip is transcribed, so the notebook's search index can pick
    /// the new words up without waiting for the notebook to close.
    var onTranscriptStored: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The clip whose transcript is open.
    @State private var transcriptClip: AudioClip?

    var body: some View {
        NavigationStack {
            Group {
                if showsList {
                    recordingsList
                } else if !session.audio.hasLoaded {
                    loadingState
                } else {
                    emptyState
                }
            }
            .navigationTitle("Recordings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        // Playback keeps going: the editor shows the now-playing
                        // bar, and tapping the page seeks the recording.
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
            .alert("Microphone Access Needed", isPresented: Binding(
                get: { session.audio.showsMicrophonePermissionHelp },
                set: { if !$0 { session.audio.showsMicrophonePermissionHelp = false } }
            )) {
                #if os(iOS)
                Button("Open Settings") { openSettings() }
                #endif
                Button("OK", role: .cancel) {
                    session.audio.showsMicrophonePermissionHelp = false
                }
            } message: {
                Text(microphoneMessage)
            }
            .sheet(item: $transcriptClip) { clip in
                ClipTranscriptView(
                    session: session,
                    clip: clip,
                    onTranscriptStored: onTranscriptStored
                )
            }
        }
    }

    /// The list is shown while there is a clip to show, a recording running, or
    /// a stopped clip still being written; the empty state waits for both.
    private var showsList: Bool {
        !session.audio.clips.isEmpty
            || session.audio.isRecording
            || session.audio.isSavingRecording
    }

    private var recordingsList: some View {
        List {
            if session.audio.isRecording {
                Section {
                    recordingRow
                }
            }
            if session.audio.isSavingRecording {
                Section {
                    savingRow
                }
            }
            if !session.audio.clips.isEmpty {
                Section {
                    ForEach(session.audio.clips) { clip in
                        row(clip)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Audio files stay inside this notebook's assets. Deleting a clip only removes it from this list; its file stays in the notebook.")
                }
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#endif
        .appAnimation(AppMotion.quick, value: session.audio.isRecording)
        .appAnimation(AppMotion.quick, value: session.audio.isSavingRecording)
    }

    private var loadingState: some View {
        VStack(spacing: AppSpacing.m) {
            ProgressView()
            Text("Loading recordings…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Recordings", systemImage: "waveform")
        } description: {
            Text("Record a lecture or a thought while you write. The audio is saved with this notebook.")
        } actions: {
            Button {
                toggleRecording()
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    .frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.audio.isBusy)
        }
    }

    private var recordingRow: some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                .foregroundStyle(Color.red)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Recording")
                    .font(.body.weight(.medium))
                RecordingElapsedLabel(audio: session.audio)
            }
            Spacer(minLength: AppSpacing.s)
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

    private var savingRow: some View {
        HStack(spacing: AppSpacing.m) {
            ProgressView()
                .accessibilityHidden(true)
            Text("Saving recording…")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: AppSpacing.s)
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saving recording")
    }

    private func row(_ clip: AudioClip) -> some View {
        let isPlaying = session.audio.playingClipID == clip.id && session.audio.isPlaying
        let isLoaded = session.audio.playingClipID == clip.id
        let clipTitle = clip.title.isEmpty ? "recording" : clip.title
        return HStack(spacing: AppSpacing.m) {
            Button {
                session.audio.togglePlayback(clip)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(
                        (isLoaded ? Color.accentColor : Color.secondary).opacity(0.14),
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isPlaying ? "Pause" : "Play") \(clipTitle)")

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(clip.title.isEmpty ? "Recording" : clip.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(duration(clip.durationSeconds)) · \(clip.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppSpacing.s)

            if session.audio.isTranscribing(clip) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Transcribing")
            } else if isPlaying {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }

            Button {
                transcriptClip = clip
            } label: {
                Image(systemName: "text.quote")
                    .foregroundStyle(
                        session.audio.transcript(for: clip) == nil
                            ? Color.secondary
                            : Color.accentColor
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                session.audio.transcript(for: clip) == nil
                    ? "Transcribe"
                    : "Show transcript"
            )

            Button(role: .destructive) {
                Task { await session.audio.delete(clip) }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(clipTitle)")
        }
        .frame(minHeight: 56)
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

    private var microphoneMessage: String {
        #if os(iOS)
        "NOTEAPP cannot record without microphone access. Open Settings and allow the Microphone for NOTEAPP."
        #else
        "NOTEAPP cannot record without microphone access. Allow it in System Settings → Privacy & Security → Microphone."
        #endif
    }

    #if os(iOS)
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    #endif

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The recording timer on its own, so the audio sheet's body does not read
/// `elapsed` and re-run the whole list twice a second.
private struct RecordingElapsedLabel: View {
    let audio: NotebookAudio

    var body: some View {
        Text(Self.text(for: audio.elapsed))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    static func text(for seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
