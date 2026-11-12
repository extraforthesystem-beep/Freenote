import Foundation

/// Retention rules for local version history.
///
/// The rules are deliberately independent of the store: `prunePlan` is a pure
/// function over snapshot metadata, so the same inputs always produce the same
/// deletion plan. The store applies the plan to disk.
public struct SnapshotPolicy: Codable, Hashable, Sendable {
    /// Keep at least this many newest snapshots for every page. Values below one
    /// are treated as one so a page always keeps a recovery point.
    public var maxSnapshotsPerPage: Int
    /// Keep the newest snapshot from each of the last N calendar days (UTC).
    public var dailyKeepDays: Int
    /// Delete the oldest remaining snapshots until the total fits this byte budget.
    /// Zero or a negative value disables the budget.
    public var maxTotalBytes: Int

    /// Creates a policy; every argument defaults to the documented value.
    public init(
        maxSnapshotsPerPage: Int = 20,
        dailyKeepDays: Int = 7,
        maxTotalBytes: Int = 200 * 1_024 * 1_024
    ) {
        self.maxSnapshotsPerPage = maxSnapshotsPerPage
        self.dailyKeepDays = dailyKeepDays
        self.maxTotalBytes = maxTotalBytes
    }

    /// The documented defaults: 20 snapshots per page, 7 daily keeps, 200 MB.
    public static let `default` = SnapshotPolicy()

    /// Decodes missing fields as the defaults so a policy written by an older
    /// build keeps working after a field is added.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxSnapshotsPerPage = try container.decodeIfPresent(
            Int.self, forKey: .maxSnapshotsPerPage
        ) ?? 20
        dailyKeepDays = try container.decodeIfPresent(
            Int.self, forKey: .dailyKeepDays
        ) ?? 7
        maxTotalBytes = try container.decodeIfPresent(
            Int.self, forKey: .maxTotalBytes
        ) ?? 200 * 1_024 * 1_024
    }

    /// True when `snapshot` is part of the deletion plan for `history`.
    ///
    /// Pass the complete history the store would prune, including `snapshot`.
    public func shouldPrune(
        _ snapshot: VersionSnapshot,
        in history: [VersionSnapshot],
        now: Date = Date()
    ) -> Bool {
        prunePlan(snapshots: history, now: now).contains(snapshot.id)
    }

    /// True when any snapshot in `snapshots` would be deleted.
    public func shouldPrune(
        snapshots: [VersionSnapshot],
        now: Date = Date()
    ) -> Bool {
        !prunePlan(snapshots: snapshots, now: now).isEmpty
    }

    /// The ids to delete, oldest first.
    ///
    /// The plan keeps the newest `maxSnapshotsPerPage` snapshots of every
    /// (notebook, page) pair, plus the newest snapshot of each of the last
    /// `dailyKeepDays` UTC days. It then removes the oldest remaining snapshots
    /// until `maxTotalBytes` is met. The newest snapshot of a page is never
    /// removed by the byte budget, so a budget smaller than one snapshot per page
    /// can stay exceeded rather than erase the only recovery point.
    public func prunePlan(snapshots: [VersionSnapshot], now: Date) -> [UUID] {
        guard !snapshots.isEmpty else { return [] }

        let keepCount = max(1, maxSnapshotsPerPage)
        let dailyDays = max(0, dailyKeepDays)
        var groups: [PageKey: [VersionSnapshot]] = [:]
        for snapshot in snapshots {
            groups[
                PageKey(notebookID: snapshot.notebookID, pageID: snapshot.pageID),
                default: []
            ].append(snapshot)
        }

        var keep = Set<UUID>()
        let today = Self.utcCalendar.startOfDay(for: now)
        let oldestDailyDay = dailyDays > 0
            ? Self.utcCalendar.date(byAdding: .day, value: -(dailyDays - 1), to: today)
            : nil

        for group in groups.values {
            let sorted = group.sorted(by: SnapshotOrder.isNewer)
            keep.formUnion(sorted.prefix(keepCount).map(\.id))

            guard let oldestDailyDay else { continue }
            var days = Set<Date>()
            for snapshot in sorted {
                let day = Self.utcCalendar.startOfDay(for: snapshot.createdAt)
                guard day >= oldestDailyDay, day <= today else { continue }
                if days.insert(day).inserted {
                    keep.insert(snapshot.id)
                }
            }
        }

        var deleted = Set(snapshots.lazy.map(\.id).filter { !keep.contains($0) })

        if maxTotalBytes > 0 {
            let remaining = snapshots.filter { !deleted.contains($0.id) }
            var bytes = Self.saturatedTotalBytes(of: remaining)
            if bytes > maxTotalBytes {
                var protected = Set<UUID>()
                for group in groups.values {
                    if let newest = group.sorted(by: SnapshotOrder.isNewer).first {
                        protected.insert(newest.id)
                    }
                }

                let candidates = remaining
                    .filter { !protected.contains($0.id) }
                    .sorted(by: SnapshotOrder.isOlder)
                for candidate in candidates {
                    guard bytes > maxTotalBytes else { break }
                    if deleted.insert(candidate.id).inserted {
                        bytes -= max(0, candidate.byteCount)
                    }
                }
            }
        }

        return snapshots
            .filter { deleted.contains($0.id) }
            .sorted(by: SnapshotOrder.isOlder)
            .map(\.id)
    }

    private enum CodingKeys: String, CodingKey {
        case maxSnapshotsPerPage
        case dailyKeepDays
        case maxTotalBytes
    }

    private static func saturatedTotalBytes(of snapshots: [VersionSnapshot]) -> Int {
        var total = 0
        for snapshot in snapshots {
            let (sum, overflow) = total.addingReportingOverflow(max(0, snapshot.byteCount))
            total = overflow ? Int.max : sum
        }
        return total
    }

    private struct PageKey: Hashable {
        var notebookID: UUID
        var pageID: UUID?
    }

    /// UTC so retention does not change when the device changes time zone.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()
}
