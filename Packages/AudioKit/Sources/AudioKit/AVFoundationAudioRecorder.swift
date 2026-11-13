#if canImport(AVFoundation)
import AVFoundation
import Foundation

#if canImport(AudioToolbox)
import AudioToolbox
#endif

/// A real microphone recorder that writes AAC audio in an `.m4a` container.
///
/// The caller supplies the destination URL and owns the file. The type is an
/// actor because `AVAudioRecorder` is not `Sendable` and start/stop must not race.
public actor AVFoundationAudioRecorder: AudioRecorderSession {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var monotonicAnchor: TimeInterval?
    private var fileURL: URL?

    /// Creates a recorder. No audio hardware is touched until ``start(writingTo:)``.
    public init() {}

    /// Whether a recording is currently being written.
    public var isRecording: Bool {
        recorder?.isRecording ?? false
    }

    /// Seconds recorded so far, or zero when idle.
    public var elapsedSeconds: TimeInterval {
        guard let recorder else { return 0 }
        let time = recorder.currentTime
        return time.isFinite ? max(0, time) : 0
    }

    /// Asks for microphone access, prompting once if it is undetermined.
    public func requestPermission() async -> AudioRecordingPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            return granted ? .granted : .denied
        @unknown default:
            return .denied
        }
    }

    /// Starts an AAC recording at `url`; the protocol carries the full contract.
    public func start(writingTo url: URL) async throws -> AudioRecordingStart {
        guard recorder == nil else { throw AudioKitError.alreadyRecording }
        guard url.pathExtension.lowercased() == "m4a" else {
            throw AudioKitError.recorderUnavailable(
                "recording URL must end in .m4a: \(url.lastPathComponent)"
            )
        }
        guard await requestPermission() == .granted else {
            throw AudioKitError.permissionDenied
        }

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw AudioKitError.recorderUnavailable(
                "audio session: \(error.localizedDescription)"
            )
        }
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            throw AudioKitError.recorderUnavailable(
                "could not create recorder: \(error.localizedDescription)"
            )
        }

        guard recorder.prepareToRecord(), recorder.record() else {
            // Do not leave a zero-byte file behind when the start fails.
            try? FileManager.default.removeItem(at: url)
            throw AudioKitError.recorderUnavailable(
                "could not start recording at \(url.lastPathComponent)"
            )
        }

        let start = AudioRecordingStart(
            startedAt: Date(),
            monotonicAnchorSeconds: AudioAnchor.currentUptime()
        )
        self.recorder = recorder
        self.startedAt = start.startedAt
        self.monotonicAnchor = start.monotonicAnchorSeconds
        self.fileURL = url
        return start
    }

    /// Stops the recording, finalises the file and reports its duration.
    public func stop() async throws -> AudioRecordingResult {
        guard let recorder, let startedAt, let monotonicAnchor, let fileURL else {
            throw AudioKitError.notRecording
        }

        let recorded = recorder.currentTime
        recorder.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif

        // `currentTime` is the length the file actually has; the monotonic clock is
        // only a fallback for the rare case where the recorder reports nothing.
        let elapsedOnMonotonicClock = AudioAnchor.currentUptime() - monotonicAnchor
        let duration = recorded.isFinite && recorded > 0
            ? recorded
            : max(0, elapsedOnMonotonicClock)

        self.recorder = nil
        self.startedAt = nil
        self.monotonicAnchor = nil
        self.fileURL = nil

        return AudioRecordingResult(
            fileURL: fileURL,
            startedAt: startedAt,
            monotonicAnchorSeconds: monotonicAnchor,
            durationSeconds: duration
        )
    }
}
#endif
