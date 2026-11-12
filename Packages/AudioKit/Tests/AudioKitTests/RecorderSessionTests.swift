import Foundation
import Testing
@testable import AudioKit

/// A recorder that never touches a microphone, so the lifecycle can be tested.
actor FakeRecorder: AudioRecorderSession {
    private let permission: AudioRecordingPermission
    private var recording = false
    private var elapsed: TimeInterval = 0
    private var startedAt: Date?
    private var anchor: TimeInterval = 0
    private var destination: URL?

    init(permission: AudioRecordingPermission = .granted) {
        self.permission = permission
    }

    var isRecording: Bool {
        recording
    }

    var elapsedSeconds: TimeInterval {
        elapsed
    }

    func requestPermission() async -> AudioRecordingPermission {
        permission
    }

    func start(writingTo url: URL) async throws -> AudioRecordingStart {
        guard permission == .granted else { throw AudioKitError.permissionDenied }
        guard !recording else { throw AudioKitError.alreadyRecording }

        let start = AudioRecordingStart(
            startedAt: testStart,
            monotonicAnchorSeconds: 5_000
        )
        recording = true
        elapsed = 0
        startedAt = start.startedAt
        anchor = start.monotonicAnchorSeconds
        destination = url
        return start
    }

    func stop() async throws -> AudioRecordingResult {
        guard recording, let startedAt, let destination else {
            throw AudioKitError.notRecording
        }
        recording = false
        elapsed = 12.5
        return AudioRecordingResult(
            fileURL: destination,
            startedAt: startedAt,
            monotonicAnchorSeconds: anchor,
            durationSeconds: 12.5
        )
    }

    /// Test hook: pretend time passed while recording.
    func advance(by seconds: TimeInterval) {
        elapsed += seconds
    }
}

@Suite("Recorder session")
struct RecorderSessionTests {
    @Test("A fake recorder follows start, elapsed, stop and restart")
    func lifecycle() async throws {
        let recorder = FakeRecorder()
        let url = URL(fileURLWithPath: "/tmp/fake-recording.m4a")

        #expect(await recorder.requestPermission() == .granted)
        #expect(await recorder.isRecording == false)
        #expect(await recorder.elapsedSeconds == 0)

        let start = try await recorder.start(writingTo: url)
        #expect(start.startedAt == testStart)
        #expect(start.monotonicAnchorSeconds == 5_000)
        #expect(await recorder.isRecording)

        await recorder.advance(by: 3)
        #expect(await recorder.elapsedSeconds == 3)

        // Starting twice is refused and leaves the first recording running.
        do {
            _ = try await recorder.start(writingTo: url)
            Issue.record("A second start should throw")
        } catch let error as AudioKitError {
            #expect(error == .alreadyRecording)
        }
        #expect(await recorder.isRecording)

        let result = try await recorder.stop()
        #expect(result.fileURL == url)
        #expect(result.startedAt == testStart)
        #expect(result.monotonicAnchorSeconds == 5_000)
        #expect(result.durationSeconds == 12.5)
        #expect(await recorder.isRecording == false)

        // Stopping twice is refused.
        do {
            _ = try await recorder.stop()
            Issue.record("A second stop should throw")
        } catch let error as AudioKitError {
            #expect(error == .notRecording)
        }

        // The same session can record again after a stop.
        _ = try await recorder.start(writingTo: url)
        #expect(await recorder.isRecording)
        _ = try await recorder.stop()
        #expect(await recorder.isRecording == false)
    }

    @Test("Denied permission blocks start")
    func deniedPermission() async {
        let recorder = FakeRecorder(permission: .denied)
        let url = URL(fileURLWithPath: "/tmp/denied.m4a")

        #expect(await recorder.requestPermission() == .denied)
        do {
            _ = try await recorder.start(writingTo: url)
            Issue.record("Start should throw without permission")
        } catch let error as AudioKitError {
            #expect(error == .permissionDenied)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await recorder.isRecording == false)
        #expect(await recorder.elapsedSeconds == 0)
    }

    @Test("A recording result builds a clip that keeps its anchor")
    func resultBuildsClip() async throws {
        let recorder = FakeRecorder()
        let url = URL(fileURLWithPath: "/tmp/clip.m4a")
        _ = try await recorder.start(writingTo: url)
        let result = try await recorder.stop()

        let clip = AudioClip(
            assetName: result.fileURL.lastPathComponent,
            startedAt: result.startedAt,
            monotonicAnchorSeconds: result.monotonicAnchorSeconds,
            durationSeconds: result.durationSeconds,
            title: "Recorded"
        )

        #expect(clip.assetName == "clip.m4a")
        #expect(clip.startedAt == testStart)
        #expect(clip.durationSeconds == 12.5)
        #expect(
            AudioAnchor.offset(for: testStart.addingTimeInterval(2.5), clip: clip) == 2.5
        )
    }
}
