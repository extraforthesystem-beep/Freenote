import Foundation
import Testing
@testable import AudioKit

@Suite("Pending recordings")
struct PendingRecordingTests {
    /// A store in a fresh temp folder; callers remove `rootURL`'s parent.
    private func makeStore() throws -> PendingRecordingStore {
        PendingRecordingStore(
            rootURL: try makeTemporaryDirectory()
                .appendingPathComponent("pending", isDirectory: true)
        )
    }

    private func cleanUp(_ store: PendingRecordingStore) {
        try? FileManager.default.removeItem(at: store.rootURL.deletingLastPathComponent())
    }

    private func makeAudioFile(
        _ store: PendingRecordingStore,
        id: UUID,
        bytes: Int = 64
    ) throws -> URL {
        let url = store.audioURL(for: id)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    @Test("Preparing the folder creates it, and a file in its place is an error")
    func prepareCreatesFolder() throws {
        let store = try makeStore()
        defer { cleanUp(store) }

        #expect(throws: Never.self) { try store.prepare() }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: store.rootURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        // An empty folder lists nothing, and calling prepare again is harmless.
        #expect(try store.files().isEmpty)
        try store.prepare()

        let blocked = try makeTemporaryDirectory()
            .appendingPathComponent("pending", isDirectory: false)
        try Data("not a folder".utf8).write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked.deletingLastPathComponent()) }
        #expect(throws: AudioKitError.self) {
            try PendingRecordingStore(rootURL: blocked).prepare()
        }
    }

    @Test("A started recording writes a sidecar that reads back unchanged")
    func sidecarRoundTrip() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let recording = PendingRecording(
            id: UUID(),
            startedAt: testStart.addingTimeInterval(0.125),
            monotonicAnchorSeconds: 4_242.5,
            title: "Recording 3",
            number: 3
        )
        _ = try makeAudioFile(store, id: recording.id)
        try store.begin(recording)

        let files = try store.files()
        #expect(files.count == 1)
        let file = try #require(files.first)
        #expect(file.id == recording.id)
        #expect(file.sidecar == recording)
        #expect(file.audioURL.lastPathComponent == "\(recording.id.uuidString.lowercased()).m4a")
        #expect(file.sidecarURL.lastPathComponent == "\(recording.id.uuidString.lowercased()).json")
        #expect(file.fileSize == 64)
        #expect(file.isEmpty == false)

        // The sidecar is readable JSON with an ISO-8601 start, so a recovery
        // session can be inspected by hand.
        let data = try Data(contentsOf: file.sidecarURL)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["startedAt"] as? String != nil)
        #expect(object["number"] as? Int == 3)
        #expect(object["title"] as? String == "Recording 3")
    }

    @Test("Missing and corrupt sidecars keep the audio visible")
    func sidecarLossKeepsAudio() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let withoutSidecar = UUID()
        _ = try makeAudioFile(store, id: withoutSidecar)

        let corrupt = UUID()
        _ = try makeAudioFile(store, id: corrupt)
        try Data("{ not json".utf8).write(to: store.sidecarURL(for: corrupt))

        let files = try store.files()
        let listed = Set(files.map(\.id))
        #expect(listed == Set([withoutSidecar, corrupt]))
        let missing = try #require(files.first { $0.id == withoutSidecar })
        #expect(missing.sidecar == nil)
        #expect(missing.fileSize > 0)
        let broken = try #require(files.first { $0.id == corrupt })
        #expect(broken.sidecar == nil)
        #expect(broken.fileSize > 0)
    }

    @Test("Unrelated files and folders are ignored")
    func ignoresUnrelatedNames() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()
        _ = try makeAudioFile(store, id: UUID())

        try Data("notes".utf8).write(to: store.rootURL.appendingPathComponent("notes.txt"))
        try Data("no".utf8).write(to: store.rootURL.appendingPathComponent("not-a-uuid.m4a"))
        try FileManager.default.createDirectory(
            at: store.rootURL.appendingPathComponent("nested.m4a", isDirectory: true),
            withIntermediateDirectories: true
        )

        #expect(try store.files().count == 1)
    }

    @Test("Files are listed oldest first")
    func filesAreSorted() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let late = PendingRecording(
            id: UUID(),
            startedAt: testStart.addingTimeInterval(600),
            monotonicAnchorSeconds: 1,
            title: "Late",
            number: 2
        )
        let early = PendingRecording(
            id: UUID(),
            startedAt: testStart,
            monotonicAnchorSeconds: 2,
            title: "Early",
            number: 1
        )
        _ = try makeAudioFile(store, id: late.id)
        try store.begin(late)
        _ = try makeAudioFile(store, id: early.id)
        try store.begin(early)

        #expect(try store.files().map(\.title).compactMap { $0 } == ["Early", "Late"])
    }

    @Test("Removing a pending recording deletes the audio and sidecar")
    func removeDeletesBoth() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let recording = PendingRecording(
            id: UUID(),
            startedAt: testStart,
            monotonicAnchorSeconds: 1,
            title: "Recording 1",
            number: 1
        )
        _ = try makeAudioFile(store, id: recording.id)
        try store.begin(recording)

        try store.remove(id: recording.id)
        #expect(try store.files().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.audioURL(for: recording.id).path))
        #expect(!FileManager.default.fileExists(atPath: store.sidecarURL(for: recording.id).path))

        // Removing twice is safe, so finalisation can be retried.
        #expect(throws: Never.self) { try store.remove(id: recording.id) }
    }

    @Test("Recovery prefers the sidecar metadata")
    func recoveryUsesSidecar() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let recording = PendingRecording(
            id: UUID(),
            startedAt: testStart,
            monotonicAnchorSeconds: 9_000,
            title: "Lecture 4",
            number: 4
        )
        _ = try makeAudioFile(store, id: recording.id)
        try store.begin(recording)
        let file = try #require(try store.files().first)

        let clip = file.recoveredClip(
            assetName: "abc123.m4a",
            durationSeconds: 1_800.5,
            fallbackTitle: "Recording 9",
            createdAt: testStart.addingTimeInterval(2_000)
        )

        #expect(clip.id == recording.id)
        #expect(clip.assetName == "abc123.m4a")
        #expect(clip.startedAt == testStart)
        #expect(clip.monotonicAnchorSeconds == 9_000)
        #expect(clip.durationSeconds == 1_800.5)
        #expect(clip.title == "Lecture 4")
    }

    @Test("Recovery without a sidecar estimates the start from the file")
    func recoveryWithoutSidecar() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let id = UUID()
        let audioURL = try makeAudioFile(store, id: id)
        let lastWrite = testStart.addingTimeInterval(120)
        try FileManager.default.setAttributes(
            [.modificationDate: lastWrite],
            ofItemAtPath: audioURL.path
        )
        let file = try #require(try store.files().first { $0.id == id })

        let clip = file.recoveredClip(
            assetName: "recovered.m4a",
            durationSeconds: 120,
            fallbackTitle: "Recording 2",
            createdAt: lastWrite.addingTimeInterval(600)
        )

        #expect(clip.id == id)
        #expect(clip.startedAt == testStart)
        #expect(clip.monotonicAnchorSeconds == 0)
        #expect(clip.durationSeconds == 120)
        #expect(clip.title == "Recording 2")
    }

    @Test("A blank sidecar title falls back to its recording number")
    func blankTitleUsesNumber() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let recording = PendingRecording(
            id: UUID(),
            startedAt: testStart,
            monotonicAnchorSeconds: 1,
            title: "   ",
            number: 7
        )
        _ = try makeAudioFile(store, id: recording.id)
        try store.begin(recording)
        let file = try #require(try store.files().first)

        let clip = file.recoveredClip(
            assetName: "x.m4a",
            durationSeconds: 10,
            fallbackTitle: "Recording 1"
        )
        #expect(clip.title == "Recording 7")
    }

    @Test("The file name owns identity, not a mismatched sidecar")
    func fileNameOwnsIdentity() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let fileID = UUID()
        let otherID = UUID()
        _ = try makeAudioFile(store, id: fileID)
        try store.begin(
            PendingRecording(
                id: otherID,
                startedAt: testStart,
                monotonicAnchorSeconds: 1,
                title: "Copy",
                number: 1
            )
        )
        // A sidecar named after the audio file but carrying another id: the file
        // name still decides which clip this is.
        try FileManager.default.copyItem(
            at: store.sidecarURL(for: otherID),
            to: store.sidecarURL(for: fileID)
        )

        let file = try #require(try store.files().first { $0.id == fileID })
        #expect(file.sidecar?.id == otherID)
        #expect(file.sidecar?.title == "Copy")
        let clip = file.recoveredClip(
            assetName: "a.m4a",
            durationSeconds: 5,
            fallbackTitle: "Recording 1"
        )
        #expect(clip.id == fileID)
        #expect(clip.title == "Copy")
    }

    @Test("A zero-byte file is flagged as empty and a non-finite duration is clamped")
    func emptyFileAndBadDuration() throws {
        let store = try makeStore()
        defer { cleanUp(store) }
        try store.prepare()

        let recording = PendingRecording(
            id: UUID(),
            startedAt: testStart,
            monotonicAnchorSeconds: 1,
            title: "Recording 1",
            number: 1
        )
        _ = try makeAudioFile(store, id: recording.id, bytes: 0)
        try store.begin(recording)
        let file = try #require(try store.files().first)
        #expect(file.isEmpty)

        let clip = file.recoveredClip(
            assetName: "empty.m4a",
            durationSeconds: .nan,
            fallbackTitle: "Recording 1"
        )
        #expect(clip.durationSeconds == 0)
    }
}

private extension PendingRecordingFile {
    /// Convenience for the sort test.
    var title: String? { sidecar?.title }
}
