import Foundation
import Testing
@testable import AudioKit

@Suite("Transcripts")
struct TranscriptTests {
    private let segments = [
        TranscriptSegment(startSeconds: 0, endSeconds: 5, text: "Hello there"),
        TranscriptSegment(startSeconds: 5, endSeconds: 10, text: "The café is open"),
        TranscriptSegment(startSeconds: 10, endSeconds: 15, text: "Closing remarks"),
    ]

    @Test("Segment lookup uses half-open ranges and the final end")
    func segmentLookup() {
        let transcript = Transcript(language: "en-US", segments: segments)

        #expect(transcript.segment(at: 0)?.text == "Hello there")
        #expect(transcript.segment(at: 4.999)?.text == "Hello there")
        #expect(transcript.segment(at: 5)?.text == "The café is open")
        #expect(transcript.segment(at: 9.999)?.text == "The café is open")
        #expect(transcript.segment(at: 10)?.text == "Closing remarks")
        #expect(transcript.segment(at: 14.5)?.text == "Closing remarks")
        // A position exactly at the last end is still inside the clip.
        #expect(transcript.segment(at: 15)?.text == "Closing remarks")

        #expect(transcript.segment(at: -0.1) == nil)
        #expect(transcript.segment(at: 15.001) == nil)
        #expect(transcript.segment(at: .nan) == nil)
        #expect(Transcript(language: "en-US").segment(at: 0) == nil)
    }

    @Test("Search ignores case and diacritics")
    func search() {
        let transcript = Transcript(language: "en-US", segments: segments)

        #expect(transcript.search("hello").map(\.text) == ["Hello there"])
        #expect(transcript.search("HELLO").map(\.text) == ["Hello there"])
        #expect(transcript.search("cafe").map(\.text) == ["The café is open"])
        #expect(transcript.search("CAFÉ").map(\.text) == ["The café is open"])
        #expect(transcript.search("remarks").count == 1)
        #expect(transcript.search("missing").isEmpty)
        #expect(transcript.search("   ").isEmpty)
        #expect(transcript.search("").isEmpty)
    }

    @Test("A transcript survives a JSON round-trip")
    func codableRoundTrip() throws {
        let clipID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_760_000_100)
        let original = Transcript(
            clipID: clipID,
            language: "de-DE",
            segments: segments,
            updatedAt: updatedAt
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Transcript.self, from: data)

        #expect(decoded.clipID == clipID)
        #expect(decoded.language == "de-DE")
        #expect(decoded.segments == segments)
        #expect(decoded.updatedAt == updatedAt)
        #expect(decoded.segment(at: 5)?.text == "The café is open")
    }
}
