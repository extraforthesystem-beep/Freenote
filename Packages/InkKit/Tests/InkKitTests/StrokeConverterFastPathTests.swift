// The append fast path in `IncrementalStrokeConverter` must return exactly the
// records the full path would, for every kind of change the canvas can report.
// The generator is seeded so a failure can be replayed.

import CoreGraphics
import Foundation
import InkKit
import NoteCore
import PencilKit
import Testing

/// A deterministic linear congruential generator: no system randomness, so a
/// failing sequence is reproducible from its seed.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed | 1
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    mutating func int(_ upperBound: Int) -> Int {
        Int(next() >> 33) % upperBound
    }
}

struct StrokeConverterFastPathTests {
    /// The two converters are driven with the same history. A calls the fast
    /// path for pure appends; B always calls the full path. After every step
    /// the results must be equal, including both being nil.
    @Test func appendFastPathMatchesFullPathForGeneratedChanges() {
        let layers = [UUID(), UUID()]
        for sequence in 0..<200 {
            var rng = SeededGenerator(seed: UInt64(sequence) &* 0x9E37_79B9_7F4A_7C15 &+ 17)
            let layer = layers[sequence % layers.count]
            var strokes = (0..<5).map {
                SampleStroke.stroke(style: .pen, index: $0, pointCount: 8 + $0)
            }
            let fast = IncrementalStrokeConverter()
            let full = IncrementalStrokeConverter()

            for step in 0..<30 {
                var appendedOnly = false
                switch rng.int(5) {
                case 0:
                    // Append one to three strokes at the end.
                    for _ in 0..<(1 + rng.int(3)) {
                        strokes.append(
                            SampleStroke.stroke(
                                style: rng.int(2) == 0 ? .pen : .marker,
                                index: rng.int(4),
                                pointCount: 4 + rng.int(24)
                            )
                        )
                    }
                    appendedOnly = true
                case 1:
                    // Remove one stroke at a random index.
                    if !strokes.isEmpty {
                        strokes.remove(at: rng.int(strokes.count))
                    }
                case 2:
                    // Remove the last stroke.
                    if !strokes.isEmpty {
                        strokes.removeLast()
                    }
                case 3:
                    // Swap two strokes.
                    if strokes.count >= 2 {
                        let first = rng.int(strokes.count)
                        var second = rng.int(strokes.count)
                        if first == second { second = (second + 1) % strokes.count }
                        strokes.swapAt(first, second)
                    }
                default:
                    // Replace one stroke with a changed stroke of the same id.
                    if strokes.isEmpty {
                        strokes.append(
                            SampleStroke.stroke(style: .pen, index: rng.int(4), pointCount: 6)
                        )
                    } else {
                        let index = rng.int(strokes.count)
                        var replacement = strokes[index]
                        replacement.transform = CGAffineTransform(
                            translationX: CGFloat(1 + rng.int(40)),
                            y: CGFloat(rng.int(40))
                        )
                        strokes[index] = replacement
                    }
                }

                let fastResult = fast.changedRecords(
                    from: strokes,
                    layerID: { _ in layer },
                    appendOnly: appendedOnly
                )
                let fullResult = full.changedRecords(
                    from: strokes,
                    layerID: { _ in layer },
                    appendOnly: false
                )
                #expect(
                    fastResult == fullResult,
                    "sequence \(sequence), step \(step), appendedOnly \(appendedOnly)"
                )
            }
        }
    }

    /// Even when the caller passes true, a prefix that differs, a shorter
    /// array or an equal-length array must give the full-path result.
    @Test func appendFastPathFallsBackWhenTheClaimDoesNotHold() {
        let layer = UUID()
        let initial = (0..<5).map {
            SampleStroke.stroke(style: .pen, index: $0, pointCount: 12)
        }

        func compare(
            _ next: [PKStroke],
            appendOnly: Bool = true,
            _ label: String
        ) {
            let fast = IncrementalStrokeConverter()
            let full = IncrementalStrokeConverter()
            _ = fast.changedRecords(from: initial, layerID: { _ in layer })
            _ = full.changedRecords(from: initial, layerID: { _ in layer })
            let fastResult = fast.changedRecords(
                from: next,
                layerID: { _ in layer },
                appendOnly: appendOnly
            )
            let fullResult = full.changedRecords(
                from: next,
                layerID: { _ in layer },
                appendOnly: false
            )
            #expect(fastResult == fullResult, "\(label)")
        }

        // The ids before the suffix differ: a new stroke replaces one in the
        // middle and another is appended.
        var differentPrefix = initial
        differentPrefix[2] = SampleStroke.stroke(style: .pen, index: 2, pointCount: 12)
        differentPrefix.append(SampleStroke.stroke(style: .pen, index: 1, pointCount: 12))
        compare(differentPrefix, "different prefix")

        // A shorter array.
        compare(Array(initial.dropLast()), "shorter")

        // An equal-length array with one changed stroke.
        var equalLength = initial
        equalLength[1].transform = CGAffineTransform(translationX: 7, y: -3)
        compare(equalLength, "equal length")

        // An equal-length array with nothing changed: both paths report nil.
        compare(initial, "unchanged")
    }
}
