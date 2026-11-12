import AppKit
import Foundation
import PencilKit
import Testing
@testable import StrokeRoundTrip

// Shared helpers for the experiment.

struct RoundTrip {
    let record: SpikeStroke
    let decoded: SpikeStroke
    let rebuilt: PKStroke
    let original: PKStroke
}

func roundTrip(_ stroke: PKStroke) throws -> RoundTrip {
    let record = toRecord(stroke)
    let data = try SpikeJSON.encode(record)
    let decoded = try SpikeJSON.decode(data)
    let rebuilt = try toStroke(decoded)
    return RoundTrip(record: record, decoded: decoded, rebuilt: rebuilt, original: stroke)
}

/// One line per measured result, parsed after the run to build RESULTS.md.
func resultLine(_ kind: String, _ style: String, _ outcome: String, _ measurements: [String]) {
    print("RESULT|\(kind)|\(style)|\(outcome)|" + measurements.joined(separator: "|"))
}

func styleName(_ ink: PKInkingTool.InkType) -> String { ink.rawValue }
