import AppKit
import Foundation
import PencilKit
import Testing
@testable import StrokeRoundTrip

@MainActor
@Suite("Generator coverage")
struct GeneratorTests {

    @Test("synthetic strokes cover the requested ranges")
    func coverage() throws {
        var total = 0
        var allMasks = 0
        var allSeeds = Set<UInt32>()
        for ink in InkStyles.all {
            let strokes = StrokeFactory.strokes(for: ink)
            total += strokes.count
            #expect(strokes.count >= 5, "\(ink.rawValue): fewer than 5 strokes")
            let counts = strokes.map(\.path.count)
            #expect(counts.contains(2), "\(ink.rawValue): no 2-point stroke")
            #expect(counts.contains(200), "\(ink.rawValue): no 200-point stroke")
            #expect(counts.allSatisfy { (2...200).contains($0) }, "\(ink.rawValue): point count out of range: \(counts)")
            let masks = strokes.filter { $0.mask != nil }
            allMasks += masks.count
            #expect(!masks.isEmpty, "\(ink.rawValue): no masked stroke")
            let alphas = strokes.map { $0.ink.color.alphaComponent }
            #expect(alphas.contains { $0 < 1 }, "\(ink.rawValue): no translucent colour")
            #expect(strokes.contains { $0.transform != .identity }, "\(ink.rawValue): all transforms are identity")
            let seeds = strokes.map(\.randomSeed)
            #expect(Set(seeds).count == seeds.count, "\(ink.rawValue): duplicate random seeds")
            allSeeds.formUnion(seeds)
            let ids = strokes.map(\.id)
            #expect(Set(ids).count == ids.count, "\(ink.rawValue): duplicate stroke ids")
            let secondary = strokes.flatMap { stroke in
                (0..<stroke.path.count).map { stroke.path[$0].secondaryScale }
            }
            #expect(secondary.contains { $0 > 0 }, "\(ink.rawValue): secondaryScale never varies")
            let forces = strokes.flatMap { stroke in
                (0..<stroke.path.count).map { stroke.path[$0].force }
            }
            #expect(forces.min() == 0 && forces.max() == 1, "\(ink.rawValue): force does not span 0...1")
        }
        resultLine("G", "all", "pass", ["strokes=\(total)", "masked=\(allMasks)", "distinctSeeds=\(allSeeds.count)"])
        #expect(total == 40, "expected 40 strokes, got \(total)")
    }
}

@MainActor
@Suite("Erased strokes", .serialized)
struct ErasedStrokeTests {

    /// Builds a stroke, erases through it with PencilKit's own eraser and
    /// reports what PencilKit leaves behind. This is the real "partly erased" case.
    @Test("PencilKit-erased strokes round trip")
    func erasedStroke() throws {
        let base = StrokeFactory.stroke(inkType: .marker, index: 2, seed: 0x5EED_1)
        let original = PKStroke(ink: base.ink,
                                path: base.path,
                                transform: base.transform,
                                mask: nil,
                                randomSeed: base.randomSeed,
                                id: base.id,
                                renderGroupID: base.renderGroupID,
                                renderState: nil)
        let drawing = PKDrawing(strokes: [original])

        var eraserPoints: [PKStrokePoint] = []
        for i in 0..<24 {
            let y = 80 + Double(i) * 12
            eraserPoints.append(PKStrokePoint(location: CGPoint(x: 260, y: y),
                                              timeOffset: Double(i) * 0.01,
                                              size: CGSize(width: 40, height: 40),
                                              opacity: 1,
                                              force: 0.5,
                                              azimuth: 0,
                                              altitude: .pi / 2,
                                              secondaryScale: 0,
                                              threshold: 0,
                                              lateralJitter: 0))
        }
        let eraserPath = PKStrokePath(controlPoints: eraserPoints, creationDate: Date())
        let erased = drawing.erasingPath(eraserPath)

        let masked = erased.strokes.filter { $0.mask != nil }
        var rendersEqual = true
        var renderDetail = "not run"
        var fieldDetail = "none"
        var fieldsEqual = true
        var recordEqual = true
        var countsEqual = true
        var pointSetsMatch = true
        var startVertexStable = true
        var maskFieldsExact = true
        var maxGeometryDelta = 0.0
        var elementCounts: [String] = []

        for stroke in masked {
            let trip = try roundTrip(stroke)
            let report = compareStrokes(stroke, trip.rebuilt)
            if !report.toleranceMet {
                fieldsEqual = false
                fieldDetail = report.mismatchDetail
            }
            if !report.mismatches.filter({ $0.field.hasPrefix("mask") }).isEmpty { maskFieldsExact = false }
            if toRecord(trip.rebuilt) != trip.record { recordEqual = false }

            if let a = stroke.mask, let b = trip.rebuilt.mask {
                elementCounts.append("\(a.elementCount)/\(b.elementCount)")
                if a.elementCount != b.elementCount || maskKinds(a) != maskKinds(b) { countsEqual = false }
                let ringA = maskRing(a)
                let ringB = maskRing(b)
                if let (delta, offset) = cyclicMaxDelta(ringA, ringB) {
                    maxGeometryDelta = max(maxGeometryDelta, delta)
                    if offset != 0 { startVertexStable = false }
                    if delta > 0.02 { pointSetsMatch = false }
                } else {
                    pointSetsMatch = false
                }
            }

            let a = PKDrawing(strokes: [stroke])
            let b = PKDrawing(strokes: [trip.rebuilt])
            let rect = a.bounds.insetBy(dx: -4, dy: -4)
            guard rect.width > 1, rect.height > 1 else { continue }
            let imageA = try renderRGBA(a, rect: rect, scale: 2)
            let imageB = try renderRGBA(b, rect: rect, scale: 2)
            let diff = compareBitmaps(imageA, imageB)
            renderDetail = diff.summary
            if !diff.identical { rendersEqual = false }
        }

        resultLine("ERASED", "marker", (!masked.isEmpty && rendersEqual) ? "pass" : "fail", [
            "strokesAfterErase=\(erased.strokes.count)",
            "maskedStrokes=\(masked.count)",
            "maskElementCounts=\(elementCounts.joined(separator: ","))",
            "maskCountsAndKindsEqual=\(countsEqual)",
            "maskShapeMatches=\(pointSetsMatch)",
            String(format: "maxMaskGeometryDelta=%.3g", maxGeometryDelta),
            "maskStartVertexStable=\(startVertexStable)",
            "maskFieldsExact=\(maskFieldsExact)",
            "pointFieldsWithin1e-6=\(fieldsEqual)",
            "recordsEqual=\(recordEqual)",
            "rendersEqual=\(rendersEqual)",
            "fieldDetail=\(fieldDetail)",
            "renderDetail=\(renderDetail)"
        ])

        try #require(!masked.isEmpty,
                      "PencilKit's eraser left no stroke with a mask (strokes after erase: \(erased.strokes.count)); cannot test the partly-erased case this way")
        #expect(rendersEqual, "ERASED: rendering differs after round trip: \(renderDetail)")
        #expect(countsEqual, "ERASED: mask element count or kinds changed")
        #expect(pointSetsMatch, "ERASED: mask geometry changed, max delta \(maxGeometryDelta)")
    }

    /// Hand-built mask via the public initialiser (the synthetic generator's case).
    @Test("mask built by hand survives the round trip")
    func syntheticMask() throws {
        var failures: [String] = []
        var exactMaskMismatches: [String] = []
        var checked = 0
        for ink in InkStyles.all {
            guard let masked = StrokeFactory.strokes(for: ink).first(where: { $0.mask != nil }) else { continue }
            checked += 1
            let trip = try roundTrip(masked)
            let report = compareStrokes(masked, trip.rebuilt)
            let maskMismatches = report.mismatches.filter { $0.field.hasPrefix("mask") }
            if !maskMismatches.isEmpty {
                exactMaskMismatches.append("\(ink.rawValue): \(maskMismatches.prefix(3).map(\.description).joined(separator: "; "))")
            }
            let originalElements = flatten(masked).numbers.filter { $0.label.hasPrefix("mask") }
            let rebuiltElements = flatten(trip.rebuilt).numbers.filter { $0.label.hasPrefix("mask") }
            if originalElements.count != rebuiltElements.count {
                failures.append("\(ink.rawValue): mask element count \(originalElements.count) vs \(rebuiltElements.count)")
            }
        }
        resultLine("MASK", "all", (failures.isEmpty && exactMaskMismatches.isEmpty) ? "pass" : "fail", [
            "stylesWithMask=\(checked)",
            "maskFieldsExact=\(exactMaskMismatches.isEmpty)",
            "maskDetail=\(exactMaskMismatches.isEmpty ? "none" : exactMaskMismatches.joined(separator: "; "))",
            "otherDetail=\(failures.isEmpty ? "none" : failures.joined(separator: "; "))"
        ])
        #expect(checked == InkStyles.all.count, "not every pen style produced a masked stroke")
        #expect(exactMaskMismatches.isEmpty, "MASK: mask fields changed: \(exactMaskMismatches.joined(separator: "; "))")
        #expect(failures.isEmpty, "MASK: \(failures.joined(separator: "; "))")
    }

    /// PencilKit does not store the mask path as given: it normalises it. This is
    /// evidence about the API, not about our record format.
    @Test("PencilKit normalises mask geometry on ingestion")
    func maskNormalisation() throws {
        let circle = StrokeFactory.makeMask(index: 2)          // move + 4 cubic segments + close
        let inputKinds = maskKinds(circle)
        let base = StrokeFactory.stroke(inkType: .pen, index: 1, seed: 0x5EED_1)
        let stroke = PKStroke(ink: base.ink, path: base.path, transform: .identity, mask: circle,
                              randomSeed: base.randomSeed, id: base.id, renderGroupID: nil, renderState: nil)
        let stored = try #require(stroke.mask)
        var kinds: [UInt] = []
        var buffer = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<stored.elementCount {
            let element = buffer.withUnsafeMutableBufferPointer { stored.element(at: index, associatedPoints: $0.baseAddress) }
            kinds.append(element.rawValue)
        }
        let trip = try roundTrip(stroke)
        let rebuilt = try #require(trip.rebuilt.mask)
        let kindsPreserved = (0..<rebuilt.elementCount).allSatisfy { index in
            var b = [NSPoint](repeating: .zero, count: 3)
            let element = b.withUnsafeMutableBufferPointer { rebuilt.element(at: index, associatedPoints: $0.baseAddress) }
            return index < kinds.count && element.rawValue == kinds[index]
        }
        resultLine("MASKSTRUCT", "pen", "info", [
            "inputElements=\(circle.elementCount)",
            "inputKinds=\(inputKinds)",
            "storedCubics=\(kinds.filter { $0 == 2 }.count)",
            "storedElements=\(stored.elementCount)",
            "storedLines=\(kinds.filter { $0 == 1 }.count)",
            "rebuiltElements=\(rebuilt.elementCount)",
            "elementKindsPreserved=\(kindsPreserved)"
        ])
        #expect(stored.elementCount > circle.elementCount,
                "mask was not flattened: input \(circle.elementCount) elements, stored \(stored.elementCount)")
        #expect(kindsPreserved, "record round trip changed the mask element kinds")
    }

    /// Render state is only created by PencilKit for real captured substrokes, so
    /// this checks the record path with a state we construct plus what PencilKit
    /// attaches to a synthetic substroke.
    @Test("renderState survives")
    func renderState() throws {
        let base = StrokeFactory.stroke(inkType: .crayon, index: 1, seed: 0x5EED_1)
        let state = PKStroke.RenderState(grainOffset: CGPoint(x: 12.5, y: -3.25))
        let stroke = PKStroke(ink: base.ink,
                              path: base.path,
                              transform: base.transform,
                              mask: base.mask,
                              randomSeed: base.randomSeed,
                              id: base.id,
                              renderGroupID: base.renderGroupID,
                              renderState: state)

        let trip = try roundTrip(stroke)
        let report = compareStrokes(stroke, trip.rebuilt)
        let statesEqual = stroke.renderState == trip.rebuilt.renderState
        let json = trip.record.renderState?.codableJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"

        let substroke = base.substroke(range: 0...2)
        resultLine("STATE", "crayon", statesEqual ? "pass" : "fail", [
            "constructedStatePreserved=\(statesEqual)",
            "originalHasState=\(stroke.renderState != nil)",
            "rebuiltHasState=\(trip.rebuilt.renderState != nil)",
            "renderStateJSON=\(json)",
            "substrokeHasPencilKitState=\(substroke.renderState != nil)",
            "fieldReport=\(report.summary)",
            "detail=\(report.mismatchDetail)"
        ])
        #expect(statesEqual, "STATE: renderState changed across the round trip")
        #expect(report.mismatches.allSatisfy { !$0.field.hasPrefix("renderState") },
                "STATE: render state fields changed: \(report.mismatchDetail)")
    }
}

@MainActor
@Suite("Colour spaces")
struct ColourTests {

    /// Compares the colour PencilKit actually stores on the stroke with the colour
    /// of the rebuilt stroke. The input colour is reported separately because
    /// PencilKit normalises it before any round trip happens.
    private func check(_ name: String, _ input: NSColor) throws {
        let ink = PKInk(.pen, color: input)
        let base = StrokeFactory.stroke(inkType: .pen, index: 0, seed: 0x5EED_1)
        let stroke = PKStroke(ink: ink,
                              path: base.path,
                              transform: .identity,
                              mask: nil,
                              randomSeed: base.randomSeed,
                              id: base.id,
                              renderGroupID: nil,
                              renderState: nil)
        let record = toRecord(stroke)
        let decoded = try SpikeJSON.decode(SpikeJSON.encode(record))
        let rebuilt = try toStroke(decoded)

        let storedColor = spikeColor(stroke.ink.color)
        let rebuiltColor = spikeColor(rebuilt.ink.color)
        let storedEqualsInput = spikeColor(input).spaceName == storedColor.spaceName
        let recordStable = storedColor == rebuiltColor
        let fields = compareStrokes(stroke, rebuilt)

        var renderDetail = "not run"
        var rendersEqual = false
        let a = PKDrawing(strokes: [stroke])
        let b = PKDrawing(strokes: [rebuilt])
        let rect = a.bounds.insetBy(dx: -4, dy: -4)
        if rect.width > 1, rect.height > 1 {
            let imageA = try renderRGBA(a, rect: rect, scale: 2)
            let imageB = try renderRGBA(b, rect: rect, scale: 2)
            let diff = compareBitmaps(imageA, imageB)
            renderDetail = diff.summary
            rendersEqual = diff.identical
        }

        let outcome = (recordStable && rendersEqual) ? "pass" : "fail"
        resultLine("COLOUR", name, outcome, [
            "inputSpace=\(spikeColor(input).spaceName)",
            "storedSpace=\(storedColor.spaceName)",
            "rebuiltSpace=\(rebuiltColor.spaceName)",
            "storedMatchesInputSpace=\(storedEqualsInput)",
            "recordStable=\(recordStable)",
            "fieldReport=\(fields.summary)",
            "rendersEqual=\(rendersEqual)",
            "renderDetail=\(renderDetail)"
        ])
        #expect(rendersEqual, "COLOUR \(name): rendered pixels differ: \(renderDetail)")
        #expect(recordStable, "COLOUR \(name): colour record changed: \(storedColor.spaceName) vs \(rebuiltColor.spaceName)")
        #expect(fields.mismatches.allSatisfy { !$0.field.hasPrefix("ink.color") },
                "COLOUR \(name): colour fields differ: \(fields.mismatchDetail)")
    }

    @Test("sRGB colour round trips")
    func srgb() throws {
        try check("sRGB", NSColor(srgbRed: 0.13, green: 0.42, blue: 0.87, alpha: 0.9))
    }

    @Test("Display P3 colour round trips")
    func displayP3() throws {
        try check("displayP3", NSColor(displayP3Red: 0.9, green: 0.2, blue: 0.35, alpha: 1))
    }

    @Test("grey colour round trips")
    func grey() throws {
        try check("genericGamma22Gray", NSColor(white: 0.42, alpha: 0.8))
    }

    @Test("extended-range sRGB colour round trips")
    func extendedSRGB() throws {
        try check("extendedSRGB", NSColor(srgbRed: 1.35, green: 0.2, blue: 0.05, alpha: 1))
    }

    @Test("catalog colour round trips")
    func catalog() throws {
        try check("catalog-systemRed", NSColor.systemRed)
    }

    @Test("pattern colour cannot be represented")
    func pattern() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let color = NSColor(patternImage: image)
        let record = spikeColor(color)
        resultLine("COLOUR", "pattern", "fail",
                   ["inputSpace=\(record.spaceName)", "detail=pattern colour has no component representation"])
        #expect(returnsError { _ = try nsColor(record) }, "pattern colour unexpectedly rebuilt")
    }
}

private func maskKinds(_ mask: NSBezierPath) -> [UInt] {
    var buffer = [NSPoint](repeating: .zero, count: 3)
    return (0..<mask.elementCount).map { index in
        buffer.withUnsafeMutableBufferPointer { mask.element(at: index, associatedPoints: $0.baseAddress).rawValue }
    }
}

/// Element points in path order, including duplicates.
func maskPointsInOrder(_ mask: NSBezierPath) -> [CGPoint] {
    var buffer = [NSPoint](repeating: .zero, count: 3)
    var points: [CGPoint] = []
    for index in 0..<mask.elementCount {
        let element = buffer.withUnsafeMutableBufferPointer { mask.element(at: index, associatedPoints: $0.baseAddress) }
        let count: Int = element == .closePath ? 0 : (element == .cubicCurveTo ? 3 : (element == .quadraticCurveTo ? 2 : 1))
        for i in 0..<count { points.append(CGPoint(x: buffer[i].x, y: buffer[i].y)) }
    }
    return points
}

/// A closed ring of vertices: drop the duplicated start/end vertex PencilKit
/// sometimes leaves on a mask polygon.
func maskRing(_ mask: NSBezierPath) -> [CGPoint] {
    var cleaned: [CGPoint] = []
    for point in maskPointsInOrder(mask) {
        if let last = cleaned.last, abs(last.x - point.x) < 1e-9, abs(last.y - point.y) < 1e-9 { continue }
        cleaned.append(point)
    }
    if cleaned.count > 1, let first = cleaned.first, let last = cleaned.last,
       abs(first.x - last.x) < 1e-9, abs(first.y - last.y) < 1e-9 {
        cleaned.removeLast()
    }
    return cleaned
}

/// Best rotation offset and largest coordinate delta between two rings.
func cyclicMaxDelta(_ a: [CGPoint], _ b: [CGPoint]) -> (Double, Int)? {
    guard a.count == b.count, !a.isEmpty else { return nil }
    var best = Double.infinity
    var bestOffset = 0
    for offset in 0..<a.count {
        var maxDelta = 0.0
        for i in 0..<a.count {
            let p = a[i]
            let q = b[(i + offset) % a.count]
            maxDelta = max(maxDelta, abs(p.x - q.x), abs(p.y - q.y))
        }
        if maxDelta < best {
            best = maxDelta
            bestOffset = offset
        }
    }
    return (best, bestOffset)
}

func returnsError(_ body: () throws -> Void) -> Bool {
    do { try body(); return false } catch { return true }
}

