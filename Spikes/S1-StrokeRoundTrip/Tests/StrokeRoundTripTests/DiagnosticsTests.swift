import AppKit
import Foundation
import PencilKit
import Testing
@testable import StrokeRoundTrip

/// Attributes any difference: is it our JSON format, or PencilKit's own storage?
@MainActor
@Suite("Diagnostics", .serialized)
struct DiagnosticsTests {

    @Test("JSON encoding is exact")
    func jsonExactness() throws {
        var strokes = 0
        var mismatched = 0
        var firstMismatch = "none"
        for ink in InkStyles.all {
            for stroke in StrokeFactory.strokes(for: ink) {
                strokes += 1
                let record = toRecord(stroke)
                let decoded = try SpikeJSON.decode(SpikeJSON.encode(record))
                if record != decoded {
                    mismatched += 1
                    if firstMismatch == "none" { firstMismatch = "\(ink.rawValue): \(describeRecordDifference(record, decoded))" }
                }
            }
        }
        resultLine("JSON", "all", mismatched == 0 ? "pass" : "fail",
                   ["strokes=\(strokes)", "recordChangedByJSON=\(mismatched)", "detail=\(firstMismatch)"])
        #expect(mismatched == 0, "JSON encode/decode changed the record: \(firstMismatch)")
    }

    /// Replays every point property through PKStrokePoint's own initialiser,
    /// with no JSON involved, and reports per-property drift and convergence.
    @Test("PKStrokePoint replay drift")
    func pointReplay() throws {
        var samples: [(label: String, delta: Double, thirdDelta: Double, original: Double, first: Double, second: Double)] = []
        var pointCount = 0
        var maxGeneration = 0
        var oscillating = 0

        for ink in InkStyles.all {
            for stroke in StrokeFactory.strokes(for: ink) {
                for index in 0..<stroke.path.count {
                    pointCount += 1
                    let p1 = spikePoint(stroke.path[index])
                    let p2 = spikePoint(pkStrokePoint(p1))
                    let p3 = spikePoint(pkStrokePoint(p2))
                    var p4 = p3
                    var generations = 3
                    while generations < 20, pointValues(p4) != pointValues(p3) {
                        p4 = spikePoint(pkStrokePoint(p4))
                        generations += 1
                    }
                    if generations >= 20 { oscillating += 1 }
                    maxGeneration = max(maxGeneration, generations)

                    for (label, value1) in pointFields(p1) {
                        let value2 = pointFields(p2).first { $0.0 == label }!.1
                        let value3 = pointFields(p3).first { $0.0 == label }!.1
                        let delta = value2 - value1
                        let thirdDelta = value3 - value2
                        if delta != 0 || thirdDelta != 0 {
                            samples.append((label, delta, thirdDelta, value1, value2, value3))
                        }
                    }
                }
            }
        }

        var byField: [String: (count: Int, maxDelta: Double, maxThird: Double)] = [:]
        for sample in samples {
            var entry = byField[sample.label] ?? (0, 0, 0)
            entry.count += 1
            entry.maxDelta = max(entry.maxDelta, abs(sample.delta))
            entry.maxThird = max(entry.maxThird, abs(sample.thirdDelta))
            byField[sample.label] = entry
        }
        let summary = byField.keys.sorted().map { key -> String in
            let e = byField[key]!
            return "\(key):n=\(e.count),max=\(String(format: "%.3g", e.maxDelta)),gen2=\(String(format: "%.3g", e.maxThird))"
        }.joined(separator: " ")

        resultLine("POINT", "all", samples.isEmpty ? "pass" : "fail", [
            "points=\(pointCount)",
            "driftingFields=\(byField.keys.sorted().joined(separator: "+"))",
            "maxGenerationsToFixpoint=\(maxGeneration)",
            "oscillating=\(oscillating)",
            "detail=\(summary)"
        ])

        if let azimuth = byField["azimuth"] {
            resultLine("POINT", "azimuth", "fail", [
                "points=\(pointCount)", "drifted=\(azimuth.count)",
                String(format: "maxDelta=%.3g", azimuth.maxDelta),
                String(format: "secondGenerationMaxDelta=%.3g", azimuth.maxThird)
            ])
        }
        if let altitude = byField["altitude"] {
            resultLine("POINT", "altitude", "fail", [
                "points=\(pointCount)", "drifted=\(altitude.count)",
                String(format: "maxDelta=%.3g", altitude.maxDelta),
                String(format: "secondGenerationMaxDelta=%.3g", altitude.maxThird)
            ])
        }

        #expect(oscillating == 0, "point replay oscillates for \(oscillating) points")
    }
}

func pointValues(_ point: SpikePoint) -> [Double] {
    pointFields(point).map(\.1)
}

func pointFields(_ point: SpikePoint) -> [(String, Double)] {
    [
        ("location.x", point.location.x),
        ("location.y", point.location.y),
        ("timeOffset", point.timeOffset),
        ("size.width", point.size.width),
        ("size.height", point.size.height),
        ("opacity", point.opacity),
        ("force", point.force),
        ("azimuth", point.azimuth),
        ("altitude", point.altitude),
        ("secondaryScale", point.secondaryScale),
        ("threshold", point.threshold),
        ("lateralJitter", point.lateralJitter)
    ]
}

@MainActor
@Suite("Drift details", .serialized)
struct DriftDetailTests {

    @Test("non-point fields that drift")
    func nonPointDrift() throws {
        for ink in InkStyles.all {
            for (index, stroke) in StrokeFactory.strokes(for: ink).enumerated() {
                let trip = try roundTrip(stroke)
                let report = compareStrokes(stroke, trip.rebuilt)
                let nonPoint = report.mismatches.filter {
                    !$0.field.hasPrefix("point[") && !$0.field.hasPrefix("derived.")
                }
                if !nonPoint.isEmpty {
                    print("DRIFT|\(ink.rawValue)|\(index)|" + nonPoint.map(\.description).joined(separator: "; "))
                }
            }
        }
    }

    @Test("a second round trip is stable")
    func secondRoundTrip() throws {
        var unstable = 0
        var maxSecondDelta = 0.0
        var checked = 0
        for ink in InkStyles.all {
            for stroke in StrokeFactory.strokes(for: ink) {
                let first = try roundTrip(stroke)
                let second = try roundTrip(first.rebuilt)
                checked += 1
                let report = compareStrokes(first.rebuilt, second.rebuilt)
                maxSecondDelta = max(maxSecondDelta, report.maxDelta)
                if !report.exact || second.record != first.record { unstable += 1 }
            }
        }
        resultLine("SECOND", "all", unstable == 0 ? "pass" : "fail", [
            "strokes=\(checked)",
            "unstableAfterNormalisation=\(unstable)",
            String(format: "maxDelta=%.3g", maxSecondDelta)
        ])

        var stableAt: [Int: Int] = [:]
        var maxIterations = 0
        for ink in InkStyles.all {
            for stroke in StrokeFactory.strokes(for: ink) {
                var current = stroke
                var iterations = 0
                var previousRecord = toRecord(stroke)
                while iterations < 6 {
                    iterations += 1
                    current = try roundTrip(current).rebuilt
                    let record = toRecord(current)
                    if record == previousRecord {
                        stableAt[iterations, default: 0] += 1
                        break
                    }
                    previousRecord = record
                }
                maxIterations = max(maxIterations, iterations)
            }
        }
        resultLine("FIXPOINT", "all", "info", [
            "stableAfterRoundTrips=\(stableAt.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))",
            "maxIterations=\(maxIterations)"
        ])
        #expect(unstable == 0, "\(unstable) of \(checked) strokes still change on a second round trip")
    }

}
