import CryptoKit
import Foundation

/// Everything a backup can go wrong with.
public enum BackupError: Error, Hashable, Sendable {
    /// The destination already holds an archive with that name.
    case archiveExists(path: String)
    /// The folder does not have the backup layout.
    case notAnArchive(path: String)
    /// The archive was written by a newer build than this one.
    case unsupportedVersion(found: Int, supported: Int)
    /// `manifest.sha256` is not a list of hash and path pairs.
    case manifestUnreadable(path: String)
    /// A file listed in `manifest.sha256` is missing or has different bytes.
    case verificationFailed(path: String)
    /// The archive holds a file that `manifest.sha256` does not list.
    case unlistedFile(path: String)
    /// The filesystem refused an operation.
    case ioFailure(String)
}

extension BackupError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .archiveExists(path):
            "A backup already exists at \(path)."
        case let .notAnArchive(path):
            "\(path) is not a NoteApp backup."
        case let .unsupportedVersion(found, supported):
            "This backup was made by a newer version (\(found)); this build reads up to \(supported)."
        case let .manifestUnreadable(path):
            "The backup's manifest could not be read: \(path)."
        case let .verificationFailed(path):
            "The backup is damaged: \(path) does not match its recorded checksum."
        case let .unlistedFile(path):
            "The backup is damaged: \(path) is not listed in its manifest."
        case let .ioFailure(reason):
            "Backup error: \(reason)"
        }
    }
}

/// One library-wide backup: plain JSON, page files, attachments and a
/// `manifest.sha256` listing the hash of every file.
///
/// The archive is a directory with the `noteappbackup` extension rather than a
/// single compressed file, so it can be opened, copied and repaired with Files
/// and read by any JSON tool. What makes it trustworthy is not the container but
/// the hash manifest: `verify` recomputes every hash, and `restore` writes into
/// a staging folder, checks the copies and only then moves them into the library.
public enum BackupArchive {
    public static let fileExtension = "noteappbackup"
    public static let formatName = "noteapp-backup"
    public static let schemaVersion = 1

    /// The archive's own metadata, stored as `manifest.json`.
    public struct Manifest: Codable, Sendable, Hashable {
        public var format: String
        public var schemaVersion: Int
        public var createdAt: Date
        public var deviceID: String?
        public var notebookCount: Int
        public var pageCount: Int

        public init(
            format: String = BackupArchive.formatName,
            schemaVersion: Int = BackupArchive.schemaVersion,
            createdAt: Date,
            deviceID: String?,
            notebookCount: Int,
            pageCount: Int
        ) {
            self.format = format
            self.schemaVersion = schemaVersion
            self.createdAt = createdAt
            self.deviceID = deviceID
            self.notebookCount = notebookCount
            self.pageCount = pageCount
        }
    }

    /// What an archive holds, for showing a backup before restoring it.
    public struct Summary: Sendable, Hashable, Identifiable {
        public var url: URL
        public var manifest: Manifest
        public var fileCount: Int
        public var byteCount: Int

        public var id: URL { url }

        public init(url: URL, manifest: Manifest, fileCount: Int, byteCount: Int) {
            self.url = url
            self.manifest = manifest
            self.fileCount = fileCount
            self.byteCount = byteCount
        }
    }

    /// What a restore put back into the library.
    public struct RestoreSummary: Sendable, Hashable {
        /// Notebooks that were restored, in archive order.
        public var restoredNotebookIDs: [UUID]
        /// Restored notebooks that had to take a new id because their old one
        /// was still in the library or its trash.
        public var renamedNotebookIDs: [UUID]
        /// Notebook folders that were put back but whose `notebook.json` could
        /// not be read; they need repair, and nothing was thrown away.
        public var unreadableNotebookCount: Int
        public var pageCount: Int
        public var byteCount: Int

        public init(
            restoredNotebookIDs: [UUID] = [],
            renamedNotebookIDs: [UUID] = [],
            unreadableNotebookCount: Int = 0,
            pageCount: Int = 0,
            byteCount: Int = 0
        ) {
            self.restoredNotebookIDs = restoredNotebookIDs
            self.renamedNotebookIDs = renamedNotebookIDs
            self.unreadableNotebookCount = unreadableNotebookCount
            self.pageCount = pageCount
            self.byteCount = byteCount
        }
    }

    // MARK: - Creating

    /// Copies the library into a new archive at `url` and verifies every file
    /// before the archive is moved into place. A failure leaves nothing behind.
    public static func create(
        from store: LibraryStore,
        at url: URL,
        now: Date = Date()
    ) async throws -> Summary {
        let fileManager = FileManager.default
        let layout = LibraryLayout(root: store.root)
        let parent = url.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: url.path) else {
            throw BackupError.archiveExists(path: url.path)
        }
        let staging = parent.appendingPathComponent(
            ".\(UUID().uuidString).partial",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

            // library.json and folders.json are part of the archive even though a
            // restore keeps the destination library's own identity.
            for name in ["library.json", "folders.json"] {
                let source = layout.root.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(at: source, to: staging.appendingPathComponent(name))
            }

            let destinationNotebooks = staging
                .appendingPathComponent("notebooks", isDirectory: true)
            try fileManager.createDirectory(at: destinationNotebooks, withIntermediateDirectories: true)

            // Every notebook folder is copied, including one whose manifest does
            // not decode: a backup must not drop the very file that needs repair.
            let notebookFolders = try directories(in: layout.notebooksDirectory)
            for folder in notebookFolders {
                do {
                    try fileManager.copyItem(
                        at: folder,
                        to: destinationNotebooks.appendingPathComponent(
                            folder.lastPathComponent,
                            isDirectory: true
                        )
                    )
                } catch {
                    throw BackupError.ioFailure(
                        "could not copy \(folder.lastPathComponent): \(error)"
                    )
                }
            }

            let deviceInfo = try? LibraryInfoCodec.decode(
                Data(contentsOf: layout.libraryFile),
                path: layout.libraryFile.path
            )
            let pageCount = try regularFiles(in: destinationNotebooks)
                .filter { $0.pathExtension == "page" }
                .count
            let manifest = Manifest(
                createdAt: now,
                deviceID: deviceInfo?.deviceID.uuidString,
                notebookCount: notebookFolders.count,
                pageCount: pageCount
            )
            try write(manifest, to: staging.appendingPathComponent("manifest.json"))

            let hashes = try hashAllFiles(in: staging)
            try writeHashManifest(hashes, to: staging.appendingPathComponent("manifest.sha256"))

            // Prove the archive before it is given its final name.
            let expected = Dictionary(uniqueKeysWithValues: hashes.map { ($0.path, $0.hash) })
            try verifyFiles(in: staging, expected: expected)

            try fileManager.moveItem(at: staging, to: url)
            return Summary(
                url: url,
                manifest: manifest,
                fileCount: hashes.count,
                byteCount: hashes.reduce(0) { $0 + $1.byteCount }
            )
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    // MARK: - Reading

    /// Recomputes every hash in an archive. Throws if a file is missing, changed
    /// or not listed.
    @discardableResult
    public static func verify(archiveAt url: URL) async throws -> Summary {
        let verified = try verifiedFiles(in: url)
        return Summary(
            url: url,
            manifest: verified.manifest,
            fileCount: verified.hashes.count,
            byteCount: verified.hashes.reduce(0) { $0 + $1.byteCount }
        )
    }

    /// Every archive in `directory`, newest first. A folder that is not a
    /// readable backup is skipped rather than failing the list.
    public static func summaries(in directory: URL) -> [Summary] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names
            .filter { $0.hasSuffix("." + fileExtension) }
            .compactMap { name in
                let url = directory.appendingPathComponent(name, isDirectory: true)
                guard let manifest = try? readManifest(at: url) else { return nil }
                let files = (try? regularFiles(in: url)) ?? []
                let bytes = files.reduce(0) { $0 + byteCount(of: $1) }
                return Summary(
                    url: url,
                    manifest: manifest,
                    fileCount: files.count,
                    byteCount: bytes
                )
            }
            .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    // MARK: - Shared verification

    struct VerifiedFiles {
        var manifest: Manifest
        var hashes: [(path: String, hash: String, byteCount: Int)]
    }

    static func verifiedFiles(in url: URL) throws -> VerifiedFiles {
        let manifest = try readManifest(at: url)
        let hashFile = url.appendingPathComponent("manifest.sha256")
        guard let text = try? String(contentsOf: hashFile, encoding: .utf8) else {
            throw BackupError.manifestUnreadable(path: hashFile.path)
        }

        var expected: [(path: String, hash: String, byteCount: Int)] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count > 66 else {
                throw BackupError.manifestUnreadable(path: hashFile.path)
            }
            let hash = String(line.prefix(64)).lowercased()
            let path = String(line.dropFirst(66))
            guard hash.count == 64,
                  hash.allSatisfy({ $0.isHexDigit }),
                  !path.isEmpty,
                  !path.hasPrefix("/"),
                  !path.split(separator: "/").contains(".."),
                  seen.insert(path).inserted
            else {
                throw BackupError.manifestUnreadable(path: hashFile.path)
            }
            let file = url.appendingPathComponent(path)
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            expected.append((path: path, hash: hash, byteCount: size))
        }

        try verifyFiles(in: url, expected: Dictionary(
            uniqueKeysWithValues: expected.map { ($0.path, $0.hash) }
        ))
        return VerifiedFiles(manifest: manifest, hashes: expected)
    }

    static func verifyFiles(in root: URL, expected: [String: String]) throws {
        let listed = Set(expected.keys)
        for (path, expectedHash) in expected.sorted(by: { $0.key < $1.key }) {
            let file = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: file) else {
                throw BackupError.verificationFailed(path: path)
            }
            guard sha256Hex(data) == expectedHash else {
                throw BackupError.verificationFailed(path: path)
            }
        }
        for file in try regularFiles(in: root) {
            let path = relativePath(of: file, in: root)
            if path == "manifest.sha256" { continue }
            guard listed.contains(path) else {
                throw BackupError.unlistedFile(path: path)
            }
        }
    }

    static func readManifest(at url: URL) throws -> Manifest {
        let file = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: file) else {
            throw BackupError.notAnArchive(path: url.path)
        }
        let manifest: Manifest
        do {
            manifest = try NoteCoreJSON.decoder().decode(Manifest.self, from: data)
        } catch {
            throw BackupError.notAnArchive(path: url.path)
        }
        guard manifest.format == formatName else {
            throw BackupError.notAnArchive(path: url.path)
        }
        guard manifest.schemaVersion <= schemaVersion else {
            throw BackupError.unsupportedVersion(
                found: manifest.schemaVersion,
                supported: schemaVersion
            )
        }
        return manifest
    }

    // MARK: - File helpers

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data: Data
        do {
            data = try NoteCoreJSON.encoder(prettyPrinted: true).encode(value)
        } catch {
            throw BackupError.ioFailure("could not encode \(url.lastPathComponent): \(error)")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw BackupError.ioFailure("could not write \(url.lastPathComponent): \(error)")
        }
    }

    static func writeHashManifest(
        _ hashes: [(path: String, hash: String, byteCount: Int)],
        to url: URL
    ) throws {
        let text = hashes
            .sorted { $0.path < $1.path }
            .map { "\($0.hash)  \($0.path)\n" }
            .joined()
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw BackupError.ioFailure("could not write manifest.sha256: \(error)")
        }
    }

    /// The hash and size of every regular file under `root`, path-sorted.
    static func hashAllFiles(in root: URL) throws -> [(path: String, hash: String, byteCount: Int)] {
        try regularFiles(in: root).map { file in
            guard let data = try? Data(contentsOf: file) else {
                throw BackupError.verificationFailed(path: relativePath(of: file, in: root))
            }
            return (
                path: relativePath(of: file, in: root),
                hash: sha256Hex(data),
                byteCount: data.count
            )
        }
        .sorted { $0.path < $1.path }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Every regular file under `root`, including hidden-free, path-sorted.
    static func regularFiles(in root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let isFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile
            guard isFile == true else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    static func directories(in root: URL) throws -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        return names.sorted().compactMap { name in
            let url = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            return url
        }
    }

    static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    static func byteCount(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
