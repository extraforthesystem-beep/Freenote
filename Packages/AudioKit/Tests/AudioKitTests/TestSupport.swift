import Foundation
import NoteCore
@testable import AudioKit

/// A fixed wall-clock start for every synthetic clip in the tests.
let testStart = Date(timeIntervalSince1970: 1_760_000_000)

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AudioKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeClip(
    id: UUID = UUID(),
    assetName: String = "clip.m4a",
    startedAt: Date = testStart,
    monotonicAnchorSeconds: Double = 1_000,
    durationSeconds: Double = 60,
    createdAt: Date = testStart,
    title: String = "Test clip"
) -> AudioClip {
    AudioClip(
        id: id,
        assetName: assetName,
        startedAt: startedAt,
        monotonicAnchorSeconds: monotonicAnchorSeconds,
        durationSeconds: durationSeconds,
        createdAt: createdAt,
        title: title
    )
}

func makeStroke(id: UUID = UUID(), createdAt: Date) -> StrokeRecord {
    StrokeRecord(
        id: id,
        layerID: UUID(),
        tool: StrokeTool(
            engine: "metal",
            inkType: "pen",
            color: RGBAColor(r: 0, g: 0, b: 0),
            width: 2
        ),
        createdAt: createdAt,
        randomSeed: 1,
        points: []
    )
}
