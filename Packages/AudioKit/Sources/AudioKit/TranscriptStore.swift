import Foundation

/// Persists one transcript per clip as a small JSON file under a root directory.
///
/// Transcripts are derived data: the audio file is immutable and a transcript can
/// always be recognised again. The store still writes atomically, so a crash
/// never leaves half a file, and it rejects a transcript that cannot belong to a
/// clip before the disk is touched.
public actor TranscriptStore {
    /// Directory that holds the transcript files.
    public nonisolated let rootURL: URL

    private static let fileExtension = "json"

    /// Creates a store rooted at `rootURL`; the directory is created on first use.
    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// The file used for `clipID`.
    public nonisolated func transcriptURL(for clipID: UUID) -> URL {
        rootURL.appendingPathComponent(
            "\(clipID.uuidString.lowercased()).\(Self.fileExtension)",
            isDirectory: false
        )
    }

    /// Every stored transcript, sorted by clip id.
    public func list() throws -> [Transcript] {
        try ensureRoot()
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
        } catch {
            throw AudioKitError.storeFailure(
                "could not list \(rootURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        var transcripts: [Transcript] = []
        for name in names where name.hasSuffix(".\(Self.fileExtension)") {
            let stem = String(name.dropLast(Self.fileExtension.count + 1))
            guard let clipID = UUID(uuidString: stem) else { continue }
            transcripts.append(try decode(at: transcriptURL(for: clipID), clipID: clipID))
        }
        return transcripts.sorted { lhs, rhs in
            (lhs.clipID?.uuidString ?? "") < (rhs.clipID?.uuidString ?? "")
        }
    }

    /// The transcript for `clipID`, or nil when none is stored.
    public func load(clipID: UUID) throws -> Transcript? {
        let url = transcriptURL(for: clipID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(at: url, clipID: clipID)
    }

    /// Writes `transcript` atomically, replacing any previous one for its clip.
    ///
    /// Throws ``AudioKitError/invalidTranscript(_:)`` when the transcript is not
    /// attached to a clip or has a malformed segment.
    public func save(_ transcript: Transcript) throws {
        try Self.validate(transcript)
        try ensureRoot()
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(transcript)
        } catch {
            throw AudioKitError.storeFailure(
                "could not encode transcript: \(error.localizedDescription)"
            )
        }
        guard let clipID = transcript.clipID else {
            throw AudioKitError.invalidTranscript("no clip id")
        }
        do {
            try data.write(to: transcriptURL(for: clipID), options: [.atomic])
        } catch {
            throw AudioKitError.storeFailure(
                "could not write transcript \(clipID.uuidString): \(error.localizedDescription)"
            )
        }
    }

    /// Removes the transcript for `clipID`. A missing file is ignored, so
    /// replaying a delete is safe.
    public func delete(clipID: UUID) throws {
        let url = transcriptURL(for: clipID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw AudioKitError.storeFailure(
                "could not delete transcript \(clipID.uuidString): \(error.localizedDescription)"
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

    private func decode(at url: URL, clipID: UUID) throws -> Transcript {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AudioKitError.storeFailure(
                "could not read \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        let transcript: Transcript
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            transcript = try decoder.decode(Transcript.self, from: data)
        } catch {
            throw AudioKitError.corruptMetadata(url.lastPathComponent)
        }
        guard transcript.clipID == clipID else {
            throw AudioKitError.corruptMetadata(url.lastPathComponent)
        }
        return transcript
    }

    private static func validate(_ transcript: Transcript) throws {
        guard transcript.clipID != nil else {
            throw AudioKitError.invalidTranscript("no clip id")
        }
        for segment in transcript.segments {
            guard segment.startSeconds.isFinite, segment.endSeconds.isFinite,
                  segment.startSeconds >= 0, segment.endSeconds >= segment.startSeconds
            else {
                throw AudioKitError.invalidTranscript(
                    "segment \(segment.id.uuidString) has a malformed time range"
                )
            }
        }
    }
}
