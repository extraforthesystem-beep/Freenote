import Foundation
import Testing
@testable import NoteCore

@Suite("Notebook manifest last opened")
struct NotebookManifestOpenedTests {
    /// A manifest written before `lastOpenedAt` existed decodes, and re-encoding
    /// it does not grow the field. The schema version stays the same, so an
    /// older build still reads a manifest that carries the new key.
    @Test func openedDateIsOptionalOnDisk() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = """
        {
          "schemaVersion": 1,
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "pageOrder": [],
          "createdAt": "\(ISODate.string(from: date))",
          "updatedAt": "\(ISODate.string(from: date))"
        }
        """
        let decoded = try ManifestCodec.decode(Data(legacy.utf8))
        #expect(decoded.lastOpenedAt == nil)
        #expect(decoded.schemaVersion == SchemaVersion.current)

        let encoded = String(decoding: try ManifestCodec.encode(decoded), as: UTF8.self)
        #expect(!encoded.contains("lastOpenedAt"))
    }

    /// An optional field is an additive change: the same bytes decode to the
    /// same manifest, and the open date survives the round trip.
    @Test func openedDateRoundTrips() throws {
        let opened = Date(timeIntervalSince1970: 1_700_000_100)
        let manifest = NotebookManifest(
            id: UUID(),
            title: "Round trip",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_050),
            lastOpenedAt: opened
        )
        let data = try ManifestCodec.encode(manifest)
        let decoded = try ManifestCodec.decode(data)
        #expect(decoded == manifest)
        #expect(decoded.lastOpenedAt == opened)
        #expect(decoded.schemaVersion == SchemaVersion.current)
    }

    /// Marking a notebook opened records the date and leaves the edit date —
    /// and therefore a grid sorted by date modified — alone.
    @Test func markOpenedKeepsUpdatedAt() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()

        let created = try await store.createNotebook(title: "Opened")
        let opened = Date(timeIntervalSince1970: 1_700_000_200)
        try await store.markOpened(created.id, at: opened)

        let loaded = try await store.loadManifest(created.id)
        #expect(loaded.lastOpenedAt == opened)
        #expect(loaded.updatedAt == created.updatedAt)
        #expect(loaded.pageOrder == created.pageOrder)
    }
}
