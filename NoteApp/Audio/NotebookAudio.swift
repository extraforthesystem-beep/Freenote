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

/// Recording and playback for one notebook. Audio files are immutable assets;
/// clip metadata sits in the notebook's private `audio/` folder.
@MainActor
@Observable
final class NotebookAudio {
    let store: LibraryStore
    let notebookID: UUID

    private let clipStore: AudioClipStore
    private let recorder = AVFoundationAudioRecorder()
    private let playbackDelegate = AudioPlaybackDelegate()
    private var player: AVAudioPlayer?
    private var recordingURL: URL?
    private var timerTask: Task<Void, Never>?

    private(set) var clips: [AudioClip] = []
    private(set) var isRecording = false
    private(set) var isBusy = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var playingClipID: UUID?
    var errorText: String?

    init(store: LibraryStore, notebookID: UUID) {
        self.store = store
        self.notebookID = notebookID
        let audioRoot = store.notebookDirectoryURL(for: notebookID)
            .appendingPathComponent("audio", isDirectory: true)
        clipStore = AudioClipStore(rootURL: audioRoot)
    }

    func load() async {
        do {
            clips = try await clipStore.list()
        } catch {
            errorText = error.localizedDescription
        }
    }

    func startRecording() async {
        guard !isRecording, !isBusy else { return }
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

    func togglePlayback(_ clip: AudioClip) {
        if playingClipID == clip.id {
            stopPlayback()
            return
        }
        stopPlayback()
        let url = store.assetURL(named: clip.assetName, in: notebookID)
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorText = "Playback could not start: \(error.localizedDescription)"
            return
        }
        #endif
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = playbackDelegate
            playbackDelegate.onFinish = { [weak self] in
                self?.finishPlayback()
            }
            player.prepareToPlay()
            guard player.play() else {
                errorText = "This recording could not be played."
                return
            }
            self.player = player
            playingClipID = clip.id
        } catch {
            errorText = error.localizedDescription
        }
    }

    func stopPlayback() {
        player?.stop()
        player?.delegate = nil
        player = nil
        playingClipID = nil
    }

    /// Clears the playing row once the player reaches the end of its file.
    private func finishPlayback() {
        player?.delegate = nil
        player = nil
        playingClipID = nil
    }

    func delete(_ clip: AudioClip) async {
        if playingClipID == clip.id {
            stopPlayback()
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await clipStore.delete(id: clip.id)
            clips.removeAll { $0.id == clip.id }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func seek(to offset: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, offset), max(0, player.duration - 0.05))
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
