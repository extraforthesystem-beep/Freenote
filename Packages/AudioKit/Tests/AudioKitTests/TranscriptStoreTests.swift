import Foundation
import Testing
@testable import AudioKit

@Suite("Transcript store")
struct TranscriptStoreTests {
    @Test("A saved transcript loads back and lists once")
    func roundTrip() async throws {
        let root = try makeTemporaryDirectory()
        let store = TranscriptStore(rootURL: root)
        let clipID = UUID()
        let transcript = Transcript(
            clipID: clipID,
            language: "en-US",
            segments: [
                TranscriptSegment(startSeconds: 0, endSeconds: 2.5, text: "First line"),
                TranscriptSegment(startSeconds: 2.5, endSeconds: 6, text: "Second line"),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_760_000_050)
        )

        try await store.save(transcript)

        #expect(try await store.load(clipID: clipID) == transcript)
        let all = try await store.list()
        #expect(all.count == 1)
        #expect(all.first?.clipID == clipID)
        #expect(all.first?.text == "First line Second line")
    }

    @Test("Missing transcripts read as nil and delete is safe twice")
    func missingIsNil() async throws {
        let store = TranscriptStore(rootURL: try makeTemporaryDirectory())
        let id = UUID()

        #expect(try await store.load(clipID: id) == nil)
        try await store.delete(clipID: id)
        try await store.delete(clipID: id)
        #expect(try await store.list().isEmpty)
    }

    @Test("A transcript with no clip is rejected before any file is written")
    func rejectsUnattached() async throws {
        let root = try makeTemporaryDirectory()
        let store = TranscriptStore(rootURL: root)
        let transcript = Transcript(language: "en-US")

        await #expect(throws: AudioKitError.invalidTranscript("no clip id")) {
            try await store.save(transcript)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.isEmpty)
    }

    @Test("A transcript whose file name disagrees with its clip is corrupt")
    func rejectsMismatch() async throws {
        let root = try makeTemporaryDirectory()
        let store = TranscriptStore(rootURL: root)
        let writtenID = UUID()
        let otherID = UUID()
        try await store.save(Transcript(clipID: writtenID, language: "en-US"))

        // Copy the valid file under another clip's name.
        let data = try Data(contentsOf: store.transcriptURL(for: writtenID))
        try data.write(to: store.transcriptURL(for: otherID))

        await #expect(throws: AudioKitError.corruptMetadata(
            "\(otherID.uuidString.lowercased()).json"
        )) {
            try await store.load(clipID: otherID)
        }
    }

    @Test("A malformed segment time is rejected")
    func rejectsMalformedSegment() async throws {
        let store = TranscriptStore(rootURL: try makeTemporaryDirectory())
        let transcript = Transcript(
            clipID: UUID(),
            language: "en-US",
            segments: [
                TranscriptSegment(startSeconds: 4, endSeconds: 1, text: "Backwards"),
            ]
        )

        await #expect(throws: AudioKitError.invalidTranscript(
            "segment \(transcript.segments[0].id.uuidString) has a malformed time range"
        )) {
            try await store.save(transcript)
        }
    }
}
