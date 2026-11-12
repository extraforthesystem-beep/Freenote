import Foundation

/// One audio recording that belongs to a document, not to a page.
///
/// A clip can span page turns, so it stores no page reference. `startedAt`
/// anchors stroke timestamps to playback offsets; `monotonicAnchorSeconds` is the
/// authority when the wall clock is adjusted. See ``AudioAnchor``.
public struct AudioClip: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity. ``AudioClipStore`` also uses it as the metadata file name.
    public var id: UUID
    /// Name of the audio asset in the document's asset directory, for example `"A1B2.m4a"`.
    public var assetName: String
    /// Wall-clock time at which recording started.
    public var startedAt: Date
    /// `ProcessInfo.processInfo.systemUptime` at record start, in seconds.
    ///
    /// Monotonic, and unaffected by wall-clock changes, so it is the authority
    /// for how much time has passed since recording began.
    public var monotonicAnchorSeconds: Double
    /// Length of the recorded file in seconds. The store rejects negative or non-finite values.
    public var durationSeconds: Double
    /// When this metadata record was created.
    public var createdAt: Date
    /// User-visible name, for example `"Lecture 4"`.
    public var title: String

    /// Creates a clip. `createdAt` defaults to now and `title` to an empty string.
    public init(
        id: UUID = UUID(),
        assetName: String,
        startedAt: Date,
        monotonicAnchorSeconds: Double,
        durationSeconds: Double,
        createdAt: Date = Date(),
        title: String = ""
    ) {
        self.id = id
        self.assetName = assetName
        self.startedAt = startedAt
        self.monotonicAnchorSeconds = monotonicAnchorSeconds
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.title = title
    }
}
