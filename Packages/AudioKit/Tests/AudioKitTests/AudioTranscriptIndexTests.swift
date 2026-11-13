import Foundation
import NoteCore
import Testing
@testable import AudioKit

@Suite("Transcript indexing")
struct AudioTranscriptIndexTests {
    private func page(strokes: [StrokeRecord]) -> Page {
        Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: .blank,
            layers: [Page.Layer(id: UUID(), name: "Layer 1")],
            strokes: strokes
        )
    }

    private func transcript(_ text: [String]) -> Transcript {
        Transcript(
            language: "en-US",
            segments: text.enumerated().map { index, line in
                TranscriptSegment(
                    startSeconds: Double(index) * 5,
                    endSeconds: Double(index) * 5 + 5,
                    text: line
                )
            }
        )
    }

    @Test("The clip window includes both ends and rejects a bad duration")
    func clipWindow() {
        let clip = makeClip(startedAt: testStart, durationSeconds: 60)

        #expect(clip.contains(testStart))
        #expect(clip.contains(testStart.addingTimeInterval(30)))
        #expect(clip.contains(testStart.addingTimeInterval(60)))
        #expect(!clip.contains(testStart.addingTimeInterval(-0.001)))
        #expect(!clip.contains(testStart.addingTimeInterval(60.001)))

        let broken = makeClip(durationSeconds: .infinity)
        #expect(!broken.contains(testStart))
    }

    @Test("A page takes the text of clips that were recording while it was written")
    func textByPage() {
        let firstClip = makeClip(startedAt: testStart, durationSeconds: 60, title: "First")
        let secondClip = makeClip(
            startedAt: testStart.addingTimeInterval(600),
            durationSeconds: 60,
            title: "Second"
        )
        let otherPageClip = makeClip(
            startedAt: testStart.addingTimeInterval(1_200),
            durationSeconds: 60,
            title: "Elsewhere"
        )
        let written = page(strokes: [
            makeStroke(createdAt: testStart.addingTimeInterval(10)),
            makeStroke(createdAt: testStart.addingTimeInterval(610)),
        ])
        let transcripts = [
            firstClip.id: transcript(["The derivative is a rate", "of change"]),
            secondClip.id: transcript(["Limits come first"]),
            otherPageClip.id: transcript(["Not on this page"]),
        ]

        let text = AudioTranscriptIndex.text(
            for: written,
            clips: [secondClip, otherPageClip, firstClip],
            transcripts: transcripts
        )

        #expect(text == "The derivative is a rate of change\nLimits come first")
    }

    @Test("Ink written outside every clip, or clips without a transcript, add nothing")
    func ignoresUnrecordedInk() {
        let clip = makeClip(startedAt: testStart, durationSeconds: 10)
        let writtenBefore = page(strokes: [
            makeStroke(createdAt: testStart.addingTimeInterval(-30)),
        ])
        let writtenDuring = page(strokes: [
            makeStroke(createdAt: testStart.addingTimeInterval(5)),
        ])

        #expect(
            AudioTranscriptIndex.text(
                for: writtenBefore,
                clips: [clip],
                transcripts: [clip.id: transcript(["Hello"])]
            ).isEmpty
        )
        #expect(
            AudioTranscriptIndex.text(
                for: writtenDuring,
                clips: [clip],
                transcripts: [:]
            ).isEmpty
        )
        #expect(
            AudioTranscriptIndex.text(
                for: writtenDuring,
                clips: [clip],
                transcripts: [clip.id: transcript(["  "])]
            ).isEmpty
        )
    }
}
