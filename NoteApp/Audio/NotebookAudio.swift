import AudioKit
import AVFoundation
import Foundation
import NoteCore
import Observation

/// Forwards `AVAudioPlayer` completion to the owning model on the main actor.
///
/// `AVAudioPlayer` calls its delegate from its own thread, so this box hops to
/// the main actor and delivers **exactly once**: the same player can report both
/// "finished" and a decode error, and a player that was already replaced must not
/// stop the new one. Each playback creates a fresh delegate carrying its own
/// generation; ``NotebookAudio`` ignores callbacks from an older generation.
private nonisolated final class AudioPlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    /// Guards ``handler``, the only mutable state touched off the main actor.
    private let lock = NSLock()
    private var handler: (@MainActor @Sendable () -> Void)?

    init(handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        deliver()
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: (any Error)?
    ) {
        deliver()
    }

    /// Takes the handler under the lock, so the first callback wins and the
    /// second finds nothing to run.
    private nonisolated func deliver() {
        lock.lock()
        let handler = self.handler
        self.handler = nil
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in handler() }
    }
}

/// Recording, replay and playback for one notebook. Audio files are immutable
/// assets; clip metadata, the in-progress recording and transcripts sit in the
/// notebook's private `audio/` folder.
@MainActor
@Observable
final class NotebookAudio {
    let store: LibraryStore
    let notebookID: UUID

    private let clipStore: AudioClipStore
    private let transcriptStore: TranscriptStore
    /// Durable home of the recording that is in progress, or left by a crash.
    private let pendingStore: PendingRecordingStore
    private let recorder = AVFoundationAudioRecorder()
    private let transcriber = SpeechAnalyzerTranscriber()
    /// Maps a clip's playhead to the stroke that was being written then.
    private let playback = PlaybackController()
    private var player: AVAudioPlayer?
    /// Strong owner of `player.delegate`; `AVAudioPlayer` only holds it weakly.
    private var playbackDelegate: AudioPlaybackDelegate?
    /// Invalidates callbacks from a player that has already been replaced.
    private var playbackGeneration: UInt64 = 0
    /// The recording currently being written, if any.
    private var pendingRecording: PendingRecording?
    private var timerTask: Task<Void, Never>?
    private var playheadTask: Task<Void, Never>?
    /// Serialises ``load()``; the notebook and the audio sheet both call it.
    private var isLoading = false
    #if os(iOS)
    /// Listening only while a recording runs, so an interruption can finalise it.
    private var interruptionObserver: (any NSObjectProtocol)?
    #endif
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
        pendingStore = PendingRecordingStore(
            rootURL: audioRoot.appendingPathComponent("pending", isDirectory: true)
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
        // Both the notebook and the audio sheet call this; a second pass cannot
        // recover the same pending file twice.
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await recoverPendingRecordings()
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
        guard !isRecording, !isBusy, !isLoading else { return }
        // Playback and capture share the audio session; a playing clip would be
        // recorded into the new file.
        stopPlayback()
        isBusy = true
        defer { isBusy = false }

        let number = clips.count + 1
        let clipID = UUID()
        let title = "Recording \(number)"

        // The pending folder is the recording's durable home. If it cannot be
        // created, do not start: a file in a folder that is not there is lost.
        do {
            try pendingStore.prepare()
        } catch {
            errorText = error.localizedDescription
            return
        }

        let start: AudioRecordingStart
        do {
            start = try await recorder.start(writingTo: pendingStore.audioURL(for: clipID))
        } catch {
            try? pendingStore.remove(id: clipID)
            errorText = error.localizedDescription
            return
        }

        let sidecar = PendingRecording(
            id: clipID,
            startedAt: start.startedAt,
            monotonicAnchorSeconds: start.monotonicAnchorSeconds,
            title: title,
            number: number
        )
        pendingRecording = sidecar
        elapsed = 0
        isRecording = true
        #if os(iOS)
        beginInterruptionObserving()
        #endif
        startTimer()

        // A crash between recorder start and this write still keeps the audio;
        // only the metadata shortcut is at risk, so this is not fatal.
        do {
            try pendingStore.begin(sidecar)
        } catch {
            errorText = "Recording started, but its recovery details could not be saved: "
                + error.localizedDescription
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
        #if os(iOS)
        endInterruptionObserving()
        #endif

        let recording = pendingRecording
        pendingRecording = nil
        do {
            let result = try await recorder.stop()
            let fileURL = recording.map { pendingStore.audioURL(for: $0.id) } ?? result.fileURL
            let duration = await Self.durationSeconds(of: fileURL, reported: result.durationSeconds)
            try await finalize(
                fileURL: fileURL,
                clipID: recording?.id ?? UUID(),
                title: recording?.title ?? "Recording \(clips.count + 1)",
                startedAt: result.startedAt,
                monotonicAnchorSeconds: result.monotonicAnchorSeconds,
                durationSeconds: duration
            )
        } catch {
            // The pending file and sidecar stay on disk: the next load recovers
            // the recording instead of losing the lecture.
            errorText = error.localizedDescription
        }
    }

    /// Copies a finished recording into the notebook's assets, saves its clip and
    /// only then removes the pending copy.
    private func finalize(
        fileURL: URL,
        clipID: UUID,
        title: String,
        startedAt: Date,
        monotonicAnchorSeconds: TimeInterval,
        durationSeconds: TimeInterval
    ) async throws {
        // A finished file can be several minutes long: read it off the main actor
        // so the UI keeps drawing while it is copied.
        let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            try Data(contentsOf: fileURL)
        }.value
        let assetName = try await store.addAsset(data, fileExtension: "m4a", to: notebookID)
        let clip = AudioClip(
            id: clipID,
            assetName: assetName,
            startedAt: startedAt,
            monotonicAnchorSeconds: monotonicAnchorSeconds,
            durationSeconds: durationSeconds,
            title: title
        )
        try await clipStore.save(clip)
        insert(clip)
        if let error = removePending(id: clipID) {
            errorText = error
        }
    }

    /// Recovers recordings a crash (or a failed finalise) left in the pending
    /// folder. The audio is added to the notebook's assets and the pending copy is
    /// removed only after its clip has been saved.
    private func recoverPendingRecordings() async {
        // A start or finalise owns the pending folder while `isBusy`; scanning a
        // half-finalised file would race the copy that is about to finish it.
        guard !isRecording, !isBusy else { return }
        let files: [PendingRecordingFile]
        do {
            files = try pendingStore.files()
        } catch {
            errorText = "Recordings left by an earlier session could not be checked: "
                + error.localizedDescription
            return
        }
        guard !files.isEmpty else { return }

        for file in files {
            // Zero bytes means the recorder never wrote a frame: there is no audio
            // to keep. Any other failure keeps the file for the next attempt.
            if file.isEmpty {
                if let error = removePending(id: file.id) {
                    errorText = error
                }
                continue
            }
            // The clip may already be saved and only its pending copy left behind
            // by a crash between the two writes.
            if clips.contains(where: { $0.id == file.id }) {
                if let error = removePending(id: file.id) {
                    errorText = error
                }
                continue
            }

            do {
                let duration = await AudioFileDuration.seconds(of: file.audioURL) ?? 0
                let data = try await Task.detached(priority: .userInitiated) {
                    () throws -> Data in
                    try Data(contentsOf: file.audioURL)
                }.value
                let assetName = try await store.addAsset(data, fileExtension: "m4a", to: notebookID)
                let clip = file.recoveredClip(
                    assetName: assetName,
                    durationSeconds: duration,
                    fallbackTitle: "Recording \(clips.count + 1)"
                )
                try await clipStore.save(clip)
                insert(clip)
                if let error = removePending(id: file.id) {
                    errorText = error
                }
            } catch {
                errorText = "A recording from an earlier session could not be recovered: "
                    + error.localizedDescription
            }
        }
    }

    /// Appends a clip while keeping the list in the same order the store uses.
    private func insert(_ clip: AudioClip) {
        guard !clips.contains(where: { $0.id == clip.id }) else { return }
        clips.append(clip)
        clips.sort { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Removes a pending copy, returning a message instead of throwing so callers
    /// can continue with the remaining files.
    private func removePending(id: UUID) -> String? {
        do {
            try pendingStore.remove(id: id)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The recorder's `currentTime` is authoritative, but an interruption can
    /// report zero for a file that still has audio.
    private static func durationSeconds(
        of url: URL,
        reported: TimeInterval
    ) async -> TimeInterval {
        if reported.isFinite, reported > 0 { return reported }
        return await AudioFileDuration.seconds(of: url) ?? 0
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
        playbackGeneration &+= 1
        player?.stop()
        player?.delegate = nil
        player = nil
        playbackDelegate = nil
        playingClipID = nil
        isPlaying = false
        playheadSeconds = 0
        activeStrokeID = nil
        playheadTask?.cancel()
        playheadTask = nil
    }

    /// Clears the playing row once the player reaches the end of its file.
    private func finishPlayback() {
        playbackGeneration &+= 1
        player?.delegate = nil
        player = nil
        playbackDelegate = nil
        playingClipID = nil
        isPlaying = false
        playheadSeconds = 0
        activeStrokeID = nil
        playheadTask?.cancel()
        playheadTask = nil
    }

    /// Finishes playback only when the callback belongs to the current player, so
    /// a late delegate message cannot stop a clip that just started.
    private func finishPlayback(generation: UInt64) {
        guard generation == playbackGeneration, playingClipID != nil else { return }
        finishPlayback()
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
            // One delegate per player: its completion carries this generation, so a
            // stale callback from an earlier player is ignored instead of stopping
            // the current one.
            playbackGeneration &+= 1
            let generation = playbackGeneration
            let delegate = AudioPlaybackDelegate { [weak self] in
                self?.finishPlayback(generation: generation)
            }
            playbackDelegate = delegate
            player.delegate = delegate
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

    // MARK: - Audio session interruptions

    #if os(iOS)
    /// Watches for phone calls, Siri and other apps taking the microphone. The
    /// observer only lives while a recording runs.
    private func beginInterruptionObserving() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSessionDeactivation()
            }
        }
    }

    private func endInterruptionObserving() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    /// The session was deactivated by the system, so the recorder has already
    /// stopped writing: finalise the file now instead of leaving `isRecording`
    /// stuck. Nothing resumes automatically; the user asked to record once, not to
    /// keep re-arming the microphone.
    private func handleSessionDeactivation() {
        guard isRecording else { return }
        errorText = "Recording stopped because another app took the microphone."
        Task { [weak self] in
            await self?.stopRecording()
        }
    }
    #endif
}
