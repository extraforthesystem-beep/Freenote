import Foundation

/// The state of the microphone permission the app needs to record.
public enum AudioRecordingPermission: String, Codable, Hashable, Sendable {
    /// The user has granted microphone access.
    case granted
    /// The user has denied microphone access.
    case denied
    /// The user has not been asked yet.
    case undetermined
}

/// Wall-clock and monotonic values captured at the instant recording began.
public struct AudioRecordingStart: Codable, Hashable, Sendable {
    /// Wall-clock time of the first recorded sample.
    public var startedAt: Date
    /// Monotonic host uptime at the same moment, in seconds.
    public var monotonicAnchorSeconds: TimeInterval

    /// Creates a start marker from the recorder's clock readings.
    public init(startedAt: Date, monotonicAnchorSeconds: TimeInterval) {
        self.startedAt = startedAt
        self.monotonicAnchorSeconds = monotonicAnchorSeconds
    }
}

/// What a finished recording produced.
public struct AudioRecordingResult: Codable, Hashable, Sendable {
    /// The file the caller asked the recorder to write.
    public var fileURL: URL
    /// Wall-clock time at which the recording started.
    public var startedAt: Date
    /// Monotonic host uptime at which the recording started, in seconds.
    public var monotonicAnchorSeconds: TimeInterval
    /// Duration of the written audio in seconds.
    public var durationSeconds: TimeInterval

    /// Creates a finished-recording report.
    public init(
        fileURL: URL,
        startedAt: Date,
        monotonicAnchorSeconds: TimeInterval,
        durationSeconds: TimeInterval
    ) {
        self.fileURL = fileURL
        self.startedAt = startedAt
        self.monotonicAnchorSeconds = monotonicAnchorSeconds
        self.durationSeconds = durationSeconds
    }
}

/// A microphone recorder that can be replaced by a fake in tests.
///
/// `start` asks for permission first; a denied permission throws
/// ``AudioKitError/permissionDenied`` and leaves no recording running. The caller
/// supplies the destination URL and owns the file afterwards; the recorder writes
/// AAC audio in an `.m4a` container and does not change the URL's extension, so
/// the URL must already end in `.m4a`.
public protocol AudioRecorderSession: Sendable {
    /// Asks the system for microphone access, prompting once if undetermined.
    func requestPermission() async -> AudioRecordingPermission
    /// Starts writing a new recording to `url`, or throws if one is already running.
    func start(writingTo url: URL) async throws -> AudioRecordingStart
    /// Stops the recording, finalises the file and reports its duration.
    func stop() async throws -> AudioRecordingResult
    /// Whether a recording is currently being written.
    var isRecording: Bool { get async }
    /// Seconds recorded so far, or zero when idle.
    var elapsedSeconds: TimeInterval { get async }
}
