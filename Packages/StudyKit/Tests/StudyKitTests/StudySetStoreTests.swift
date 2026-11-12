import Foundation
import StudyKit
import Testing

@Suite("Study set store")
struct StudySetStoreTests {
    @Test func saveLoadAndListRoundTripExactly() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudySetStore(root: root)
        try await store.open()

        let empty = try await store.list()
        #expect(empty.isEmpty)

        let precise = testNow.addingTimeInterval(0.123_456_789)
        let card = StudyCard(
            question: "What is a joule?",
            answer: "One newton-metre.",
            imageAssetName: "diagram.png",
            sourceNotebookID: UUID(),
            sourcePageID: UUID(),
            createdAt: precise,
            updatedAt: precise.addingTimeInterval(1)
        )
        let set = StudySet(
            title: "Physics",
            cards: [card],
            createdAt: precise,
            updatedAt: precise.addingTimeInterval(2),
            colorTag: "amber"
        )

        try await store.save(set)

        let file = store.fileURL(for: set.id)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(file.lastPathComponent == set.id.uuidString.lowercased() + ".json")

        let loaded = try await store.load(set.id)
        #expect(loaded == set)
        #expect(loaded.cards[0].imageAssetName == "diagram.png")

        let listed = try await store.list()
        #expect(listed == [set])

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names == [file.lastPathComponent], "only the set file should remain; no temporary files")
    }

    @Test func saveCreatesTheRootAndAtomicallyReplacesAnExistingFile() async throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("nested/sets", isDirectory: true)
        let store = StudySetStore(root: root)

        var set = makeSet(cardCount: 2, title: "Draft")
        try await store.save(set)
        #expect(FileManager.default.fileExists(atPath: root.path))

        set.title = "Final"
        set.cards.append(makeCard(99))
        set.updatedAt = testNow.addingTimeInterval(60)
        try await store.save(set)

        let loaded = try await store.load(set.id)
        #expect(loaded == set)
        #expect(loaded.cards.count == 3)

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names == [set.id.uuidString.lowercased() + ".json"])
    }

    @Test func listSortsByCreationDateRegardlessOfSaveOrder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudySetStore(root: root)

        let older = StudySet(
            title: "Older",
            cards: [],
            createdAt: testNow.addingTimeInterval(-1_000),
            updatedAt: testNow
        )
        let newer = StudySet(
            title: "Newer",
            cards: [],
            createdAt: testNow,
            updatedAt: testNow
        )

        try await store.save(newer)
        try await store.save(older)

        let listed = try await store.list()
        #expect(listed.map(\.id) == [older.id, newer.id])
    }

    @Test func listIgnoresFilesThatAreNotUuidNamedJson() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudySetStore(root: root)
        let set = makeSet(cardCount: 1)
        try await store.save(set)

        try Data("ignored".utf8).write(to: root.appendingPathComponent("notes.json"))
        try Data("ignored".utf8).write(to: root.appendingPathComponent(".hidden.json"))

        let listed = try await store.list()
        #expect(listed == [set])
    }

    @Test func deleteRemovesTheFileAndReportsMissingSets() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudySetStore(root: root)
        let set = makeSet(cardCount: 1)
        try await store.save(set)

        try await store.delete(set.id)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: set.id).path))

        let listed = try await store.list()
        #expect(listed.isEmpty)

        let missingPath = store.fileURL(for: set.id).path
        await expectAsyncError(.notFound(path: missingPath)) {
            _ = try await store.load(set.id)
        }
        await expectAsyncError(.notFound(path: missingPath)) {
            try await store.delete(set.id)
        }
    }

    @Test func loadUnknownSetThrowsNotFound() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudySetStore(root: root)
        let id = UUID()

        await expectAsyncError(.notFound(path: store.fileURL(for: id).path)) {
            _ = try await store.load(id)
        }
    }

    @Test func corruptJsonThrowsTypedError() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudySetStore(root: root)
        let id = UUID()
        let file = store.fileURL(for: id)

        try Data("not a study set".utf8).write(to: file)

        await expectAsyncError(.corruptFile(path: file.path)) {
            _ = try await store.load(id)
        }

        // A listing skips the bad file instead of throwing.
        let listing = try await store.listReportingIssues()
        #expect(listing.sets.isEmpty)
        #expect(listing.issues.count == 1)
        #expect(listing.issues.first?.path.hasSuffix(file.lastPathComponent) == true)
        #expect(listing.issues.first?.message.contains("Corrupt study set file") == true)
    }

    @Test func listReportsCorruptFilesAndKeepsTheRestOfTheLibrary() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudySetStore(root: root)

        let kept = makeSet(cardCount: 2, title: "Keep me")
        try await store.save(kept)

        let corruptID = UUID()
        let corruptFile = store.fileURL(for: corruptID)
        try Data("{ this is not json".utf8).write(to: corruptFile)

        let listing = try await store.listReportingIssues()
        #expect(listing.sets == [kept])
        #expect(listing.issues.count == 1)
        #expect(listing.issues.first?.path.hasSuffix(corruptFile.lastPathComponent) == true)

        // The convenience API returns the same readable sets without throwing.
        let listed = try await store.list()
        #expect(listed == [kept])
    }

    @Test func fileWhoseEncodedIdDoesNotMatchItsNameThrowsTypedError() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudySetStore(root: root)

        let stored = makeSet(cardCount: 1, title: "Stored")
        let wrongName = UUID()
        let encoder = JSONEncoder()
        let data = try encoder.encode(stored)
        try data.write(to: store.fileURL(for: wrongName))

        await expectAsyncError(.corruptFile(path: store.fileURL(for: wrongName).path)) {
            _ = try await store.load(wrongName)
        }
    }
}
