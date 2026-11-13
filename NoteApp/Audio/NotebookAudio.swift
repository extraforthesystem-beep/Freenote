import AudioKit
import AVFoundation
import Foundation
import NoteCore
import Observation

/// Forwards `AVAudioPlayer` completion to the owning model on the main actor.
///
/// `AVAudioPlayer` requires an `NSObject` delegate and calls it from its own
/// queue, so this small box is deliberately nonisolated; the handler it forwards
/// to is main-actor bound.
private nonisolated final class AudioPlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    /// Set on the main actor before playback starts, read from the callback.
    nonisolated(unsafe) var onFinish: (@MainActor @Sendable () -> Void)?

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            onFinish?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: (any Error)?
    ) {
        Task { @MainActor in
            onFinish?()
        }
    }
}

/// Recording, replay and playback for one notebook. Audio files are immutable
/// assets; clip metadata and transcripts sit in the notebook's private `audio/`
/// folder.
@MainActor
@Observable
final class NotebookAudio {
    let store: LibraryStore
    let notebookID: UUID

    private let clipStore: AudioClipStore
    private let transcriptStore: TranscriptStore
    private let recorder = AVFoundationAudioRecorder()
    private let transcriber = SpeechAnalyzerTranscriber()
    private let playbackDelegate = AudioPlaybackDelegate()
    /// Maps a clip's playhead to the stroke that was being written then.
    private let playback = PlaybackController()
    private var player: AVAudioPlayer?
    private var recordingURL: URL?
    private var timerTask: Task<Void, Never>?
    private var playheadTask: Task<Void, Never>?
    /// The page on screen while a clip plays; replay seeks on its ink only.
    private var replayStrokes: [StrokeRecord] = []

    private(set) var clips: [AudioClip] = []
    private(set) var transcripts: [UUID: Transcript] = [:]
    private(set) var isRecording = false
    private(set) var isBusy = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var playingClipID: UUID?
    /// Playback position inside the playing clip, in seconds.
    private(set) var playheadSeconds: TimeInterval = 0
    /// The stroke that was being written at ``playheadSeconds``, when the page
    /// on screen has one.
    private(set) var activeStrokeID: UUID?
    private(set) var isPlaying = false
    /// The clip whose transcript is being recognised, if any.
    private(set) var transcribingClipID: UUID?
    /// While a clip plays, ink written after the playhead is faded.
    var followsPlayhead = false
    var errorText: String?

    init(store: LibraryStore, notebookID: UUID) {
        self.store = store
        self.notebookID = notebookID
        let audioRoot = Self.audioDirectory(for: store, notebookID: notebookID)
        clipStore = AudioClipStore(rootURL: audioRoot)
        transcriptStore = TranscriptStore(
            rootURL: audioRoot.appendingPathComponent("transcripts", isDirectory: true)
        )
    }

    /// The folder holding a notebook's clip metadata and transcripts.
    nonisolated static func audioDirectory(for store: LibraryStore, notebookID: UUID) -> URL {
        store.notebookDirectoryURL(for: notebookID)
            .appendingPathComponent("audio", isDirectory: true)
    }

    /// The clip that is playing or paused, if any.
    var activeClip: AudioClip? {
        clips.first { $0.id == playingClipID }
    }

    /// Whether the now-playing bar has a clip to act on.
    var hasActiveClip: Bool { playingClipID != nil }

    func load() async {
        do {
            clips = try await clipStore.list()
            let stored = try await transcriptStore.list()
            transcripts = Dictionary(
                stored.compactMap { transcript in
                    transcript.clipID.map { ($0, transcript) }
                },
                uniquingKeysWith: { _, latest in latest }
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    func startRecording() async {
        guard !isRecording, !isBusy else { return }
        // Playback and capture share the audio session; a playing clip would be
        // recorded into the new file.
        stopPlayback()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a", isDirectory: false)
        do {
            _ = try await recorder.start(writingTo: url)
            recordingURL = url
            elapsed = 0
            isRecording = true
            startTimer()
        } catch {
            errorText = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        timerTask?.cancel()
        timerTask = nil
        isRecording = false
        elapsed = 0
        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await recorder.stop()
            recordingURL = result.fileURL
            // The finished file can be several minutes long: read it off the
            // main actor so the UI keeps drawing while it is copied.
            let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                try Data(contentsOf: result.fileURL)
            }.value
            let assetName = try await store.addAsset(data, fileExtension: "m4a", to: notebookID)
            let clip = AudioClip(
                assetName: assetName,
                startedAt: result.startedAt,
                monotonicAnchorSeconds: result.monotonicAnchorSeconds,
                durationSeconds: result.durationSeconds,
                title: "Recording \(clips.count + 1)"
            )
            try await clipStore.save(clip)
            clips.append(clip)
            try? FileManager.default.removeItem(at: result.fileURL)
            recordingURL = nil
        } catch {
            if let recordingURL {
                try? FileManager.default.removeItem(at: recordingURL)
            }
            recordingURL = nil
            errorText = error.localizedDescription
        }
    }

    /// Plays or pauses `clip`. A new clip starts at the beginning.
    func togglePlayback(_ clip: AudioClip) {
        if playingClipID == clip.id {
            if isPlaying {
                pausePlayback()
            } else {
                resumePlayback()
            }
            return
        }
        play(clip, from: 0, strokes: replayStrokes)
    }

    /// Plays `clip` from `offset`, mapping the page's ink to playback time.
    func play(_ clip: AudioClip, from offset: TimeInterval, strokes: [StrokeRecord]) {
        // Capture owns the audio session; never play into a recording.
        guard !isRecording else { return }
        if playingClipID != clip.id {
            stopPlayback()
        }
        replayStrokes = strokes
        if player == nil {
            guard startPlayer(for: clip) else { return }
        }
        guard let player else { return }
        let target = min(max(0, offset), max(0, player.duration - 0.05))
        player.currentTime = target
        if !player.play() {
            errorText = "This recording could not be played."
            finishPlayback()
            return
        }
        playingClipID = clip.id
        isPlaying = true
        playheadSeconds = target
        Task { @MainActor in
            await playback.configure(clip: clip, strokes: strokes)
            await refreshActiveStroke()
        }
        startPlayhead()
    }

    /// Plays the moment at which `stroke` was written, from whichever clip was
    /// recording then. Ink written outside a recording does nothing.
    func replay(from stroke: StrokeRecord, strokes: [StrokeRecord]) {
        guard let clip = clips.last(where: { $0.contains(stroke.createdAt) }) else { return }
        let offset = AudioAnchor.offset(for: stroke.createdAt, clip: clip)
        play(clip, from: offset, strokes: strokes)
    }

    /// Tells playback which page is on screen, so replay waits on its ink.
    func replayPageChanged(_ strokes: [StrokeRecord]) {
        replayStrokes = strokes
        guard let clip = activeClip else { return }
        Task { @MainActor in
            await playback.configure(clip: clip, strokes: strokes)
            await refreshActiveStroke()
        }
    }

    func pausePlayback() {
        guard let player else { return }
        player.pause()
        isPlaying = false
        playheadTask?.cancel()
        playheadTask = nil
    }

    func resumePlayback() {
        guard let player else { return }
        guard player.play() else { return }
        isPlaying = true
        startPlayhead()
    }

    func stopPlayback() {
        player?.stop()
        player?.delegate = nil
        player = nil
        playingClipID = nil
        isPlaying = false
        playheadSeconds = 0
        activeStrokeID = nil
        playheadTask?.cancel()
        playheadTask = nil
    }

    /// Clears the playing row once the player reaches the end of its file.
    private func finishPlayback() {
        player?.delegate = nil
        player = nil
        playingClipID = nil
        isPlaying = false
        playheadSeconds = 0
        activeStrokeID = nil
        playheadTask?.cancel()
        playheadTask = nil
    }

    /// Builds a player for `clip` without starting it.
    private func startPlayer(for clip: AudioClip) -> Bool {
        let url = store.assetURL(named: clip.assetName, in: notebookID)
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorText = "Playback could not start: \(error.localizedDescription)"
            return false
        }
        #endif
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = playbackDelegate
            playbackDelegate.onFinish = { [weak self] in
                self?.finishPlayback()
            }
            player.prepareToPlay()
            self.player = player
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    /// Moves the playhead, keeping the active stroke in step.
    func seek(to offset: TimeInterval) {
        guard let player else { return }
        let target = min(max(0, offset), max(0, player.duration - 0.05))
        player.currentTime = target
        playheadSeconds = target
        Task { @MainActor in
            await refreshActiveStroke()
        }
    }

    /// Polls the player so the marker follows the audio without a per-frame timer.
    private func startPlayhead() {
        playheadTask?.cancel()
        playheadTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                if let player = self.player, self.isPlaying {
                    self.playheadSeconds = player.currentTime
                }
                await self.refreshActiveStroke()
            }
        }
    }

    private func refreshActiveStroke() async {
        guard let clip = activeClip else {
            activeStrokeID = nil
            return
        }
        if await playback.currentClip != clip {
            await playback.configure(clip: clip, strokes: replayStrokes)
        }
        activeStrokeID = await playback.activeStrokeID(atPlaybackOffset: playheadSeconds)
    }

    // MARK: - Transcripts

    func transcript(for clip: AudioClip) -> Transcript? {
        transcripts[clip.id]
    }

    func isTranscribing(_ clip: AudioClip) -> Bool {
        transcribingClipID == clip.id
    }

    /// Recognises `clip` on device and stores the transcript with it. The audio
    /// file is untouched, so this can be repeated.
    func transcribe(_ clip: AudioClip) async {
        guard transcribingClipID == nil else { return }
        transcribingClipID = clip.id
        defer { transcribingClipID = nil }
        do {
            let url = store.assetURL(named: clip.assetName, in: notebookID)
            let transcript = try await transcriber.transcribe(url: url, clipID: clip.id)
            try await transcriptStore.save(transcript)
            transcripts[clip.id] = transcript
        } catch is CancellationError {
            // Leaving the transcript closes the work; nothing was stored.
        } catch {
            errorText = (error as? AudioKitError)?.description ?? error.localizedDescription
        }
    }

    func delete(_ clip: AudioClip) async {
        if playingClipID == clip.id {
            stopPlayback()
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await clipStore.delete(id: clip.id)
        } catch {
            errorText = error.localizedDescription
            return
        }
        // The transcript is derived data: a failed delete only leaves a file
        // that the next transcription overwrites.
        try? await transcriptStore.delete(clipID: clip.id)
        clips.removeAll { $0.id == clip.id }
        transcripts[clip.id] = nil
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                let seconds = await self.recorder.elapsedSeconds
                if Task.isCancelled { return }
                self.elapsed = seconds
            }
        }
    }
}
