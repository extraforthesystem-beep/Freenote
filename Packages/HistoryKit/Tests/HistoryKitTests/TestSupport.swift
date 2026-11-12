import Foundation
@testable import HistoryKit

/// A unique temporary directory that the caller removes when the test ends.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("HistoryKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The on-disk notebook directory the store uses for `notebookID`.
func notebookDirectory(root: URL, notebookID: UUID) -> URL {
    root
        .appendingPathComponent("notebooks", isDirectory: true)
        .appendingPathComponent(notebookID.uuidString.lowercased(), isDirectory: true)
}

/// Every `.snapshot` payload under `root`, wherever it is nested.
func payloadFiles(in root: URL) throws -> [URL] {
    let manager = FileManager.default
    guard let enumerator = manager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        return []
    }

    var files: [URL] = []
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true, url.pathExtension == "snapshot" else {
            continue
        }
        files.append(url)
    }
    return files
}

/// Metadata for policy tests; the hash is a fixed 64-character placeholder.
func makeSnapshot(
    notebookID: UUID,
    pageID: UUID?,
    createdAt: Date,
    byteCount: Int = 100,
    reason: String = "test"
) -> VersionSnapshot {
    VersionSnapshot(
        notebookID: notebookID,
        pageID: pageID,
        createdAt: createdAt,
        reason: reason,
        dataHash: String(repeating: "a", count: 64),
        byteCount: byteCount
    )
}

/// A writer failure injected at a chosen write, used to prove atomicity.
struct SimulatedWriteFailure: Error {}

/// Passes every write to the real file system except the chosen attempt.
final class FailingFileWriter: HistoryFileWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0
    private let failOnWrite: Int

    init(failOnWrite: Int) {
        self.failOnWrite = failOnWrite
    }

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return writes
    }

    func write(_ data: Data, to url: URL) throws {
        lock.lock()
        writes += 1
        let attempt = writes
        lock.unlock()

        guard attempt != failOnWrite else {
            throw SimulatedWriteFailure()
        }
        try data.write(to: url, options: .atomic)
    }
}
