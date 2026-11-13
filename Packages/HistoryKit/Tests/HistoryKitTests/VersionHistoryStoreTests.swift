import Foundation
import Testing
@testable import HistoryKit

@Suite("Version history store")
struct VersionHistoryStoreTests {
    @Test func recordListAndLoadRoundTrip() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)

        let notebookID = UUID()
        let pageID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let firstData = Data("first page".utf8)
        let secondData = Data("second".utf8)
        let thirdData = Data("other".utf8)

        let first = try await store.record(
            data: firstData,
            notebookID: notebookID,
            pageID: pageID,
            reason: "autosave",
            now: base
        )
        let second = try await store.record(
            data: secondData,
            notebookID: notebookID,
            pageID: pageID,
            reason: "manual",
            now: base.addingTimeInterval(60)
        )
        let third = try await store.record(
            data: thirdData,
            notebookID: notebookID,
            pageID: UUID(),
            reason: "import",
            now: base.addingTimeInterval(120)
        )

        #expect(first.byteCount == firstData.count)
        #expect(first.dataHash == HistoryHash.sha256Hex(firstData))
        #expect(first.pageID == pageID)
        #expect(first.reason == "autosave")
        #expect(first.createdAt == base)

        let list = try await store.list(notebookID: notebookID)
        #expect(list.map(\.id) == [third.id, second.id, first.id])
        #expect(list.last?.createdAt == base)

        let loadedFirst = try await store.load(snapshot: first)
        #expect(loadedFirst == firstData)
        let loadedThird = try await store.load(snapshot: third)
        #expect(loadedThird == thirdData)

        let empty = try await store.list(notebookID: UUID())
        #expect(empty.isEmpty)

        let total = try await store.totalBytes()
        #expect(total == firstData.count + secondData.count + thirdData.count)
    }

    @Test func notebookLevelSnapshotHasNoPage() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)
        let notebookID = UUID()

        let snapshot = try await store.record(
            data: Data("notebook manifest".utf8),
            notebookID: notebookID,
            reason: "manifest backup",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(snapshot.pageID == nil)
        let list = try await store.list(notebookID: notebookID)
        #expect(list.map(\.id) == [snapshot.id])
    }

    @Test func emptyPayloadRoundTrips() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)
        let notebookID = UUID()

        let snapshot = try await store.record(
            data: Data(),
            notebookID: notebookID,
            pageID: UUID(),
            reason: "empty page",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(snapshot.byteCount == 0)
        #expect(snapshot.dataHash == HistoryHash.sha256Hex(Data()))

        let loaded = try await store.load(snapshot: snapshot)
        #expect(loaded.isEmpty)
    }

    @Test func notebooksAreIsolated() async throws {        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)

        let firstNotebook = UUID()
        let secondNotebook = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await store.record(
            data: Data("one".utf8),
            notebookID: firstNotebook,
            pageID: UUID(),
            reason: "auto",
            now: base
        )
        _ = try await store.record(
            data: Data("two".utf8),
            notebookID: secondNotebook,
            pageID: UUID(),
            reason: "auto",
            now: base
        )

        let firstList = try await store.list(notebookID: firstNotebook)
        let secondList = try await store.list(notebookID: secondNotebook)
        #expect(firstList.count == 1)
        #expect(secondList.count == 1)
        #expect(firstList[0].notebookID == firstNotebook)
        #expect(secondList[0].notebookID == secondNotebook)
    }

    @Test func pruneDeletesMetadataAndPayloads() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)

        let notebookID = UUID()
        let pageID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var recorded: [VersionSnapshot] = []
        for index in 0..<5 {
            let snapshot = try await store.record(
                data: Data(repeating: UInt8(index), count: 100 + index),
                notebookID: notebookID,
                pageID: pageID,
                reason: "auto",
                now: base.addingTimeInterval(Double(index) * 60)
            )
            recorded.append(snapshot)
        }

        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 2, dailyKeepDays: 0, maxTotalBytes: 0
        )
        let deleted = try await store.prune(
            keeping: policy, now: base.addingTimeInterval(10 * 60)
        )

        #expect(deleted.count == 3)
        #expect(deleted.map(\.id) == [recorded[0].id, recorded[1].id, recorded[2].id])

        let list = try await store.list(notebookID: notebookID)
        #expect(list.map(\.id) == [recorded[4].id, recorded[3].id])

        let files = try payloadFiles(in: root)
        #expect(files.count == 2)
        let total = try await store.totalBytes()
        #expect(total == recorded[3].byteCount + recorded[4].byteCount)
    }

    @Test func pruneAppliesAcrossNotebooks() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let firstNotebook = UUID()
        let secondNotebook = UUID()
        var newest: [UUID: VersionSnapshot] = [:]

        for notebookID in [firstNotebook, secondNotebook] {
            let pageID = UUID()
            for index in 0..<3 {
                let snapshot = try await store.record(
                    data: Data("\(notebookID)-\(index)".utf8),
                    notebookID: notebookID,
                    pageID: pageID,
                    reason: "auto",
                    now: base.addingTimeInterval(Double(index) * 60)
                )
                newest[notebookID] = snapshot
            }
        }

        let deleted = try await store.prune(
            keeping: SnapshotPolicy(
                maxSnapshotsPerPage: 1, dailyKeepDays: 0, maxTotalBytes: 0
            ),
            now: base.addingTimeInterval(10 * 60)
        )
        #expect(deleted.count == 4)

        for notebookID in [firstNotebook, secondNotebook] {
            let list = try await store.list(notebookID: notebookID)
            let expected = try #require(newest[notebookID])
            #expect(list.map(\.id) == [expected.id])
        }

        let files = try payloadFiles(in: root)
        #expect(files.count == 2)
    }

    @Test func deleteNotebookRemovesOnlyItsHistory() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)

        let firstNotebook = UUID()
        let secondNotebook = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await store.record(
            data: Data("gone".utf8),
            notebookID: firstNotebook,
            pageID: UUID(),
            reason: "auto",
            now: base
        )
        _ = try await store.record(
            data: Data("kept".utf8),
            notebookID: secondNotebook,
            pageID: UUID(),
            reason: "auto",
            now: base
        )

        try await store.deleteNotebook(firstNotebook)
        try await store.deleteNotebook(firstNotebook)

        let firstList = try await store.list(notebookID: firstNotebook)
        let secondList = try await store.list(notebookID: secondNotebook)
        #expect(firstList.isEmpty)
        #expect(secondList.count == 1)

        let total = try await store.totalBytes()
        #expect(total == Data("kept".utf8).count)
    }

    @Test func failedIndexWriteRollsBackThePayload() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notebookID = UUID()
        let writer = FailingFileWriter(failOnWrite: 2)
        let store = VersionHistoryStore(root: root, writer: writer)

        await #expect(throws: HistoryKitError.self) {
            _ = try await store.record(
                data: Data("payload".utf8),
                notebookID: notebookID,
                pageID: UUID(),
                reason: "autosave",
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }

        #expect(writer.writeCount == 2)
        let list = try await store.list(notebookID: notebookID)
        #expect(list.isEmpty)
        let files = try payloadFiles(in: root)
        #expect(files.isEmpty)

        let indexURL = notebookDirectory(root: root, notebookID: notebookID)
            .appendingPathComponent("index.json")
        #expect(!FileManager.default.fileExists(atPath: indexURL.path))
    }

    @Test func failedPayloadWriteLeavesNoSnapshot() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notebookID = UUID()
        let writer = FailingFileWriter(failOnWrite: 1)
        let store = VersionHistoryStore(root: root, writer: writer)

        await #expect(throws: HistoryKitError.self) {
            _ = try await store.record(
                data: Data("payload".utf8),
                notebookID: notebookID,
                pageID: UUID(),
                reason: "autosave",
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }

        #expect(writer.writeCount == 1)
        let list = try await store.list(notebookID: notebookID)
        #expect(list.isEmpty)
        let files = try payloadFiles(in: root)
        #expect(files.isEmpty)
    }

    @Test func nonFiniteSnapshotTimeIsRejected() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)

        await #expect(throws: HistoryKitError.self) {
            _ = try await store.record(
                data: Data("x".utf8),
                notebookID: UUID(),
                pageID: UUID(),
                reason: "auto",
                now: Date(timeIntervalSince1970: .infinity)
            )
        }

        let files = try payloadFiles(in: root)
        #expect(files.isEmpty)
    }

    @Test func aFailedRecordDoesNotBlockTheNextOne() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notebookID = UUID()
        let failing = VersionHistoryStore(
            root: root, writer: FailingFileWriter(failOnWrite: 2)
        )

        await #expect(throws: HistoryKitError.self) {
            _ = try await failing.record(
                data: Data("first".utf8),
                notebookID: notebookID,
                pageID: UUID(),
                reason: "auto",
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }

        let live = VersionHistoryStore(root: root)
        let recovered = try await live.record(
            data: Data("second".utf8),
            notebookID: notebookID,
            pageID: UUID(),
            reason: "auto",
            now: Date(timeIntervalSince1970: 1_700_000_060)
        )
        let list = try await live.list(notebookID: notebookID)
        #expect(list.map(\.id) == [recovered.id])
    }

    @Test func failedPruneIndexWriteKeepsEverySnapshot() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notebookID = UUID()
        let pageID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let live = VersionHistoryStore(root: root)

        for index in 0..<4 {
            _ = try await live.record(
                data: Data("data-\(index)".utf8),
                notebookID: notebookID,
                pageID: pageID,
                reason: "auto",
                now: base.addingTimeInterval(Double(index) * 60)
            )
        }

        let failing = VersionHistoryStore(
            root: root, writer: FailingFileWriter(failOnWrite: 1)
        )
        await #expect(throws: HistoryKitError.self) {
            _ = try await failing.prune(
                keeping: SnapshotPolicy(
                    maxSnapshotsPerPage: 1, dailyKeepDays: 0, maxTotalBytes: 0
                ),
                now: base.addingTimeInterval(10 * 60)
            )
        }

        let list = try await live.list(notebookID: notebookID)
        #expect(list.count == 4)
        let files = try payloadFiles(in: root)
        #expect(files.count == 4)
    }

    @Test func loadRejectsAPayloadThatNoLongerMatchesItsHash() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)
        let notebookID = UUID()

        let snapshot = try await store.record(
            data: Data("original".utf8),
            notebookID: notebookID,
            pageID: UUID(),
            reason: "auto",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let files = try payloadFiles(in: root)
        let payload = try #require(files.first)
        try Data("tampered".utf8).write(to: payload)

        await #expect(throws: HistoryKitError.self) {
            _ = try await store.load(snapshot: snapshot)
        }

        let list = try await store.list(notebookID: notebookID)
        #expect(list.count == 1)
    }

    @Test func loadRejectsAMissingPayload() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)
        let notebookID = UUID()

        let snapshot = try await store.record(
            data: Data("original".utf8),
            notebookID: notebookID,
            pageID: UUID(),
            reason: "auto",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let files = try payloadFiles(in: root)
        let payload = try #require(files.first)
        try FileManager.default.removeItem(at: payload)

        await #expect(throws: HistoryKitError.self) {
            _ = try await store.load(snapshot: snapshot)
        }
    }

    @Test func corruptIndexIsReported() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)
        let notebookID = UUID()

        _ = try await store.record(
            data: Data("one".utf8),
            notebookID: notebookID,
            pageID: UUID(),
            reason: "auto",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let indexURL = notebookDirectory(root: root, notebookID: notebookID)
            .appendingPathComponent("index.json")
        try Data("not json".utf8).write(to: indexURL)

        await #expect(throws: HistoryKitError.self) {
            _ = try await store.list(notebookID: notebookID)
        }
    }

    @Test func newerIndexSchemaIsRefused() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)
        let notebookID = UUID()

        _ = try await store.record(
            data: Data("one".utf8),
            notebookID: notebookID,
            pageID: UUID(),
            reason: "auto",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let indexURL = notebookDirectory(root: root, notebookID: notebookID)
            .appendingPathComponent("index.json")
        try Data(#"{"schemaVersion":99,"entries":[]}"#.utf8).write(to: indexURL)

        await #expect(throws: HistoryKitError.self) {
            _ = try await store.list(notebookID: notebookID)
        }
    }

    @Test func orphanPayloadsAreInvisibleAndSweptByPrune() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)
        let notebookID = UUID()

        let snapshot = try await store.record(
            data: Data("real".utf8),
            notebookID: notebookID,
            pageID: UUID(),
            reason: "auto",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let orphan = notebookDirectory(root: root, notebookID: notebookID)
            .appendingPathComponent("orphan.snapshot")
        try Data("orphan".utf8).write(to: orphan)

        let before = try await store.list(notebookID: notebookID)
        #expect(before.count == 1)

        _ = try await store.prune(
            keeping: SnapshotPolicy(
                maxSnapshotsPerPage: 20, dailyKeepDays: 0, maxTotalBytes: 0
            ),
            now: snapshot.createdAt
        )

        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        let after = try await store.list(notebookID: notebookID)
        #expect(after.map(\.id) == [snapshot.id])
    }

    @Test func totalBytesIgnoresTheIndex() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VersionHistoryStore(root: root)

        let data = Data(repeating: 0xAB, count: 1_024)
        _ = try await store.record(
            data: data,
            notebookID: UUID(),
            pageID: UUID(),
            reason: "auto",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let total = try await store.totalBytes()
        #expect(total == data.count)
    }
}
