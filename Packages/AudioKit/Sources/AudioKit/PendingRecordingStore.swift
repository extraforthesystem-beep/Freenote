import Foundation

/// Owns the durable folder a recording is written to until it is finalised.
///
/// `AVAudioRecorder` writes the `.m4a` while recording, so a crash leaves the
/// recorded audio in the notebook instead of in the temporary folder. A JSON
/// sidecar written at the same moment records the metadata the finished clip
/// needs, so recovery does not have to guess.
///
/// Nothing here deletes audio on an error path: a failed finalise keeps the file
/// and sidecar for the next ``files()`` pass.
public struct PendingRecordingStore: Sendable {
    /// Folder holding `<recording-id>.m4a` and `<recording-id>.json`.
    public let rootURL: URL

    /// Extension of pending audio, matching the recorder's container.
    public static let audioExtension = "m4a"
    private static let sidecarExtension = "json"

    /// Creates a store rooted at `rootURL`; the folder is created by ``prepare()``.
    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Destination the recorder should write for `id`.
    public func audioURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(
            "\(id.uuidString.lowercased()).\(Self.audioExtension)",
            isDirectory: false
        )
    }

    /// Sidecar location for `id`, whether or not it exists.
    public func sidecarURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(
            "\(id.uuidString.lowercased()).\(Self.sidecarExtension)",
            isDirectory: false
        )
    }

    /// Creates the pending folder, or throws instead of letting the recorder fail
    /// later with a less useful message.
    public func prepare() throws {
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

    /// Writes the sidecar atomically. The audio is already being recorded, so a
    /// failure here only loses the metadata shortcut, never the audio.
    public func begin(_ recording: PendingRecording) throws {
        let data: Data
        do {
            data = try AudioJSON.makeEncoder().encode(recording)
        } catch {
            throw AudioKitError.storeFailure(
                "could not encode pending recording \(recording.id.uuidString): "
                    + error.localizedDescription
            )
        }
        do {
            try data.write(to: sidecarURL(for: recording.id), options: [.atomic])
        } catch {
            throw AudioKitError.storeFailure(
                "could not write pending recording \(recording.id.uuidString): "
                    + error.localizedDescription
            )
        }
    }

    /// Every pending audio file, oldest first.
    ///
    /// A missing or unreadable sidecar yields `nil` metadata rather than hiding
    /// the audio, so recovery can still keep the recording.
    public func files() throws -> [PendingRecordingFile] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw AudioKitError.storeFailure("\(rootURL.path) is not a directory")
        }

        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: rootURL.path)
        } catch {
            throw AudioKitError.storeFailure(
                "could not list \(rootURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        var files: [PendingRecordingFile] = []
        for name in names where name.hasSuffix(".\(Self.audioExtension)") {
            let stem = String(name.dropLast(Self.audioExtension.count + 1))
            guard let id = UUID(uuidString: stem) else { continue }
            let audioURL = rootURL.appendingPathComponent(name, isDirectory: false)
            let values = try? audioURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            files.append(
                PendingRecordingFile(
                    id: id,
                    audioURL: audioURL,
                    sidecarURL: sidecarURL(for: id),
                    sidecar: loadSidecar(for: id),
                    fileSize: values?.fileSize ?? -1,
                    modifiedAt: values?.contentModificationDate
                )
            )
        }
        return files.sorted { lhs, rhs in
            let left = lhs.sidecar?.startedAt ?? lhs.modifiedAt ?? .distantPast
            let right = rhs.sidecar?.startedAt ?? rhs.modifiedAt ?? .distantPast
            if left != right { return left < right }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Deletes the audio and its sidecar. Missing files are ignored, so a retried
    /// finalise is safe.
    public func remove(id: UUID) throws {
        var failure: String?
        for url in [audioURL(for: id), sidecarURL(for: id)] {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                failure = "could not remove \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if let failure {
            throw AudioKitError.storeFailure(failure)
        }
    }

    /// Best-effort read: corrupt or missing metadata must not hide the audio.
    private func loadSidecar(for id: UUID) -> PendingRecording? {
        let url = sidecarURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? AudioJSON.makeDecoder().decode(PendingRecording.self, from: data)
    }
}
