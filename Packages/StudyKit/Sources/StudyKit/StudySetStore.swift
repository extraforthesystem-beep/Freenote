import Foundation

/// One set file that could not be read, and why.
public struct StudySetLoadIssue: Hashable, Sendable {
    /// Path of the file that failed.
    public let path: String
    /// A human-readable reason, safe to show beside a Retry action.
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// The result of listing a study-set directory: what could be read, plus what
/// could not. A listing never fails because of a single bad file.
public struct StudySetListing: Sendable {
    /// Every set that decoded, in the same order as ``StudySetStore/list()``.
    public let sets: [StudySet]
    /// Files that were skipped because they could not be read.
    public let issues: [StudySetLoadIssue]

    public init(sets: [StudySet], issues: [StudySetLoadIssue] = []) {
        self.sets = sets
        self.issues = issues
    }
}

/// Persists study sets as one JSON file per set under a root directory.
///
/// A file is named `<uuid>.json`, where the id is the set's `id` lowercased.
/// Every save encodes the whole set first and then writes it with an atomic
/// replacement, so a reader sees either the complete old file or the complete
/// new one, never a partial document. There is no in-memory cache: `list`,
/// `load` and `delete` always reflect the directory.
public actor StudySetStore {
    /// The directory holding the set files.
    public nonisolated let root: URL

    private let fileManager = FileManager.default

    /// Creates a store rooted at `root`; the directory is created on first save or `open`.
    public init(root: URL) {
        self.root = root
    }

    /// Creates the root directory if needed.
    public func open() throws {
        try createDirectory(root)
    }

    /// The file a set with this id is stored in.
    public nonisolated func fileURL(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString.lowercased() + ".json", isDirectory: false)
    }

    /// Every readable set in the directory, oldest first and then by id for stability.
    ///
    /// Files that are not named after a UUID are ignored. A UUID-named file
    /// that cannot be decoded is skipped, so one corrupt file never hides the
    /// rest of the library; use ``listReportingIssues()`` to see what was skipped.
    public func list() throws -> [StudySet] {
        try listReportingIssues().sets
    }

    /// Lists every readable set and reports the files that had to be skipped.
    ///
    /// Only a failure to read the directory itself throws. Unreadable or
    /// mismatched set files are returned in ``StudySetListing/issues``.
    public func listReportingIssues() throws -> StudySetListing {
        var sets: [StudySet] = []
        var issues: [StudySetLoadIssue] = []
        for url in try contents(of: root) where url.pathExtension.lowercased() == "json" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                continue
            }
            do {
                sets.append(try load(id))
            } catch {
                let message = (error as? StudyKitError)?.description
                    ?? error.localizedDescription
                issues.append(StudySetLoadIssue(path: url.path, message: message))
            }
        }
        sets.sort { left, right in
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return left.id.uuidString < right.id.uuidString
        }
        return StudySetListing(sets: sets, issues: issues)
    }

    /// Loads one set, verifying that the file name and the encoded id agree.
    public func load(_ id: UUID) throws -> StudySet {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StudyKitError.notFound(path: url.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StudyKitError.ioFailure("read \(url.path): \(error)")
        }

        let set: StudySet
        do {
            set = try JSONDecoder().decode(StudySet.self, from: data)
        } catch {
            throw StudyKitError.corruptFile(path: url.path)
        }
        guard set.id == id else {
            throw StudyKitError.corruptFile(path: url.path)
        }
        return set
    }

    /// Writes a set atomically, creating the root directory when needed.
    public func save(_ set: StudySet) throws {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            data = try encoder.encode(set)
        } catch {
            throw StudyKitError.ioFailure("encode set \(set.id.uuidString): \(error)")
        }

        let url = fileURL(for: set.id)
        try createDirectory(root)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw StudyKitError.ioFailure("write \(url.path): \(error)")
        }
    }

    /// Removes a set's file. Deleting an unknown id throws `notFound`.
    public func delete(_ id: UUID) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StudyKitError.notFound(path: url.path)
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw StudyKitError.ioFailure("delete \(url.path): \(error)")
        }
    }

    // MARK: - File helpers

    private func createDirectory(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw StudyKitError.ioFailure("create \(url.path): \(error)")
        }
    }

    private func contents(of directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        do {
            return try fileManager
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw StudyKitError.ioFailure("list \(directory.path): \(error)")
        }
    }
}
