import Foundation

/// Writes bytes to a file atomically. Internal so tests can inject a failure.
protocol HistoryFileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

/// The production writer: a hidden temporary file in the destination directory,
/// flushed to disk, then renamed over the target.
struct LiveFileWriter: HistoryFileWriting {
    func write(_ data: Data, to url: URL) throws {
        try AtomicFile.write(data, to: url)
    }
}

/// Atomic single-file replacement.
///
/// The temporary file is created in the same directory as the target, so the
/// final `moveItem` or `replaceItemAt` stays on one volume and cannot expose a
/// half-written file. A crash leaves the old file intact and at worst a hidden
/// `.tmp-` file, which `VersionHistoryStore.prune` sweeps away.
enum AtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = directory.appendingPathComponent(
            ".tmp-\(UUID().uuidString)", isDirectory: false
        )
        defer { try? manager.removeItem(at: temporary) }

        try data.write(to: temporary, options: [])

        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }
}
