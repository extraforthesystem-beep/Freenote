import Foundation
import NoteCore
import Testing
@testable import AudioKit

@Suite("Playback mapping")
struct PlaybackControllerTests {
    @Test("Playback offset maps to the most recently started stroke")
    func mapsOffsetToStroke() async {
        let clip = makeClip(startedAt: testStart, durationSeconds: 100)
        let before = makeStroke(createdAt: testStart.addingTimeInterval(-10))
        let first = makeStroke(createdAt: testStart.addingTimeInterval(10))
        let second = makeStroke(createdAt: testStart.addingTimeInterval(40))
        let after = makeStroke(createdAt: testStart.addingTimeInterval(150))

        let controller = PlaybackController()
        // Deliberately unsorted input.
        await controller.configure(
            clip: clip,
            strokes: [second, before, first, after]
        )

        #expect(await controller.currentClip == clip)
        #expect(await controller.activeStrokeID(atPlaybackOffset: -1) == nil)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 0) == nil)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 9.999) == nil)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 10) == first.id)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 39.999) == first.id)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 40) == second.id)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 100) == second.id)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 100.001) == nil)
        #expect(await controller.activeStrokeID(atPlaybackOffset: .nan) == nil)

        #expect(await controller.playbackOffset(forStrokeID: first.id) == 10)
        #expect(await controller.playbackOffset(forStrokeID: second.id) == 40)
        // Strokes outside the clip are not part of the mapping.
        #expect(await controller.playbackOffset(forStrokeID: before.id) == nil)
        #expect(await controller.playbackOffset(forStrokeID: after.id) == nil)
        #expect(await controller.playbackOffset(forStrokeID: UUID()) == nil)
    }

    @Test("A stroke on the clip boundary is included")
    func boundaryStrokes() async {
        let clip = makeClip(startedAt: testStart, durationSeconds: 20)
        let atStart = makeStroke(createdAt: testStart)
        let atEnd = makeStroke(createdAt: testStart.addingTimeInterval(20))

        let controller = PlaybackController()
        await controller.configure(clip: clip, strokes: [atEnd, atStart])

        #expect(await controller.activeStrokeID(atPlaybackOffset: 0) == atStart.id)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 20) == atEnd.id)
        #expect(await controller.playbackOffset(forStrokeID: atStart.id) == 0)
        #expect(await controller.playbackOffset(forStrokeID: atEnd.id) == 20)
    }

    @Test("Configure replaces state and reset unloads it")
    func configureAndReset() async {
        let clip = makeClip(startedAt: testStart, durationSeconds: 30)
        let stroke = makeStroke(createdAt: testStart.addingTimeInterval(5))

        let controller = PlaybackController()
        await controller.configure(clip: clip, strokes: [stroke])
        #expect(await controller.activeStrokeID(atPlaybackOffset: 5) == stroke.id)

        let replacement = makeClip(
            id: UUID(),
            startedAt: testStart.addingTimeInterval(1_000),
            durationSeconds: 10
        )
        await controller.configure(clip: replacement, strokes: [])
        #expect(await controller.currentClip == replacement)
        #expect(await controller.activeStrokeID(atPlaybackOffset: 5) == nil)

        await controller.reset()
        #expect(await controller.currentClip == nil)
        #expect(await controller.playbackOffset(forStrokeID: stroke.id) == nil)
    }
}
