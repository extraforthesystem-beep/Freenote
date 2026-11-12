import Foundation

/// Where the history lives:
///
///     <root>/notebooks/<notebook-id>/index.json
///     <root>/notebooks/<notebook-id>/<timestamp>-<hash>-<id>.snapshot
///
/// A notebook's metadata is one small index; its payloads are separate files.
private struct HistoryLayout {
    let root: URL

    var notebooksDirectory: URL {
        root.appendingPathComponent("notebooks", isDirectory: true)
    }

    var trashDirectory: URL {
        root.appendingPathComponent(".trash", isDirectory: true)
    }

    func notebookDirectory(_ notebookID: UUID) -> URL {
        notebooksDirectory.appendingPathComponent(
            notebookID.uuidString.lowercased(), isDirectory: true
        )
    }

    func indexFile(_ notebookID: UUID) -> URL {
        notebookDirectory(notebookID).appendingPathComponent("index.json", isDirectory: false)
    }
}

private struct HistoryIndex: Codable, Sendable {
    var schemaVersion: Int
    var entries: [HistoryIndexEntry]
}

private struct HistoryIndexEntry: Codable, Hashable, Sendable {
    var snapshot: VersionSnapshot
    var fileName: String
}

/// Local, never-synced version history for notebooks and pages.
///
/// Each `record` writes the payload first and the index second. If the index
/// write fails, the payload is removed again, so the index can never name a file
/// that does not exist. A crash between the two writes leaves only an orphan
/// payload, which is invisible to `list` and removed by `prune`.
///
/// The actor serialises every operation; the file system is the source of truth
/// and nothing is cached between calls.
public actor VersionHistoryStore {
    /// The directory this store reads and writes. History is local-only.
    public nonisolated let root: URL

    private static let schemaVersion = 1
    private let layout: HistoryLayout
    private let writer: any HistoryFileWriting
    private let fileManager = FileManager.default

    /// Opens (or creates on first record) a history store rooted at `root`.
    public init(root: URL) {
        self.init(root: root, writer: LiveFileWriter())
    }

    /// Test seam: a writer that can fail on a chosen write.
    init(root: URL, writer: any HistoryFileWriting) {
        self.root = root
        self.layout = HistoryLayout(root: root)
        self.writer = writer
    }

    // MARK: - Recording

    /// Writes `data` as a new snapshot and returns its metadata.
    ///
    /// The payload is written before the index entry. If the index cannot be
    /// written, the payload is rolled back and the error is rethrown.
    @discardableResult
    public func record(
        data: Data,
        notebookID: UUID,
        pageID: UUID? = nil,
        reason: String,
        now: Date = Date()
    ) async throws -> VersionSnapshot {
        let milliseconds = now.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= Double(Int64.min),
              milliseconds < Double(Int64.max) else {
            throw HistoryKitError.invalidInput("snapshot time is out of range")
        }
        try createDirectory(layout.notebookDirectory(notebookID))

        var index = try loadIndex(notebookID)
        let hash = HistoryHash.sha256Hex(data)
        let id = UUID()
        let fileName = Self.payloadFileName(createdAt: now, hash: hash, id: id)
        let snapshot = VersionSnapshot(
            id: id,
            notebookID: notebookID,
            pageID: pageID,
            createdAt: now,
            reason: reason,
            dataHash: hash,
            byteCount: data.count
        )
        let payloadURL = layout.notebookDirectory(notebookID)
            .appendingPathComponent(fileName, isDirectory: false)

        do {
            try writer.write(data, to: payloadURL)
        } catch {
            throw HistoryKitError.ioFailure("could not write snapshot payload: \(error)")
        }

        index.entries.append(HistoryIndexEntry(snapshot: snapshot, fileName: fileName))
        do {
            try writeIndex(index, notebookID: notebookID)
        } catch {
            // No metadata means no visible snapshot. Remove the payload so a
            // failed record leaves nothing behind.
            try? fileManager.removeItem(at: payloadURL)
            throw error
        }
        return snapshot
    }

    // MARK: - Reading

    /// Every snapshot in a notebook, newest first.
    ///
    /// An index entry is returned even if its payload has since disappeared;
    /// `load(snapshot:)` then reports the corruption instead of silently
    /// pretending the history never existed.
    public func list(notebookID: UUID) async throws -> [VersionSnapshot] {
        let index = try loadIndex(notebookID)
        return index.entries.map(\.snapshot).sorted(by: SnapshotOrder.isNewer)
    }

    /// Reads a snapshot's bytes and verifies them against the stored hash and size.
    public func load(snapshot: VersionSnapshot) async throws -> Data {
        let index = try loadIndex(snapshot.notebookID)
        guard let entry = index.entries.first(where: { $0.snapshot.id == snapshot.id }) else {
            throw HistoryKitError.snapshotNotFound(snapshot.id)
        }

        let url = layout.notebookDirectory(snapshot.notebookID)
            .appendingPathComponent(entry.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path) else {
            throw HistoryKitError.corruptSnapshot(
                id: snapshot.id, reason: "payload file is missing"
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HistoryKitError.ioFailure("could not read snapshot payload: \(error)")
        }

        guard data.count == entry.snapshot.byteCount else {
            throw HistoryKitError.corruptSnapshot(
                id: snapshot.id,
                reason: "byte count \(data.count) does not match \(entry.snapshot.byteCount)"
            )
        }
        guard HistoryHash.sha256Hex(data) == entry.snapshot.dataHash else {
            throw HistoryKitError.corruptSnapshot(
                id: snapshot.id, reason: "content hash does not match"
            )
        }
        return data
    }

    /// Total size of all snapshot payloads, excluding indexes and deleted history.
    public func totalBytes() async throws -> Int {
        var total = 0
        for notebookID in try notebookIDs() {
            let directory = layout.notebookDirectory(notebookID)
            for name in try contents(of: directory) where name.hasSuffix(".snapshot") {
                let url = directory.appendingPathComponent(name, isDirectory: false)
                do {
                    let values = try url.resourceValues(
                        forKeys: [.isRegularFileKey, .fileSizeKey]
                    )
                    guard values.isRegularFile == true, let size = values.fileSize else {
                        continue
                    }
                    total += size
                } catch {
                    throw HistoryKitError.ioFailure(
                        "could not measure snapshot payload: \(error)"
                    )
                }
            }
        }
        return total
    }

    // MARK: - Retention

    /// Applies `policy` across every notebook and returns the deleted metadata,
    /// oldest first.
    ///
    /// The index is rewritten before any payload is removed. A crash therefore
    /// leaves an orphan payload, never an index entry whose bytes are gone.
    @discardableResult
    public func prune(
        keeping policy: SnapshotPolicy = .default,
        now: Date = Date()
    ) async throws -> [VersionSnapshot] {
        let notebookIDs = try notebookIDs()
        var indexes: [UUID: HistoryIndex] = [:]
        for notebookID in notebookIDs {
            indexes[notebookID] = try loadIndex(notebookID)
        }

        let all = indexes.values.flatMap { $0.entries.map(\.snapshot) }
        let plan = Set(policy.prunePlan(snapshots: all, now: now))

        guard !plan.isEmpty else {
            try sweepOrphans(notebookIDs: notebookIDs, indexes: indexes)
            return []
        }

        var deleted: [VersionSnapshot] = []
        for notebookID in notebookIDs {
            guard var index = indexes[notebookID] else { continue }
            let removed = index.entries.filter { plan.contains($0.snapshot.id) }
            guard !removed.isEmpty else { continue }

            index.entries.removeAll { plan.contains($0.snapshot.id) }
            try writeIndex(index, notebookID: notebookID)
            indexes[notebookID] = index

            for entry in removed {
                let url = layout.notebookDirectory(notebookID)
                    .appendingPathComponent(entry.fileName, isDirectory: false)
                do {
                    try fileManager.removeItem(at: url)
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    // Already gone; the metadata removal is what matters.
                } catch {
                    throw HistoryKitError.ioFailure(
                        "could not delete snapshot payload: \(error)"
                    )
                }
                deleted.append(entry.snapshot)
            }
        }

        try sweepOrphans(notebookIDs: notebookIDs, indexes: indexes)
        return deleted.sorted(by: SnapshotOrder.isOlder)
    }

    // MARK: - Deleting

    /// Removes a notebook's entire history, leaving other notebooks untouched.
    ///
    /// The directory is first renamed into `<root>/.trash`, so a partially
    /// deleted history is never visible through `list`.
    public func deleteNotebook(_ notebookID: UUID) async throws {
        let directory = layout.notebookDirectory(notebookID)
        guard fileManager.fileExists(atPath: directory.path) else { return }

        try createDirectory(layout.trashDirectory)
        let staged = layout.trashDirectory.appendingPathComponent(
            "\(notebookID.uuidString.lowercased())-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.moveItem(at: directory, to: staged)
        } catch {
            throw HistoryKitError.ioFailure("could not remove notebook history: \(error)")
        }
        do {
            try fileManager.removeItem(at: staged)
        } catch {
            throw HistoryKitError.ioFailure("could not delete staged notebook history: \(error)")
        }
    }

    // MARK: - Index

    private func loadIndex(_ notebookID: UUID) throws -> HistoryIndex {
        let file = layout.indexFile(notebookID)
        guard fileManager.fileExists(atPath: file.path) else {
            return HistoryIndex(schemaVersion: Self.schemaVersion, entries: [])
        }

        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw HistoryKitError.ioFailure("could not read history index: \(error)")
        }

        let decoded: HistoryIndex
        do {
            decoded = try HistoryJSON.decoder().decode(HistoryIndex.self, from: data)
        } catch {
            throw HistoryKitError.corruptIndex(notebookID: notebookID, reason: "\(error)")
        }

        guard decoded.schemaVersion <= Self.schemaVersion else {
            throw HistoryKitError.unsupportedIndexVersion(
                notebookID: notebookID,
                found: decoded.schemaVersion,
                supported: Self.schemaVersion
            )
        }

        var seen = Set<UUID>()
        for entry in decoded.entries {
            guard Self.isSafeFileName(entry.fileName) else {
                throw HistoryKitError.corruptIndex(
                    notebookID: notebookID,
                    reason: "unsafe payload file name \(entry.fileName)"
                )
            }
            guard entry.snapshot.notebookID == notebookID else {
                throw HistoryKitError.corruptIndex(
                    notebookID: notebookID,
                    reason: "entry \(entry.snapshot.id) belongs to another notebook"
                )
            }
            guard seen.insert(entry.snapshot.id).inserted else {
                throw HistoryKitError.corruptIndex(
                    notebookID: notebookID,
                    reason: "duplicate snapshot id \(entry.snapshot.id)"
                )
            }
        }
        return decoded
    }

    private func writeIndex(_ index: HistoryIndex, notebookID: UUID) throws {
        var sorted = index
        sorted.entries.sort { SnapshotOrder.isNewer($0.snapshot, than: $1.snapshot) }
        sorted.schemaVersion = Self.schemaVersion

        let data: Data
        do {
            data = try HistoryJSON.encoder().encode(sorted)
        } catch {
            throw HistoryKitError.ioFailure("could not encode history index: \(error)")
        }

        do {
            try writer.write(data, to: layout.indexFile(notebookID))
        } catch {
            throw HistoryKitError.ioFailure("could not write history index: \(error)")
        }
    }

    // MARK: - Directory helpers

    private func notebookIDs() throws -> [UUID] {
        let directory = layout.notebooksDirectory
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try contents(of: directory)
            .compactMap(UUID.init(uuidString:))
            .sorted { $0.uuidString < $1.uuidString }
    }

    private func contents(of directory: URL) throws -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw HistoryKitError.ioFailure("could not list history directory: \(error)")
        }
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw HistoryKitError.ioFailure(
                "could not create directory \(url.lastPathComponent): \(error)"
            )
        }
    }

    /// Removes payloads and temporary files that the index does not reference.
    private func sweepOrphans(
        notebookIDs: [UUID],
        indexes: [UUID: HistoryIndex]
    ) throws {
        for notebookID in notebookIDs {
            let directory = layout.notebookDirectory(notebookID)
            let referenced = Set((indexes[notebookID]?.entries ?? []).map(\.fileName))
            for name in try contents(of: directory) {
                let isPayload = name.hasSuffix(".snapshot") && !referenced.contains(name)
                let isTemporary = name.hasPrefix(".tmp-")
                guard isPayload || isTemporary else { continue }
                do {
                    try fileManager.removeItem(
                        at: directory.appendingPathComponent(name, isDirectory: false)
                    )
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    // Raced with another cleanup; nothing to do.
                } catch {
                    throw HistoryKitError.ioFailure(
                        "could not remove orphaned history file: \(error)"
                    )
                }
            }
        }
    }

    private static func payloadFileName(createdAt: Date, hash: String, id: UUID) -> String {
        let milliseconds = Int64((createdAt.timeIntervalSince1970 * 1_000).rounded())
        return "\(milliseconds)-\(hash.prefix(16))-\(id.uuidString.lowercased()).snapshot"
    }

    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
    }
}
