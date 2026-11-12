import Foundation
import Testing
@testable import TextDocKit

@Suite("Text document store")
struct TextDocumentStoreTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "TextDocKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("Save, list, load and delete")
    func savesLoadsListsAndDeletes() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        let date = Date(timeIntervalSince1970: 1_700_000_000.125)
        let document = TextDocument(
            title: "Notes",
            blocks: [TextBlock(kind: .paragraph(text: "Hello"))],
            createdAt: date,
            updatedAt: date
        )

        let url = try await store.save(document)
        #expect(url.lastPathComponent == document.id.uuidString.lowercased() + ".json")

        let documents = try await store.list()
        #expect(documents == [document])

        let loaded = try await store.load(id: document.id)
        #expect(loaded == document)

        try await store.delete(id: document.id)
        let remaining = try await store.list()
        #expect(remaining.isEmpty)
    }

    @Test("Loading a missing document throws notFound")
    func loadMissingThrowsNotFound() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        let id = UUID()
        let expected = store.fileURL(for: id)

        await #expect(throws: TextDocError.notFound(path: expected.path)) {
            _ = try await store.load(id: id)
        }
    }

    @Test("A future schema is refused on load and list")
    func futureSchemaIsRefusedOnLoad() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        let id = UUID()
        let file = store.fileURL(for: id)
        let json = """
        {
          "schemaVersion": 2,
          "id": "\(id.uuidString)",
          "title": "Future",
          "blocks": [],
          "createdAt": 0,
          "updatedAt": 0
        }
        """
        try Data(json.utf8).write(to: file)

        let expected = TextDocError.unsupportedSchemaVersion(
            found: 2,
            supported: TextDocument.currentSchemaVersion
        )
        await #expect(throws: expected) {
            _ = try await store.load(id: id)
        }
        await #expect(throws: expected) {
            _ = try await store.list()
        }
    }

    @Test("A future schema is refused on save and writes nothing")
    func futureSchemaIsRefusedOnSave() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        let document = TextDocument(
            title: "Future",
            schemaVersion: TextDocument.currentSchemaVersion + 1
        )
        let expected = TextDocError.unsupportedSchemaVersion(
            found: TextDocument.currentSchemaVersion + 1,
            supported: TextDocument.currentSchemaVersion
        )

        await #expect(throws: expected) {
            _ = try await store.save(document)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(files.isEmpty)
    }

    @Test("A corrupt file is refused")
    func corruptFileIsRefused() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        let id = UUID()
        let file = store.fileURL(for: id)
        try Data("this is not a document".utf8).write(to: file)

        await #expect(throws: TextDocError.corruptFile(path: file.path)) {
            _ = try await store.load(id: id)
        }
    }

    @Test("Saving the same id replaces the file")
    func savingSameIDReplacesTheFile() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        var document = TextDocument(title: "First")

        _ = try await store.save(document)
        document.title = "Second"
        document.touch(at: Date(timeIntervalSince1970: 1_700_000_100))
        _ = try await store.save(document)

        let documents = try await store.list()
        #expect(documents.count == 1)
        #expect(documents.first?.title == "Second")

        let files = try FileManager.default
            .contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".json") }
        #expect(files.count == 1)
    }

    @Test("Timestamps round-trip exactly")
    func timestampsRoundTripExactly() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        let document = TextDocument(title: "Now", createdAt: Date(), updatedAt: Date())

        _ = try await store.save(document)
        let loaded = try await store.load(id: document.id)

        #expect(loaded.createdAt == document.createdAt)
        #expect(loaded.updatedAt == document.updatedAt)
    }

    @Test("List is ordered newest first")
    func listIsNewestFirst() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        let older = TextDocument(
            title: "Older",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = TextDocument(
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 1_700_000_500),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        _ = try await store.save(older)
        _ = try await store.save(newer)

        let documents = try await store.list()
        #expect(documents.map(\.title) == ["Newer", "Older"])

        let files = try FileManager.default
            .contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".json") }
        #expect(files.count == 2)
    }
}
