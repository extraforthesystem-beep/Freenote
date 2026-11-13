import Foundation

/// Pure conversions between wall-clock stroke timestamps and playback offsets.
///
/// ## Which clock is authoritative
///
/// `AudioClip.startedAt` is wall-clock time. NTP can step it and the user can
/// change the date, so a difference between two wall-clock dates is only right
/// while the clock is steady. `AudioClip.monotonicAnchorSeconds` is a reading of
/// the host's monotonic uptime clock, which cannot be stepped, so it is the
/// authority for "how long ago did recording start". Use
/// ``monotonicOffset(nowUptime:clip:)`` for live playhead math and
/// ``clockJumpCorrectedOffset(offset:wallClockDelta:)`` to repair offsets that
/// were already derived from wall-clock dates.
///
/// The uptime clock is not a replacement for the recorded file's duration: it
/// does not advance while the device is asleep on every platform. `durationSeconds`
/// comes from the recorder, not from this clock.
public enum AudioAnchor {
    /// Reads the host's monotonic clock, in seconds since boot.
    public static func currentUptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// Playback offset of a stroke, clamped to `0...clip.durationSeconds`.
    public static func offset(for strokeCreatedAt: Date, clip: AudioClip) -> TimeInterval {
        clampedOffset(strokeCreatedAt.timeIntervalSince(clip.startedAt), clip: clip)
    }

    /// Wall-clock time for a playback position, clamped to the clip.
    public static func strokeTime(forPlaybackOffset offset: TimeInterval, clip: AudioClip) -> Date {
        clip.startedAt.addingTimeInterval(clampedOffset(offset, clip: clip))
    }

    /// Live playback offset derived from the monotonic anchor, clamped to the clip.
    public static func monotonicOffset(nowUptime: TimeInterval, clip: AudioClip) -> TimeInterval {
        clampedOffset(nowUptime - clip.monotonicAnchorSeconds, clip: clip)
    }

    /// Repairs an offset that was computed from wall-clock dates after the clock moved.
    ///
    /// `wallClockDelta` is how far the wall clock jumped forward relative to
    /// monotonic time: `+300` means it jumped five minutes ahead, so a wall-clock
    /// offset is five minutes too large. The result is never negative. Clamp it to
    /// the clip with ``clampedOffset(_:clip:)`` before seeking.
    public static func clockJumpCorrectedOffset(
        offset: TimeInterval,
        wallClockDelta: TimeInterval
    ) -> TimeInterval {
        guard offset.isFinite, wallClockDelta.isFinite else { return 0 }
        return max(0, offset - wallClockDelta)
    }

    /// Clamps any offset to `0...clip.durationSeconds`; NaN and infinity become 0.
    public static func clampedOffset(_ offset: TimeInterval, clip: AudioClip) -> TimeInterval {
        guard offset.isFinite else { return 0 }
        let duration = clip.durationSeconds.isFinite ? max(0, clip.durationSeconds) : 0
        return min(max(offset, 0), duration)
    }
}
