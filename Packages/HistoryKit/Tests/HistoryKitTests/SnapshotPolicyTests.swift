import Foundation
import Testing
@testable import HistoryKit

@Suite("Snapshot retention policy")
struct SnapshotPolicyTests {
    @Test func defaultsMatchTheDocumentedValues() {
        let policy = SnapshotPolicy()
        #expect(policy.maxSnapshotsPerPage == 20)
        #expect(policy.dailyKeepDays == 7)
        #expect(policy.maxTotalBytes == 200 * 1_024 * 1_024)
    }

    @Test func codableRoundTripsAndMissingFieldsUseDefaults() throws {
        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 3, dailyKeepDays: 2, maxTotalBytes: 1_000
        )
        let encoded = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(SnapshotPolicy.self, from: encoded)
        #expect(decoded == policy)

        let partial = Data(#"{"maxSnapshotsPerPage":5}"#.utf8)
        let defaults = try JSONDecoder().decode(SnapshotPolicy.self, from: partial)
        #expect(defaults.maxSnapshotsPerPage == 5)
        #expect(defaults.dailyKeepDays == 7)
        #expect(defaults.maxTotalBytes == 200 * 1_024 * 1_024)
    }

    @Test func keepsTheNewestSnapshotsOfEachPage() {
        let notebookID = UUID()
        let pageA = UUID()
        let pageB = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        var snapshots: [VersionSnapshot] = []
        for index in 0..<5 {
            snapshots.append(
                makeSnapshot(
                    notebookID: notebookID,
                    pageID: pageA,
                    createdAt: now.addingTimeInterval(Double(index) * 60)
                )
            )
            snapshots.append(
                makeSnapshot(
                    notebookID: notebookID,
                    pageID: pageB,
                    createdAt: now.addingTimeInterval(Double(index) * 60)
                )
            )
        }

        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 2, dailyKeepDays: 0, maxTotalBytes: 0
        )
        let deleted = Set(policy.prunePlan(snapshots: snapshots, now: now.addingTimeInterval(300)))

        // Two newest of each page stay, the other three of each page go.
        #expect(deleted.count == 6)
        for page in [pageA, pageB] {
            let pageSnapshots = snapshots
                .filter { $0.pageID == page }
                .sorted(by: SnapshotOrder.isNewer)
            #expect(!deleted.contains(pageSnapshots[0].id))
            #expect(!deleted.contains(pageSnapshots[1].id))
            #expect(deleted.contains(pageSnapshots[2].id))
            #expect(deleted.contains(pageSnapshots[3].id))
            #expect(deleted.contains(pageSnapshots[4].id))
        }
    }

    @Test func keepsOneSnapshotPerDayForTheDailyWindow() {
        let notebookID = UUID()
        let pageID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // One snapshot per day, newest first.
        let snapshots = (0..<10).map { index in
            makeSnapshot(
                notebookID: notebookID,
                pageID: pageID,
                createdAt: now.addingTimeInterval(-Double(index) * 86_400)
            )
        }

        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 2, dailyKeepDays: 7, maxTotalBytes: 0
        )
        let deleted = Set(policy.prunePlan(snapshots: snapshots, now: now))

        // Newest two by count plus days 0...6 by the daily rule: 7 kept, 3 gone.
        #expect(deleted == Set([snapshots[7].id, snapshots[8].id, snapshots[9].id]))
    }

    @Test func dailyRuleKeepsTheNewestSnapshotOfEachDay() {
        let notebookID = UUID()
        let pageID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let today = makeSnapshot(
            notebookID: notebookID,
            pageID: pageID,
            createdAt: now.addingTimeInterval(-60)
        )
        let yesterdayEarly = makeSnapshot(
            notebookID: notebookID,
            pageID: pageID,
            createdAt: now.addingTimeInterval(-86_400 - 3_600)
        )
        let yesterdayLate = makeSnapshot(
            notebookID: notebookID,
            pageID: pageID,
            createdAt: now.addingTimeInterval(-86_400 - 60)
        )

        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 1, dailyKeepDays: 7, maxTotalBytes: 0
        )
        let deleted = Set(
            policy.prunePlan(
                snapshots: [today, yesterdayEarly, yesterdayLate], now: now
            )
        )

        // The count rule keeps today; the daily rule keeps the later snapshot of yesterday.
        #expect(!deleted.contains(today.id))
        #expect(!deleted.contains(yesterdayLate.id))
        #expect(deleted.contains(yesterdayEarly.id))
    }

    @Test func byteBudgetDeletesOldestUntilUnderTheCap() {
        let notebookID = UUID()
        let pageID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Five 100-byte snapshots, index 4 newest.
        let snapshots = (0..<5).map { index in
            makeSnapshot(
                notebookID: notebookID,
                pageID: pageID,
                createdAt: now.addingTimeInterval(-Double(4 - index) * 60),
                byteCount: 100
            )
        }

        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 10, dailyKeepDays: 0, maxTotalBytes: 250
        )
        let deleted = Set(policy.prunePlan(snapshots: snapshots, now: now))

        // 500 bytes must fall to at most 250: delete the three oldest.
        #expect(deleted == Set([snapshots[0].id, snapshots[1].id, snapshots[2].id]))
    }

    @Test func byteBudgetNeverDeletesTheNewestSnapshotOfAPage() {
        let notebookID = UUID()
        let pageA = UUID()
        let pageB = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let newestA = makeSnapshot(
            notebookID: notebookID,
            pageID: pageA,
            createdAt: now.addingTimeInterval(-100),
            byteCount: 1_000
        )
        let newestB = makeSnapshot(
            notebookID: notebookID,
            pageID: pageB,
            createdAt: now.addingTimeInterval(-200),
            byteCount: 1_000
        )

        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 10, dailyKeepDays: 0, maxTotalBytes: 1
        )
        let deleted = policy.prunePlan(snapshots: [newestA, newestB], now: now)

        // The budget cannot be met without erasing the only recovery point of a page.
        #expect(deleted.isEmpty)
    }

    @Test func zeroLimitsDisableCountAndByteRules() {
        let notebookID = UUID()
        let pageID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = (0..<4).map { index in
            makeSnapshot(
                notebookID: notebookID,
                pageID: pageID,
                createdAt: now.addingTimeInterval(Double(index) * 60),
                byteCount: 10_000
            )
        }

        // maxSnapshotsPerPage is clamped to one, so the newest survives.
        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 0, dailyKeepDays: 0, maxTotalBytes: 0
        )
        let deleted = Set(policy.prunePlan(snapshots: snapshots, now: now))
        #expect(deleted.count == 3)
        #expect(!deleted.contains(snapshots[3].id))
    }

    @Test func shouldPruneMatchesThePlan() {
        let notebookID = UUID()
        let pageID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = (0..<4).map { index in
            makeSnapshot(
                notebookID: notebookID,
                pageID: pageID,
                createdAt: now.addingTimeInterval(Double(index) * 60)
            )
        }

        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 1, dailyKeepDays: 0, maxTotalBytes: 0
        )
        #expect(policy.shouldPrune(snapshots[0], in: snapshots, now: now))
        #expect(!policy.shouldPrune(snapshots[3], in: snapshots, now: now))
        #expect(policy.shouldPrune(snapshots: snapshots, now: now))
    }

    @Test func aPolicyWithinItsLimitsNeedsNoPruning() {
        let notebookID = UUID()
        let pageID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = (0..<3).map { index in
            makeSnapshot(
                notebookID: notebookID,
                pageID: pageID,
                createdAt: now.addingTimeInterval(Double(index) * 60),
                byteCount: 10
            )
        }

        let policy = SnapshotPolicy(
            maxSnapshotsPerPage: 20, dailyKeepDays: 7, maxTotalBytes: 1_000
        )
        #expect(!policy.shouldPrune(snapshots: snapshots, now: now))
        #expect(policy.prunePlan(snapshots: snapshots, now: now).isEmpty)
    }

    @Test func emptyHistoryHasNoPlan() {
        let policy = SnapshotPolicy()
        #expect(policy.prunePlan(snapshots: [], now: Date()).isEmpty)
    }

    @Test func snapshotIsCodable() throws {
        let snapshot = VersionSnapshot(
            notebookID: UUID(),
            pageID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.123_456),
            reason: "manual",
            dataHash: String(repeating: "b", count: 64),
            byteCount: 42
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(VersionSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}
