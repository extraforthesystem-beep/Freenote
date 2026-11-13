import CoreGraphics
import Foundation
@testable import InkKit
import NoteCore
import PencilKit
import Testing

// MARK: - Shared synthetic strokes

private func madeStroke(
    _ locations: [CGPoint],
    width: CGFloat = 3,
    ink: PKInk = PKInk(.pen, color: .black)
) -> PKStroke {
    let points = locations.enumerated().map { index, location in
        PKStrokePoint(
            location: location,
            timeOffset: Double(index) / 240,
            size: CGSize(width: width + CGFloat(index % 3), height: width),
            opacity: 1,
            force: 0.5,
            azimuth: 0.2,
            altitude: 1.0
        )
    }
    let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 500))
    return PKStroke(ink: ink, path: path, transform: .identity, mask: nil)
}

/// Points along `vertices`, about every 2 pt, with a deterministic wobble.
private func drawnPoints(_ vertices: [CGPoint], noise: CGFloat = 1.2) -> [CGPoint] {
    var points: [CGPoint] = []
    var index = 0
    for segment in 1..<max(vertices.count, 1) {
        let a = vertices[segment - 1], b = vertices[segment]
        let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 2))
        for step in 0..<steps {
            let t = CGFloat(step) / CGFloat(steps)
            points.append(CGPoint(
                x: a.x + (b.x - a.x) * t + sin(CGFloat(index) * 1.7) * noise,
                y: a.y + (b.y - a.y) * t + cos(CGFloat(index) * 2.3) * noise
            ))
            index += 1
        }
    }
    if let last = vertices.last { points.append(last) }
    return points
}

private func closed(_ vertices: [CGPoint]) -> [CGPoint] {
    guard let first = vertices.first else { return vertices }
    return vertices + [first]
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

// MARK: - Smoothing

@Suite("Stroke smoothing")
struct StrokeSmoothingTests {
    /// A line with a 1.5 pt zigzag on it, like a shaky hand.
    private func shakyLine() -> PKStroke {
        let locations = (0...200).map { index -> CGPoint in
            CGPoint(x: CGFloat(index), y: 100 + (index % 2 == 0 ? 1.5 : -1.5))
        }
        return madeStroke(locations)
    }

    private func deviationFromChord(_ stroke: PKStroke) -> CGFloat {
        let points = (0..<stroke.path.count).map { stroke.path[$0].location }
        guard let first = points.first, let last = points.last else { return 0 }
        return points.map { ShapeRecognizer.distance($0, toSegment: first, last) }.max() ?? 0
    }

    @Test func smoothingLeavesTheEndsAndTheWidthsAlone() throws {
        let original = shakyLine()
        let smoothed = try #require(StrokeSmoothing.smoothed(original, strength: 80))
        #expect(smoothed.id == original.id)
        #expect(smoothed.path.count == original.path.count)
        #expect(smoothed.path[0].location == original.path[0].location)
        #expect(smoothed.path[original.path.count - 1].location == original.path[original.path.count - 1].location)
        for index in [0, 57, 200] {
            #expect(smoothed.path[index].size == original.path[index].size)
            #expect(smoothed.path[index].force == original.path[index].force)
            #expect(smoothed.path[index].opacity == original.path[index].opacity)
        }
    }

    @Test func smoothingTakesTheZigzagOut() throws {
        let original = shakyLine()
        let smoothed = try #require(StrokeSmoothing.smoothed(original, strength: 100))
        #expect(deviationFromChord(smoothed) < deviationFromChord(original) * 0.7)
        #expect(deviationFromChord(original) <= 3.001)
    }

    @Test func zeroStrengthChangesNothing() {
        #expect(StrokeSmoothing.smoothed(shakyLine(), strength: 0) == nil)
        #expect(StrokeSmoothing.smoothed(madeStroke([.zero, CGPoint(x: 10, y: 0)]), strength: 100) == nil)
    }
}

// MARK: - Dashes

@Suite("Dashed strokes")
struct StrokeDashTests {
    private func line(length: CGFloat = 200) -> PKStroke {
        madeStroke((0...Int(length)).map { CGPoint(x: CGFloat($0), y: 100) })
    }

    @Test func dashedStrokeCarriesAClipOfManyCaps() throws {
        let original = line()
        let masked = try #require(StrokeDash.masked(original, style: .dashed))
        let mask = try #require(masked.mask)
        #expect(masked.id == original.id)
        #expect(!mask.isEmpty)
        #expect(mask.bounds.width > 180)
        #expect(abs(mask.bounds.height - 8) < 10)
    }

    @Test func dottedHasMoreCapsThanDashed() throws {
        func caps(_ style: PenLineStyle) throws -> Int {
            let record = StrokeCodec.record(
                from: try #require(StrokeDash.masked(line(), style: style)),
                layerID: UUID()
            )
            return (record.mask ?? []).filter {
                if case .move = $0 { return true }
                return false
            }.count
        }
        let dashed = try caps(.dashed)
        let dotted = try caps(.dotted)
        #expect(dashed > 5)
        #expect(dotted > dashed)
    }

    @Test func solidLeavesTheStrokeAlone() {
        #expect(StrokeDash.masked(line(), style: .solid) == nil)
    }

    @Test func dashClipSurvivesTheRecordRoundTrip() throws {
        let masked = try #require(StrokeDash.masked(line(), style: .dashed))
        let record = StrokeCodec.record(from: masked, layerID: UUID())
        #expect(record.mask != nil)
        #expect((record.mask?.count ?? 0) > 20)
        let rebuilt = try StrokeCodec.stroke(from: record)
        #expect(rebuilt.mask != nil)
        #expect(rebuilt.id == masked.id)
    }

    @Test func aDashedStrokeIsFlattenedInAnEditablePDF() throws {
        let masked = try #require(StrokeDash.masked(line(), style: .dashed))
        let record = StrokeCodec.record(from: masked, layerID: UUID())
        #expect(VectorPDFAnnotations.isFlattened(record))
        #expect(!VectorPDFAnnotations.isTranslucent(record))
    }

    @Test func dashedInkLeavesGapsInTheRenderedPage() throws {
        // Red ink: PencilKit renders black as white in the test process's dark
        // appearance, which is invisible on white paper.
        let ink = PKInk(.pen, color: InkPlatformColor(srgbRed: 0.85, green: 0.05, blue: 0.05, alpha: 1))
        let original = madeStroke(
            (0...200).map { CGPoint(x: CGFloat($0), y: 100) },
            width: 16,
            ink: ink
        )
        let solid = StrokeCodec.record(from: original, layerID: UUID())
        let dashed = StrokeCodec.record(
            from: try #require(StrokeDash.masked(original, style: .dashed)),
            layerID: UUID()
        )
        let size = CGSize(width: 220, height: 140)
        let solidInk = try inkPixels(of: solid, size: size)
        let dashedInk = try inkPixels(of: dashed, size: size)
        #expect(solidInk > 500)
        #expect(Double(dashedInk) < Double(solidInk) * 0.85)
        #expect(Double(dashedInk) > Double(solidInk) * 0.2)
    }

    /// Pixels of red ink a record paints on a white page.
    private func inkPixels(of record: StrokeRecord, size: CGSize) throws -> Int {
        let image = try #require(PageRenderer.image(
            strokes: [record],
            pageSize: size,
            template: .blank,
            scale: 1
        ))
        let source = try #require(PageRenderer.cgImage(of: image))
        let width = Int(size.width), height = Int(size.height)
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(source, in: CGRect(origin: .zero, size: size))
        let data = try #require(context.data)
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return (0..<(width * height)).reduce(0) { count, pixel in
            bytes[pixel * 4 + 1] < 200 ? count + 1 : count
        }
    }

    @Test func walkMeasuresAndInterpolatesAlongAPolyline() {
        let walk = PolylineWalk([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
        #expect(walk.length == 20)
        #expect(walk.point(at: 5) == CGPoint(x: 5, y: 0))
        #expect(walk.point(at: 15) == CGPoint(x: 10, y: 5))
        #expect(walk.point(at: -3) == CGPoint(x: 0, y: 0))
        #expect(walk.point(at: 40) == CGPoint(x: 10, y: 10))
    }
}

// MARK: - Scratch out

@Suite("Scratch-out erase")
struct ScratchOutTests {
    private func backAndForth() -> [CGPoint] {
        var points: [CGPoint] = []
        for pass in 0..<5 {
            let direction: CGFloat = pass % 2 == 0 ? 1 : -1
            for step in 0..<20 {
                points.append(CGPoint(
                    x: 100 + direction * CGFloat(step) * 2 + sin(CGFloat(step) * 1.3),
                    y: 100 + CGFloat(pass) * 4 + sin(CGFloat(step) * 2.1) * 2
                ))
            }
        }
        return points
    }

    @Test func backAndForthScribbleIsRecognised() throws {
        let area = try #require(ScratchOut.scribbledArea(backAndForth()))
        #expect(area.width > 30)
        #expect(area.height > 10)
    }

    @Test func writingAndLinesAreNotScribbles() {
        let underline = (0...200).map { CGPoint(x: CGFloat($0), y: 100) }
        #expect(ScratchOut.scribbledArea(underline) == nil)

        // A cursive "e"-like loop.
        let writing = (0..<120).map { index -> CGPoint in
            let t = CGFloat(index) / 119 * 3 * .pi
            return CGPoint(x: t * 12 + cos(t * 2) * 10, y: 50 + sin(t * 2) * 12)
        }
        #expect(ScratchOut.scribbledArea(writing) == nil)
        #expect(ScratchOut.scribbledArea([CGPoint(x: 5, y: 5), CGPoint(x: 6, y: 6)]) == nil)
    }
}

// MARK: - Eraser filter

@Suite("Eraser filter")
struct EraserFilterTests {
    @Test func filterIsAnAllowList() {
        #expect(EraserFilter.all.allows(.pen))
        #expect(EraserFilter.all.allows(.shape))
        #expect(!EraserFilter.highlighter.allows(.pen))
        #expect(!EraserFilter.none.allows(.highlighter))
    }

    @Test func aSnappedLineIsShapeInk() throws {
        let freehand = madeStroke((0...100).map { CGPoint(x: CGFloat($0) * 2, y: 50 + sin(CGFloat($0)) * 0.6) })
        let shape = try #require(ShapeStrokeBuilder.shapeStroke(replacing: freehand))
        #expect(StrokeClassifier.kind(of: shape) == .shape)
    }

    @Test func writingAndHighlightsKeepTheirKind() {
        let writing = madeStroke((0..<120).map { index -> CGPoint in
            let t = CGFloat(index) / 119 * 3 * .pi
            return CGPoint(x: t * 10 + cos(t * 2) * 9, y: 50 + sin(t * 2) * 11)
        })
        #expect(StrokeClassifier.kind(of: writing) == .pen)

        let highlight = madeStroke(
            (0...100).map { CGPoint(x: CGFloat($0), y: 100) },
            width: 24,
            ink: PKInk(.marker, color: InkPlatformColor(srgbRed: 1, green: 0.9, blue: 0.2, alpha: 0.35))
        )
        #expect(StrokeClassifier.kind(of: highlight) == .highlighter)
    }
}

// MARK: - Straight highlighter and presets

@Suite("Highlighter straight lines")
struct HighlighterStraightTests {
    @Test func curvedHighlightBecomesAStraightStroke() throws {
        let curve = madeStroke((0...100).map { index in
            CGPoint(x: CGFloat(index), y: 100 + sin(CGFloat(index) / 10) * 40)
        })
        let straight = try #require(ShapeStrokeBuilder.straightened(curve))
        #expect(straight.id == curve.id)
        #expect(straight.ink.inkType == curve.ink.inkType)
        #expect(straight.path.first?.location == curve.path.first?.location)
        #expect(straight.path.last?.location == curve.path.last?.location)

        let start = try #require(curve.path.first?.location)
        let end = try #require(curve.path.last?.location)
        let length = hypot(end.x - start.x, end.y - start.y)
        for index in 0..<straight.path.count {
            let point = straight.path[index].location
            let offLine = abs((end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x))
            #expect(offLine / length < 0.01)
        }
    }

    @Test func aShortTapStaysAsDrawn() {
        let dot = madeStroke([CGPoint(x: 10, y: 10), CGPoint(x: 14, y: 12)])
        #expect(ShapeStrokeBuilder.straightened(dot) == nil)
    }
}

@Suite("Ink tool presets")
struct InkToolPresetTests {
    @Test func aPresetWithoutALineStyleDecodesAsSolid() throws {
        let json = """
        {"style":"pen","color":{"r":0,"g":0,"b":0,"a":1},"width":2}
        """
        let tool = try JSONDecoder().decode(InkTool.self, from: Data(json.utf8))
        #expect(tool.lineStyle == .solid)
    }

    @Test func lineStyleRoundTrips() throws {
        for style in PenLineStyle.allCases {
            let tool = InkTool(.pen, lineStyle: style)
            let decoded = try JSONDecoder().decode(
                InkTool.self,
                from: JSONEncoder().encode(tool)
            )
            #expect(decoded == tool)
            #expect(decoded.lineStyle == style)
        }
    }

    @Test func aHighlighterIsAlwaysSolid() {
        let tool = InkTool(.marker, isHighlighter: true, lineStyle: .dashed)
        #expect(tool.lineStyle == .solid)
        #expect(PenLineStyle.allCases.map(\.rawValue) == ["solid", "dashed", "dotted"])
    }
}

// MARK: - New snap targets
@Suite("New hold-to-shape targets")
struct ExtendedShapeRecognizerTests {
    private let recognizer = ShapeRecognizer()

    @Test func arrow() throws {
        let vertices = [CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100),
                        CGPoint(x: 168, y: 78), CGPoint(x: 170, y: 122)]
        guard case let .arrow(tail, tip)? = recognizer.recognize(drawnPoints(vertices)) else {
            Issue.record("expected an arrow"); return
        }
        #expect(distance(tail, vertices[0]) < 5)
        #expect(distance(tip, vertices[1]) < 5)
        #expect(abs(tip.y - tail.y) < 0.001, "a horizontal arrow snaps flat")
    }

    @Test func pentagon() throws {
        let center = CGPoint(x: 200, y: 200)
        let corners = (0..<5).map { index -> CGPoint in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / 5
            return CGPoint(x: center.x + cos(angle) * 100, y: center.y + sin(angle) * 100)
        }
        guard case let .pentagon(loop)? = recognizer.recognize(drawnPoints(closed(corners))) else {
            Issue.record("expected a pentagon"); return
        }
        #expect(loop.count == 5)
        for corner in corners {
            #expect(loop.contains { distance($0, corner) < 12 })
        }
    }

    @Test func hexagon() throws {
        let center = CGPoint(x: 200, y: 200)
        let corners = (0..<6).map { index -> CGPoint in
            let angle = CGFloat(index) * 2 * .pi / 6
            return CGPoint(x: center.x + cos(angle) * 100, y: center.y + sin(angle) * 100)
        }
        guard case let .hexagon(loop)? = recognizer.recognize(drawnPoints(closed(corners))) else {
            Issue.record("expected a hexagon"); return
        }
        #expect(loop.count == 6)
        for corner in corners {
            #expect(loop.contains { distance($0, corner) < 12 })
        }
    }

    @Test func rhombus() throws {
        let corners = [CGPoint(x: 200, y: 80), CGPoint(x: 260, y: 200),
                       CGPoint(x: 200, y: 320), CGPoint(x: 140, y: 200)]
        guard case let .rhombus(loop)? = recognizer.recognize(drawnPoints(closed(corners))) else {
            Issue.record("expected a rhombus"); return
        }
        #expect(loop.count == 4)
        let sides = (0..<4).map { distance(loop[$0], loop[($0 + 1) % 4]) }
        #expect((sides.max() ?? 0) - (sides.min() ?? 0) < 1)
        // The diagonals meet at a right angle.
        let first = CGPoint(x: loop[2].x - loop[0].x, y: loop[2].y - loop[0].y)
        let second = CGPoint(x: loop[3].x - loop[1].x, y: loop[3].y - loop[1].y)
        #expect(abs(first.x * second.x + first.y * second.y) < 1)
    }

    @Test func resampledNewShapesAreClean() {
        let arrow = ShapeRecognizer.points(for: .arrow(tail: .zero, tip: CGPoint(x: 100, y: 0)), spacing: 2)
        #expect(arrow.first == .zero)
        #expect(arrow.last != .zero)
        #expect(arrow.count > 20)

        let pentagon = ShapeRecognizer.points(
            for: .pentagon([CGPoint(x: 100, y: 0), CGPoint(x: 120, y: 80), CGPoint(x: 50, y: 130),
                            CGPoint(x: -20, y: 80), CGPoint(x: 0, y: 0)]),
            spacing: 2
        )
        #expect(pentagon.first == pentagon.last)
    }
}
