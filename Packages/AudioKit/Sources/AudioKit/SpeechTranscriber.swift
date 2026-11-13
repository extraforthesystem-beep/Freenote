import Foundation

/// Turns a recorded audio file into a timed transcript.
///
/// The protocol exists so tests and previews can use a fake; the real
/// implementation is ``SpeechAnalyzerTranscriber``.
public protocol SpeechTranscriber: Sendable {
    /// Whether the on-device speech models can run on this device.
    var isAvailable: Bool { get async }
    /// Locales the on-device transcriber supports, whether or not they are installed.
    var supportedLocales: [Locale] { get async }
    /// Transcribes `url`, stamping `clipID` on the result. A nil id leaves the
    /// transcript unattached.
    func transcribe(url: URL, clipID: UUID?) async throws -> Transcript
}

extension SpeechTranscriber {
    /// Transcribes a file without attaching it to a clip yet.
    public func transcribe(url: URL) async throws -> Transcript {
        try await transcribe(url: url, clipID: nil)
    }
}
