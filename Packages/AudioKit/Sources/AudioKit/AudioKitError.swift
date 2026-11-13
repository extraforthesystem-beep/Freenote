import Foundation

/// Every error this package throws.
public enum AudioKitError: Error, Hashable, Sendable {
    /// The user, or the system, refused microphone access.
    case permissionDenied
    /// `start` was called while a recording was already running.
    case alreadyRecording
    /// `stop` was called with no recording in progress.
    case notRecording
    /// The audio recorder could not be created, prepared or started.
    case recorderUnavailable(String)
    /// A clip's metadata is not usable: empty asset name, negative duration, bad clock value.
    case invalidClip(String)
    /// A metadata file is not valid clip JSON, or its contents do not match its file name.
    case corruptMetadata(String)
    /// A transcript cannot be stored: it has no clip or a malformed segment.
    case invalidTranscript(String)
    /// The requested clip has no metadata in the store.
    case clipNotFound(UUID)
    /// The file system refused a store operation.
    case storeFailure(String)
    /// On-device speech models cannot run on this device.
    case transcriptionUnavailable
    /// The requested language is not supported by the on-device transcriber.
    case unsupportedLocale(String)
    /// The audio file could not be read or analysed.
    case transcriptionFailed(String)
}

extension AudioKitError: CustomStringConvertible {
    /// A readable explanation for logs and UI.
    public var description: String {
        switch self {
        case .permissionDenied:
            "Microphone permission was denied."
        case .alreadyRecording:
            "A recording is already running."
        case .notRecording:
            "No recording is running."
        case let .recorderUnavailable(reason):
            "Audio recorder unavailable: \(reason)"
        case let .invalidClip(reason):
            "Invalid audio clip: \(reason)"
        case let .corruptMetadata(name):
            "Corrupt audio clip metadata: \(name)"
        case let .invalidTranscript(reason):
            "Invalid transcript: \(reason)"
        case let .clipNotFound(id):
            "Audio clip not found: \(id.uuidString)"
        case let .storeFailure(reason):
            "Audio clip store error: \(reason)"
        case .transcriptionUnavailable:
            "On-device transcription is not available."
        case let .unsupportedLocale(identifier):
            "Transcription does not support locale \(identifier)."
        case let .transcriptionFailed(reason):
            "Transcription failed: \(reason)"
        }
    }
}
