import Foundation

/// One timed phrase in a transcript.
public struct TranscriptSegment: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity, so a re-transcription can be diffed against the old one.
    public var id: UUID
    /// Start of the phrase, in seconds from the start of the audio file.
    public var startSeconds: Double
    /// End of the phrase, in seconds from the start of the audio file.
    public var endSeconds: Double
    /// The recognised words.
    public var text: String
    /// `false` only for a volatile result that a live transcriber may still replace.
    public var isFinal: Bool

    /// Creates a segment; `isFinal` is true for anything that will not be replaced.
    public init(
        id: UUID = UUID(),
        startSeconds: Double,
        endSeconds: Double,
        text: String,
        isFinal: Bool = true
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.isFinal = isFinal
    }

    /// Length of the phrase; zero for a malformed or non-finite range.
    public var durationSeconds: TimeInterval {
        guard startSeconds.isFinite, endSeconds.isFinite else { return 0 }
        return max(0, endSeconds - startSeconds)
    }

    /// Whether `time` lies in this phrase. The start is included, the end excluded.
    func contains(_ time: TimeInterval) -> Bool {
        guard time.isFinite, startSeconds.isFinite, endSeconds.isFinite else { return false }
        return time >= startSeconds && time < endSeconds
    }
}
