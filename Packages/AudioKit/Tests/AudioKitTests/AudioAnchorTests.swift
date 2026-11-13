import Foundation
import Testing
@testable import AudioKit

@Suite("Audio anchors")
struct AudioAnchorTests {
    @Test("Offsets are clamped to the clip")
    func offsetClamping() {
        let clip = makeClip(startedAt: testStart, durationSeconds: 30)

        #expect(AudioAnchor.offset(for: testStart.addingTimeInterval(12), clip: clip) == 12)
        #expect(AudioAnchor.offset(for: testStart, clip: clip) == 0)
        #expect(AudioAnchor.offset(for: testStart.addingTimeInterval(-5), clip: clip) == 0)
        #expect(AudioAnchor.offset(for: testStart.addingTimeInterval(30), clip: clip) == 30)
        #expect(AudioAnchor.offset(for: testStart.addingTimeInterval(45), clip: clip) == 30)
        #expect(AudioAnchor.offset(for: .distantFuture, clip: clip) == 30)
        #expect(AudioAnchor.offset(for: .distantPast, clip: clip) == 0)
    }

    @Test("Non-finite offsets become zero")
    func nonFiniteOffsets() {
        let clip = makeClip(startedAt: testStart, durationSeconds: 30)

        #expect(AudioAnchor.clampedOffset(.nan, clip: clip) == 0)
        #expect(AudioAnchor.clampedOffset(.infinity, clip: clip) == 0)
        #expect(AudioAnchor.clampedOffset(-.infinity, clip: clip) == 0)
        #expect(AudioAnchor.strokeTime(forPlaybackOffset: .nan, clip: clip) == testStart)
        #expect(AudioAnchor.clampedOffset(5, clip: makeClip(durationSeconds: .nan)) == 0)
        #expect(AudioAnchor.clampedOffset(5, clip: makeClip(durationSeconds: -10)) == 0)
    }

    @Test("Stroke time and playback offset round-trip")
    func strokeTimeRoundTrip() {
        let clip = makeClip(startedAt: testStart, durationSeconds: 30)

        let time = AudioAnchor.strokeTime(forPlaybackOffset: 7.5, clip: clip)
        #expect(time == testStart.addingTimeInterval(7.5))
        #expect(AudioAnchor.offset(for: time, clip: clip) == 7.5)

        #expect(
            AudioAnchor.strokeTime(forPlaybackOffset: 99, clip: clip)
                == testStart.addingTimeInterval(30)
        )
        #expect(
            AudioAnchor.strokeTime(forPlaybackOffset: -99, clip: clip)
                == testStart
        )
    }

    @Test("A wall-clock jump is subtracted from existing offsets")
    func wallClockJumpCorrection() {
        // The clock jumped 60 seconds ahead, so a wall-clock offset is 60 too large.
        #expect(
            AudioAnchor.clockJumpCorrectedOffset(offset: 120, wallClockDelta: 60) == 60
        )
        // The clock jumped 30 seconds back, so the offset is 30 too small.
        #expect(
            AudioAnchor.clockJumpCorrectedOffset(offset: 120, wallClockDelta: -30) == 150
        )
        // Correcting past the start lands on zero, never negative.
        #expect(
            AudioAnchor.clockJumpCorrectedOffset(offset: 10, wallClockDelta: 300) == 0
        )
        #expect(
            AudioAnchor.clockJumpCorrectedOffset(offset: .nan, wallClockDelta: 1) == 0
        )
        #expect(
            AudioAnchor.clockJumpCorrectedOffset(offset: 10, wallClockDelta: .infinity) == 0
        )

        let clip = makeClip(startedAt: testStart, durationSeconds: 100)
        let corrected = AudioAnchor.clockJumpCorrectedOffset(offset: 120, wallClockDelta: 30)
        #expect(AudioAnchor.clampedOffset(corrected, clip: clip) == 90)
    }

    @Test("The monotonic anchor ignores wall-clock changes")
    func monotonicAnchorAuthority() {
        let clip = makeClip(
            startedAt: testStart,
            monotonicAnchorSeconds: 1_000,
            durationSeconds: 60
        )

        #expect(AudioAnchor.monotonicOffset(nowUptime: 1_012, clip: clip) == 12)
        #expect(AudioAnchor.monotonicOffset(nowUptime: 999, clip: clip) == 0)
        #expect(AudioAnchor.monotonicOffset(nowUptime: 2_000, clip: clip) == 60)

        // A 500-second wall-clock step does not enter the monotonic path at all.
        let shifted = makeClip(
            startedAt: testStart.addingTimeInterval(-500),
            monotonicAnchorSeconds: 1_000,
            durationSeconds: 60
        )
        #expect(AudioAnchor.monotonicOffset(nowUptime: 1_012, clip: shifted) == 12)
    }
}
