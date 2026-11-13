import Foundation

/// Metadata written beside an in-progress recording so a crash cannot lose it.
///
/// The sidecar sits next to the audio file in the notebook's `audio/pending/`
/// folder and is removed only after the audio has been copied into the notebook's
/// assets and the finished ``AudioClip`` has been saved.
public struct PendingRecording: Codable, Hashable, Sendable {
    /// The identity the finished ``AudioClip`` will have.
    public var id: UUID
    /// Wall-clock time at which recording started.
    public var startedAt: Date
    /// Monotonic host uptime at the same moment, in seconds.
    public var monotonicAnchorSeconds: TimeInterval
    /// Title the finished clip will get, for example `"Recording 3"`.
    public var title: String
    /// The ordinal in that title. Kept separately so a blank title can still be
    /// rebuilt as `"Recording <number>"` after a crash.
    public var number: Int

    /// Creates a sidecar for a recording that has just started.
    public init(
        id: UUID,
        startedAt: Date,
        monotonicAnchorSeconds: TimeInterval,
        title: String,
        number: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.monotonicAnchorSeconds = monotonicAnchorSeconds
        self.title = title
        self.number = number
    }
}

/// One audio file found in the pending folder, with whatever metadata survived.
public struct PendingRecordingFile: Hashable, Sendable {
    /// Identity the recovered clip will use. The file name is authoritative: it
    /// cannot disagree with itself the way a sidecar can.
    public var id: UUID
    /// The recording still in the pending folder.
    public var audioURL: URL
    /// Where the sidecar would be, whether or not it exists.
    public var sidecarURL: URL
    /// `nil` when the sidecar is missing, unreadable or not valid JSON.
    public var sidecar: PendingRecording?
    /// Size of the audio file in bytes, or `-1` when the file system could not
    /// report it (treated as "not empty", so nothing is deleted by accident).
    public var fileSize: Int
    /// Last write to the audio file, the best fallback clock for a crash.
    public var modifiedAt: Date?

    /// Creates a descriptor for one pending file.
    public init(
        id: UUID,
        audioURL: URL,
        sidecarURL: URL,
        sidecar: PendingRecording?,
        fileSize: Int,
        modifiedAt: Date?
    ) {
        self.id = id
        self.audioURL = audioURL
        self.sidecarURL = sidecarURL
        self.sidecar = sidecar
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }

    /// Whether the recorder never wrote a frame, so there is no audio to keep.
    /// An unknown size is not empty.
    public var isEmpty: Bool { fileSize == 0 }

    /// Builds the clip for a recording interrupted by a crash.
    ///
    /// The sidecar supplies the start time, monotonic anchor and title. Without a
    /// readable sidecar the start is estimated as the file's last write minus its
    /// duration, the strongest signal left after a crash, and the clip keeps the
    /// caller's fallback title. A missing anchor becomes zero: uptime from before
    /// the relaunch cannot be compared with the current boot.
    ///
    /// - Parameters:
    ///   - assetName: Name the audio was stored under in the notebook's assets.
    ///   - durationSeconds: Duration read from the file; non-finite values become zero.
    ///   - fallbackTitle: Title to use when no sidecar title survived.
    ///   - createdAt: Timestamp for the new metadata record.
    public func recoveredClip(
        assetName: String,
        durationSeconds: TimeInterval,
        fallbackTitle: String,
        createdAt: Date = Date()
    ) -> AudioClip {
        let duration = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        let sidecarStart = sidecar?.startedAt
        let startedAt: Date
        let anchor: TimeInterval
        if let sidecarStart, sidecarStart.timeIntervalSinceReferenceDate.isFinite {
            startedAt = sidecarStart
            anchor = Self.validAnchor(sidecar?.monotonicAnchorSeconds)
        } else {
            startedAt = (modifiedAt ?? createdAt).addingTimeInterval(-duration)
            anchor = 0
        }

        let title = sidecar?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle: String
        if !title.isEmpty {
            resolvedTitle = title
        } else if let number = sidecar?.number, number > 0 {
            resolvedTitle = "Recording \(number)"
        } else {
            resolvedTitle = fallbackTitle
        }

        return AudioClip(
            id: id,
            assetName: assetName,
            startedAt: startedAt,
            monotonicAnchorSeconds: anchor,
            durationSeconds: duration,
            createdAt: createdAt,
            title: resolvedTitle
        )
    }

    private static func validAnchor(_ value: TimeInterval?) -> TimeInterval {
        guard let value, value.isFinite, value >= 0 else { return 0 }
        return value
    }
}
