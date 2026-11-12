import Foundation
import NoteCore

/// Maps a playback position to the stroke that was being written at that moment.
///
/// The controller is configured once per clip with the document's strokes. It
/// keeps a sorted anchor list, so a 60 Hz playhead does not re-sort thousands of
/// strokes on every frame.
public actor PlaybackController {
    private struct Anchor: Sendable {
        let strokeID: UUID
        let offset: TimeInterval
        let createdAt: Date
    }

    private var clip: AudioClip?
    private var anchors: [Anchor] = []

    /// Creates an empty controller; call ``configure(clip:strokes:)`` before use.
    public init() {}

    /// The clip currently loaded, or nil before ``configure(clip:strokes:)``.
    public var currentClip: AudioClip? {
        clip
    }

    /// Replaces the clip and its strokes.
    ///
    /// Strokes created outside the clip are ignored, so ink from before the
    /// recording never lights up at offset zero. Strokes inside the clip keep
    /// their clamped offset.
    public func configure(clip: AudioClip, strokes: [StrokeRecord]) {
        self.clip = clip
        let duration = clip.durationSeconds.isFinite ? max(0, clip.durationSeconds) : 0

        anchors = strokes.compactMap { stroke in
            let rawOffset = stroke.createdAt.timeIntervalSince(clip.startedAt)
            guard rawOffset.isFinite, rawOffset >= 0, rawOffset <= duration else {
                return nil
            }
            return Anchor(
                strokeID: stroke.id,
                offset: rawOffset,
                createdAt: stroke.createdAt
            )
        }.sorted { lhs, rhs in
            if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.strokeID.uuidString < rhs.strokeID.uuidString
        }
    }

    /// The most recently started stroke at `offset`, or nil outside the clip and
    /// before the first stroke.
    public func activeStrokeID(atPlaybackOffset offset: TimeInterval) -> UUID? {
        guard let clip else { return nil }
        let duration = clip.durationSeconds.isFinite ? max(0, clip.durationSeconds) : 0
        guard offset.isFinite, offset >= 0, offset <= duration, !anchors.isEmpty else {
            return nil
        }

        // Last anchor whose offset is <= the playhead.
        var low = 0
        var high = anchors.count
        while low < high {
            let middle = (low + high) / 2
            if anchors[middle].offset <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low == 0 ? nil : anchors[low - 1].strokeID
    }

    /// Playback offset at which `strokeID` was written, or nil when it is not part
    /// of the current clip.
    public func playbackOffset(forStrokeID strokeID: UUID) -> TimeInterval? {
        anchors.first(where: { $0.strokeID == strokeID })?.offset
    }

    /// Unloads the clip and its strokes.
    public func reset() {
        clip = nil
        anchors = []
    }
}
