import AppKit
import Foundation
import PencilKit
import Testing
@testable import StrokeRoundTrip

@MainActor
@Suite("Stroke round trip", .serialized)
struct RoundTripTests {

    // MARK: A - field equality

    @Test("A. field equality", arguments: InkStyles.allNames)
    func fieldEquality(_ name: String) throws {
        let ink = try #require(PKInkingTool.InkType(rawValue: name))
        let style = styleName(ink)
        let strokes = StrokeFactory.strokes(for: ink)
        var reports: [ComparisonReport] = []
        for stroke in strokes {
            let trip = try roundTrip(stroke)
            reports.append(compareStrokes(stroke, trip.rebuilt))
        }

        let exactMismatchCount = reports.reduce(0) { $0 + $1.mismatches.count }
        let exactZero = exactMismatchCount == 0
        let worst = reports.max { $0.maxDelta < $1.maxDelta } ?? ComparisonReport()
        let beyond = reports.reduce(0) { $0 + $1.beyondTolerance.count }
        let detail = reports
            .flatMap(\.mismatches)
            .prefix(8)
            .map(\.description)
            .joined(separator: "; ")

        let outcome = reports.allSatisfy { $0.toleranceMet } ? "pass" : "fail"
        resultLine("A", style, outcome, [
            "strokes=\(strokes.count)",
            "fieldsPerStroke=\(reports.first?.numericFields ?? 0)+\(reports.first?.stringFields ?? 0)",
            "exactPass=\(exactZero)",
            "exactMismatches=\(exactMismatchCount)",
            String(format: "maxDelta=%.3g", worst.maxDelta),
            "maxDeltaField=\(worst.maxDeltaField)",
            "beyond1e-6=\(beyond)",
            "detail=\(detail.isEmpty ? "none" : detail)"
        ])

        #expect(reports.allSatisfy { $0.toleranceMet },
                "A: fields differ by more than 1e-6 after the round trip: \(detail)")
        #expect(exactZero,
                "A: round trip is not bit-exact; largest delta \(worst.maxDelta) at \(worst.maxDeltaField). \(detail)")
    }

    // MARK: B - record stability

    @Test("B. record stability", arguments: InkStyles.allNames)
    func recordStability(_ name: String) throws {
        let ink = try #require(PKInkingTool.InkType(rawValue: name))
        let style = styleName(ink)
        var stable = true
        var firstFailure = "none"
        for stroke in StrokeFactory.strokes(for: ink) {
            let trip = try roundTrip(stroke)
            let rebuiltRecord = toRecord(trip.rebuilt)
            if rebuiltRecord != trip.record {
                stable = false
                if firstFailure == "none" {
                    firstFailure = describeRecordDifference(trip.record, rebuiltRecord)
                }
            }
        }
        resultLine("B", style, stable ? "pass" : "fail", ["recordsEqual=\(stable)", "detail=\(firstFailure)"])
        #expect(stable, "B: toRecord(rebuilt) != toRecord(original): \(firstFailure)")
    }

    // MARK: C - rendering

    @Test("C. rendering", arguments: InkStyles.allNames)
    func rendering(_ name: String) throws {
        let ink = try #require(PKInkingTool.InkType(rawValue: name))
        let style = styleName(ink)
        let strokes = StrokeFactory.strokes(for: ink)
        let rebuilt = try strokes.map { try roundTrip($0).rebuilt }

        let originalDrawing = PKDrawing(strokes: strokes)
        let rebuiltDrawing = PKDrawing(strokes: rebuilt)
        let rect = originalDrawing.bounds.insetBy(dx: -8, dy: -8)
        try #require(rect.width > 1 && rect.height > 1,
                     "C: drawing bounds are empty (\(originalDrawing.bounds)); cannot render")

        let originalImage = try renderRGBA(originalDrawing, rect: rect, scale: 2)
        let rebuiltImage = try renderRGBA(rebuiltDrawing, rect: rect, scale: 2)
        try #require(originalImage.nonTransparentPixels > 100,
                     "C could not run: rendered image is blank (\(originalImage.nonTransparentPixels) non-transparent pixels), so equal bitmaps would prove nothing")

        let diff = compareBitmaps(originalImage, rebuiltImage)
        resultLine("C", style, diff.identical ? "pass" : "fail", [
            "identical=\(diff.identical)",
            "pixels=\(originalImage.width)x\(originalImage.height)",
            "nonTransparent=\(diff.originalNonTransparentPixels)/\(diff.rebuiltNonTransparentPixels)",
            "differingPixels=\(diff.differingPixels)",
            "maxChannelDelta=\(diff.maxChannelDelta)",
            "alphaDiffPixels=\(diff.differingAlphaPixels)",
            "rgbDiffPixels=\(diff.differingRGBPixels)",
            "rect=\(fmt(rect))",
            "aggregate=\(diff.summary)"
        ])
        #expect(diff.identical,
                "C: rendered bitmaps differ: \(diff.differingPixels) of \(originalImage.width * originalImage.height) pixels, max channel delta \(diff.maxChannelDelta)")
    }

    // MARK: D - Apple's own serialisation

    @Test("D. dataRepresentation", arguments: InkStyles.allNames)
    func dataRepresentation(_ name: String) throws {
        let ink = try #require(PKInkingTool.InkType(rawValue: name))
        let style = styleName(ink)
        let strokes = StrokeFactory.strokes(for: ink)
        let rebuilt = try strokes.map { try roundTrip($0).rebuilt }

        let originalData = PKDrawing(strokes: strokes).dataRepresentation()
        let rebuiltData = PKDrawing(strokes: rebuilt).dataRepresentation()
        let equal = originalData == rebuiltData
        resultLine("D", style, equal ? "pass" : "fail", [
            "bytesEqual=\(equal)",
            "originalBytes=\(originalData.count)",
            "rebuiltBytes=\(rebuiltData.count)",
            "delta=\(rebuiltData.count - originalData.count)"
        ])
        #expect(equal, "D (supporting): PKDrawing.dataRepresentation differs, \(originalData.count) vs \(rebuiltData.count) bytes")
    }

    // MARK: E - identity

    @Test("E. identity", arguments: InkStyles.allNames)
    func identity(_ name: String) throws {
        let ink = try #require(PKInkingTool.InkType(rawValue: name))
        let style = styleName(ink)
        let strokes = StrokeFactory.strokes(for: ink)
        let rebuilt = try strokes.map { try roundTrip($0).rebuilt }

        let idsPreserved = zip(strokes, rebuilt).allSatisfy { $0.0.id == $0.1.id }
        let pathIDsPreserved = zip(strokes, rebuilt).allSatisfy { $0.0.path.id == $0.1.path.id }
        let originalIDs = Set(strokes.map(\.id))
        let rebuiltIDs = Set(rebuilt.map(\.id))
        let allDistinct = rebuiltIDs.count == rebuilt.count
        let distinctInDrawing = PKDrawing(strokes: rebuilt).strokes.count == rebuilt.count
        let pass = idsPreserved && pathIDsPreserved && allDistinct && distinctInDrawing && originalIDs == rebuiltIDs

        resultLine("E", style, pass ? "pass" : "fail", [
            "n=\(rebuilt.count)",
            "strokeIDsPreserved=\(idsPreserved)",
            "pathIDsPreserved=\(pathIDsPreserved)",
            "distinctAfterRoundTrip=\(allDistinct)",
            "distinctInDrawing=\(distinctInDrawing)",
            "setEqual=\(originalIDs == rebuiltIDs)"
        ])
        #expect(pass, "E: ids not preserved or not distinct (n=\(rebuilt.count), distinct=\(rebuiltIDs.count), strokeIDsPreserved=\(idsPreserved), pathIDsPreserved=\(pathIDsPreserved))")
    }

    // MARK: F - content version

    @Test("F. content version", arguments: InkStyles.allNames)
    func contentVersion(_ name: String) throws {
        let ink = try #require(PKInkingTool.InkType(rawValue: name))
        let style = styleName(ink)
        let strokes = StrokeFactory.strokes(for: ink)
        let trips = try strokes.map { try roundTrip($0) }
        let strokeVersions = trips.map { ($0.original.requiredContentVersion.rawValue, $0.rebuilt.requiredContentVersion.rawValue) }
        let inkVersions = trips.map { ($0.original.ink.requiredContentVersion.rawValue, $0.rebuilt.ink.requiredContentVersion.rawValue) }
        let preserved = strokeVersions.allSatisfy { $0.0 == $0.1 } && inkVersions.allSatisfy { $0.0 == $0.1 }

        resultLine("F", style, preserved ? "pass" : "fail", [
            "strokeVersion=\(strokeVersions.map(\.0).min() ?? -1)...\(strokeVersions.map(\.0).max() ?? -1)",
            "inkVersion=\(inkVersions.map(\.0).min() ?? -1)...\(inkVersions.map(\.0).max() ?? -1)",
            "preserved=\(preserved)",
            "inkTypeVersion=\(ink.requiredContentVersion.rawValue)",
            "drawingVersion=\(PKDrawing(strokes: strokes).requiredContentVersion.rawValue)"
        ])
        #expect(preserved, "F: requiredContentVersion changed across the round trip")
    }
}

func fmt(_ rect: CGRect) -> String {
    String(format: "%.1f,%.1f %.1fx%.1f", rect.minX, rect.minY, rect.width, rect.height)
}

/// Human-readable difference between two records, used by check B.
func describeRecordDifference(_ a: SpikeStroke, _ b: SpikeStroke) -> String {
    if a.strokeID != b.strokeID { return "strokeID" }
    if a.ink != b.ink { return "ink" }
    if a.transform != b.transform { return "transform" }
    if a.randomSeed != b.randomSeed { return "randomSeed" }
    if a.renderGroupID != b.renderGroupID { return "renderGroupID" }
    if a.renderState != b.renderState { return "renderState" }
    if a.requiredContentVersion != b.requiredContentVersion { return "requiredContentVersion" }
    if a.path.id != b.path.id { return "path.id" }
    if a.path.creationDate != b.path.creationDate { return "path.creationDate" }
    if a.path.controlPoints.count != b.path.controlPoints.count { return "path.controlPoints.count" }
    for (index, pair) in zip(a.path.controlPoints, b.path.controlPoints).enumerated() where pair.0 != pair.1 {
        return "path.controlPoints[\(index)]"
    }
    if a.mask != b.mask { return "mask" }
    return "unknown"
}
