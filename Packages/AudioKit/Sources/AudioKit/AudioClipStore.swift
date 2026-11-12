import Foundation

/// Persists one small JSON metadata file per clip under a root directory.
///
/// Audio files are caller-owned and live wherever the document keeps its assets;
/// this store only records metadata. Each write uses Foundation's atomic write
/// (a temporary file plus a rename), so a crash never leaves half a file, and an
/// invalid clip is rejected before the disk is touched.
///
/// Dates are stored as ISO-8601 with millisecond precision. That is plenty for
/// wall-clock fields because the monotonic anchor, not `startedAt`, decides how
/// much time has elapsed.
public actor AudioClipStore {
    /// Directory that holds the metadata files.
    public nonisolated let rootURL: URL

    private static let fileExtension = "json"

    /// Creates a store rooted at `rootURL`; the directory is created on first use.
    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// The metadata file used for `id`.
    public nonisolated func metadataURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(
            "\(id.uuidString.lowercased()).\(Self.fileExtension)",
            isDirectory: false
        )
    }

    /// Every clip in the store, sorted by `startedAt` and then by `id`.
    ///
    /// Throws ``AudioKitError/corruptMetadata(_:)`` when a `.json` file named after
    /// a UUID is not valid clip metadata. Unrelated files are ignored.
    public func list() throws -> [AudioClip] {
        try ensureRoot()
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
        } catch {
            throw AudioKitError.storeFailure(
                "could not list \(rootURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        var clips: [AudioClip] = []
        for name in names where name.hasSuffix(".\(Self.fileExtension)") {
            let stem = String(name.dropLast(Self.fileExtension.count + 1))
            guard let id = UUID(uuidString: stem) else { continue }
            clips.append(try decodeClip(at: metadataURL(for: id), expectedID: id))
        }
        return clips.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Loads one clip, or throws ``AudioKitError/clipNotFound(_:)``.
    public func load(id: UUID) throws -> AudioClip {
        let url = metadataURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioKitError.clipNotFound(id)
        }
        return try decodeClip(at: url, expectedID: id)
    }

    /// Writes `clip` atomically, replacing any previous metadata for the same id.
    ///
    /// Throws ``AudioKitError/invalidClip(_:)`` without touching the disk when the
    /// clip has an empty asset name, a negative or non-finite duration, or a
    /// non-finite clock value.
    public func save(_ clip: AudioClip) throws {
        try Self.validate(clip)
        try ensureRoot()
        let data: Data
        do {
            data = try Self.makeEncoder().encode(clip)
        } catch {
            throw AudioKitError.storeFailure(
                "could not encode clip \(clip.id.uuidString): \(error.localizedDescription)"
            )
        }
        do {
            try data.write(to: metadataURL(for: clip.id), options: [.atomic])
        } catch {
            throw AudioKitError.storeFailure(
                "could not write clip \(clip.id.uuidString): \(error.localizedDescription)"
            )
        }
    }

    /// Removes the metadata for `id`. A missing file is ignored, so replaying a
    /// delete is safe.
    public func delete(id: UUID) throws {
        let url = metadataURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw AudioKitError.storeFailure(
                "could not delete clip \(id.uuidString): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private

    private func ensureRoot() throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw AudioKitError.storeFailure("\(rootURL.path) is not a directory")
            }
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw AudioKitError.storeFailure(
                "could not create \(rootURL.path): \(error.localizedDescription)"
            )
        }
    }

    private func decodeClip(at url: URL, expectedID: UUID) throws -> AudioClip {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AudioKitError.storeFailure(
                "could not read \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        let clip: AudioClip
        do {
            clip = try Self.makeDecoder().decode(AudioClip.self, from: data)
        } catch {
            throw AudioKitError.corruptMetadata(url.lastPathComponent)
        }
        guard clip.id == expectedID else {
            throw AudioKitError.corruptMetadata(url.lastPathComponent)
        }
        return clip
    }

    private static func validate(_ clip: AudioClip) throws {
        guard !clip.assetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioKitError.invalidClip("assetName is empty")
        }
        guard clip.durationSeconds.isFinite, clip.durationSeconds >= 0 else {
            throw AudioKitError.invalidClip("durationSeconds must be finite and non-negative")
        }
        guard clip.monotonicAnchorSeconds.isFinite, clip.monotonicAnchorSeconds >= 0 else {
            throw AudioKitError.invalidClip(
                "monotonicAnchorSeconds must be finite and non-negative"
            )
        }
        guard clip.startedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AudioKitError.invalidClip("startedAt is not a finite date")
        }
        guard clip.createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AudioKitError.invalidClip("createdAt is not a finite date")
        }
    }

    /// `2026-11-12T10:22:33.123Z`. A formatter is created per call because
    /// `ISO8601DateFormatter` is not `Sendable`; metadata files are tiny, so the
    /// cost does not matter.
    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func date(fromISOString text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.isoString(from: date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = Self.date(fromISOString: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "not an ISO-8601 timestamp: \(text)"
                    )
                )
            }
            return date
        }
        return decoder
    }
}
