import Foundation
import Testing
@testable import AudioKit

/// A transcriber that never touches the speech framework or a microphone.
actor FakeTranscriber: SpeechTranscriber {
    var isAvailable: Bool {
        true
    }

    var supportedLocales: [Locale] {
        [Locale(identifier: "en-US")]
    }

    func transcribe(url: URL, clipID: UUID?) async throws -> Transcript {
        Transcript(
            clipID: clipID,
            language: "en-US",
            segments: [
                TranscriptSegment(startSeconds: 0, endSeconds: 1.5, text: "Hello from a fake"),
            ],
            updatedAt: testStart
        )
    }
}

@Suite("Speech transcriber contract")
struct SpeechTranscriberTests {
    @Test("The unattached convenience leaves clipID nil")
    func unattachedTranscription() async throws {
        let url = URL(fileURLWithPath: "/tmp/never-read.m4a")
        let transcriber = FakeTranscriber()

        let unattached = try await transcriber.transcribe(url: url)
        #expect(unattached.clipID == nil)
        #expect(unattached.segments.count == 1)

        let id = UUID()
        let attached = try await transcriber.transcribe(url: url, clipID: id)
        #expect(attached.clipID == id)
        #expect(await transcriber.isAvailable)
        #expect(await transcriber.supportedLocales.map(\.identifier) == ["en-US"])
    }
}

#if canImport(Speech)
import CoreMedia

@Suite("Speech segment normalisation")
struct SpeechSegmentTests {
    @Test("Analyzer ranges stay inside the file and gaps are filled")
    func normalisesRanges() {
        func range(_ start: Double, _ end: Double) -> CMTimeRange {
            CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
        }

        let raw: [(range: CMTimeRange, text: String)] = [
            (range(0, 2), "first"),
            (range(5, 7), "second"),
            // A result whose range is beyond the file: clamped to the file end.
            (range(20, 20), "last"),
        ]

        let segments = SpeechAnalyzerTranscriber.segments(from: raw, fileDuration: 10)

        #expect(segments.count == 3)
        #expect(segments[0].startSeconds == 0)
        #expect(segments[0].endSeconds == 2)
        #expect(segments[1].startSeconds == 5)
        #expect(segments[1].endSeconds == 7)
        #expect(abs(segments[2].startSeconds - 9.99) < 1e-9)
        #expect(segments[2].endSeconds == 10)
        #expect(segments.allSatisfy { $0.startSeconds >= 0 && $0.endSeconds <= 10 })
        #expect(segments.allSatisfy { $0.isFinal })
    }

    @Test("An empty result produces an empty transcript")
    func emptyInput() {
        #expect(
            SpeechAnalyzerTranscriber.segments(from: [], fileDuration: 10).isEmpty
        )
        #expect(
            SpeechAnalyzerTranscriber.segments(
                from: [
                    (
                        CMTimeRange(
                            start: .zero,
                            duration: CMTime(seconds: 1, preferredTimescale: 600)
                        ),
                        "text"
                    ),
                ],
                fileDuration: 0
            ).isEmpty
        )
    }
}
#endif
