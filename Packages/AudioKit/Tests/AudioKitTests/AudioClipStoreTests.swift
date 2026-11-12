import Foundation
import Testing
@testable import AudioKit

@Suite("Clip metadata store")
struct AudioClipStoreTests {
    @Test("Saves, lists, loads and deletes one file per clip")
    func roundTripAndDelete() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioClipStore(rootURL: root)

        let first = makeClip(
            startedAt: testStart,
            createdAt: testStart,
            title: "First"
        )
        let second = makeClip(
            startedAt: testStart.addingTimeInterval(120),
            createdAt: testStart,
            title: "Second"
        )

        try await store.save(first)
        try await store.save(second)

        // Sorted by start time, not by insertion order.
        #expect(try await store.list().map(\.id) == [first.id, second.id])

        let loaded = try await store.load(id: first.id)
        #expect(loaded == first)

        // Exactly one file per clip, and no atomic-write leftovers.
        let names = try FileManager.default
            .contentsOfDirectory(atPath: root.path)
            .sorted()
        let expected = [
            "\(first.id.uuidString.lowercased()).json",
            "\(second.id.uuidString.lowercased()).json",
        ].sorted()
        #expect(names == expected)

        // Dates are stored as readable ISO-8601 strings and the document is sorted JSON.
        let data = try Data(contentsOf: store.metadataURL(for: first.id))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["assetName"] as? String == "clip.m4a")
        #expect(object["startedAt"] as? String != nil)
        #expect(object["durationSeconds"] as? Double == 60)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"assetName\" : \"clip.m4a\""))

        try await store.delete(id: first.id)
        #expect(try await store.list().map(\.id) == [second.id])

        // Deleting twice is safe.
        try await store.delete(id: first.id)

        do {
            _ = try await store.load(id: first.id)
            Issue.record("Loading a deleted clip should throw")
        } catch let error as AudioKitError {
            #expect(error == .clipNotFound(first.id))
        }
    }

    @Test("Re-saving the same clip replaces its metadata")
    func saveReplaces() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioClipStore(rootURL: root)

        var clip = makeClip(title: "Draft")
        try await store.save(clip)

        clip.title = "Final"
        try await store.save(clip)

        #expect(try await store.load(id: clip.id).title == "Final")
        #expect(try await store.list().count == 1)
    }

    @Test("An invalid clip is rejected before the old file is touched")
    func invalidClipLeavesFileIntact() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioClipStore(rootURL: root)

        var clip = makeClip()
        try await store.save(clip)

        clip.durationSeconds = -1
        do {
            try await store.save(clip)
            Issue.record("A negative duration should be rejected")
        } catch let error as AudioKitError {
            guard case .invalidClip = error else {
                Issue.record("Expected invalidClip, got \(error)")
                return
            }
        }

        #expect(try await store.load(id: clip.id).durationSeconds == 60)

        var emptyAsset = makeClip()
        emptyAsset.assetName = "   "
        do {
            try await store.save(emptyAsset)
            Issue.record("An empty asset name should be rejected")
        } catch let error as AudioKitError {
            guard case .invalidClip = error else {
                Issue.record("Expected invalidClip, got \(error)")
                return
            }
        }
    }

    @Test("Corrupt metadata is reported, not silently skipped")
    func corruptMetadata() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioClipStore(rootURL: root)
        let id = UUID()

        try Data("{ not json".utf8).write(to: store.metadataURL(for: id))

        do {
            _ = try await store.list()
            Issue.record("Listing should throw for a corrupt file")
        } catch let error as AudioKitError {
            guard case .corruptMetadata = error else {
                Issue.record("Expected corruptMetadata, got \(error)")
                return
            }
        }

        // A well-formed file whose id does not match its name is corrupt too.
        let other = makeClip()
        try await store.save(other)
        let url = store.metadataURL(for: id)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: store.metadataURL(for: other.id), to: url)

        do {
            _ = try await store.load(id: id)
            Issue.record("A mismatched id should be reported")
        } catch let error as AudioKitError {
            #expect(error == .corruptMetadata(url.lastPathComponent))
        }
    }

    @Test("An empty store creates its root on demand")
    func emptyStore() async throws {
        let root = try makeTemporaryDirectory()
            .appendingPathComponent("nested", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = AudioClipStore(rootURL: root)

        #expect(try await store.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
