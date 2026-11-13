import Foundation

/// The transcript of one audio clip.
///
/// Transcripts are derived data: the audio file is immutable and a transcript can
/// always be rebuilt. `clipID` is nil until the transcript is attached to a clip,
/// which is what the unattached `SpeechTranscriber.transcribe(url:)` path returns.
public struct Transcript: Codable, Hashable, Sendable {
    /// The clip this transcript belongs to, or nil while it is unattached.
    public var clipID: UUID?
    /// BCP-47 language tag, for example `"en-US"`.
    public var language: String
    /// Segments in playback order.
    public var segments: [TranscriptSegment]
    /// When the transcript was last produced or edited.
    public var updatedAt: Date

    /// Creates a transcript; `updatedAt` defaults to now.
    public init(
        clipID: UUID? = nil,
        language: String,
        segments: [TranscriptSegment] = [],
        updatedAt: Date = Date()
    ) {
        self.clipID = clipID
        self.language = language
        self.segments = segments
        self.updatedAt = updatedAt
    }

    /// The segment containing `time`, or the last segment when `time` equals the
    /// transcript's final end. Returns nil outside every segment.
    public func segment(at time: TimeInterval) -> TranscriptSegment? {
        guard time.isFinite else { return nil }
        if let match = segments.first(where: { $0.contains(time) }) {
            return match
        }
        guard let last = segments.max(by: { $0.endSeconds < $1.endSeconds }) else {
            return nil
        }
        return time == last.endSeconds && last.endSeconds > last.startSeconds ? last : nil
    }

    /// Every segment's words, joined with a space. Empty for an empty transcript.
    public var text: String {
        segments
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Case- and diacritic-insensitive substring search over segment text.
    /// A blank query returns no matches.
    public func search(_ query: String) -> [TranscriptSegment] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return segments.filter {
            $0.text.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }
}
