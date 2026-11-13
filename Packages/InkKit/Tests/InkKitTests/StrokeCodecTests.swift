import CoreGraphics
import Foundation
import InkKit
import NoteCore
import PencilKit
import Testing

// Tolerances from S1's measurements (Spikes/S1-StrokeRoundTrip/RESULTS.md):
// PencilKit re-stores these four fields in a compressed form, so they drift by
// whole storage steps on the way back in. Everything else must be exact.
private let azimuthTolerance = 1e-4
private let altitudeTolerance = 1e-4
private let sizeHeightTolerance = 0.06
private let maskVertexTolerance = 0.02

@Suite("Stroke codec")
struct StrokeCodecTests {
    static let layerID = UUID()

    @Test("Every pen style round trips within S1's measured bounds", arguments: PenStyle.allCases)
    func roundTrip(style: PenStyle) throws {
        for index in 0..<4 {
            let original = SampleStroke.stroke(style: style, index: index)
            let first = StrokeCodec.record(from: original, layerID: Self.layerID)
            let rebuilt = try StrokeCodec.stroke(from: first)
            let second = StrokeCodec.record(from: rebuilt, layerID: Self.layerID)

            // Exact by S1: identity, tool and layer.
            #expect(second.id == first.id)
            #expect(first.id == original.id)
            #expect(second.layerID == Self.layerID)
            #expect(second.tool == first.tool)
            #expect(first.tool.inkType == style.inkType.rawValue)
            #expect(first.tool.engine == StrokeCodec.engine)
            #expect(rebuilt.ink.inkType == style.inkType)
            #expect(RGBAColor(srgb: rebuilt.ink.color) == first.tool.color)

            // Exact by S1: the path and the page-level fields.
            #expect(first.pathID == original.path.id)
            #expect(second.pathID == first.pathID)
            #expect(first.createdAt == original.path.creationDate)
            #expect(second.createdAt == first.createdAt)
            #expect(first.transform == [
                Double(original.transform.a), Double(original.transform.b),
                Double(original.transform.c), Double(original.transform.d),
                Double(original.transform.tx), Double(original.transform.ty),
            ])
            #expect(second.transform == first.transform)
            #expect(rebuilt.transform == original.transform)
            #expect(first.randomSeed == original.randomSeed)
            #expect(second.randomSeed == first.randomSeed)
            #expect(first.renderGroupID == original.renderGroupID)
            #expect(second.renderGroupID == first.renderGroupID)
            #expect(first.grainOffset == second.grainOffset)

            // Point counts and every point field.
            #expect(first.points.count == original.path.count)
            #expect(second.points.count == first.points.count)

            for (a, b) in zip(first.points, second.points) {
                #expect(a.x == b.x)
                #expect(a.y == b.y)
                #expect(a.timeOffset == b.timeOffset)
                #expect(a.width == b.width)
                #expect(a.opacity == b.opacity)
                #expect(a.force == b.force)
                #expect(a.secondaryScale == b.secondaryScale)
                #expect(a.threshold == b.threshold)
                #expect(a.lateralJitter == b.lateralJitter)
                // Drifted fields, inside S1's bounds rather than exact.
                #expect(abs(a.azimuth - b.azimuth) <= azimuthTolerance)
                #expect(abs(a.altitude - b.altitude) <= altitudeTolerance)
                #expect(abs(a.height - b.height) <= sizeHeightTolerance)
            }

            // The mask is a polyline after PencilKit's own normalisation, and it
            // may start at a different vertex on re-ingestion.
            let firstVertices = SampleStroke.vertices(first.mask)
            let secondVertices = SampleStroke.vertices(second.mask)
            #expect((first.mask == nil) == (second.mask == nil))
            #expect(abs(firstVertices.count - secondVertices.count) <= 2)
            for vertex in secondVertices {
                let nearest = firstVertices
                    .map { hypot($0.x - vertex.x, $0.y - vertex.y) }
                    .min() ?? .infinity
                #expect(nearest <= maskVertexTolerance)
            }

            // Sanity: the samples really did carry the fields under test.
            if index > 0 {
                #expect(first.mask != nil)
                #expect(!firstVertices.isEmpty)
            }
            if index == 1 {
                #expect(first.grainOffset == StrokeRecord.GrainOffset(x: 1.25, y: -0.5))
                #expect(first.points.contains { $0.lateralJitter > 0 })
            }
            if index == 2 {
                #expect(first.renderGroupID != nil)
                #expect(first.points.contains { $0.threshold > 0 })
            }
        }
    }

    @Test("A 2,000-point stroke converts and rebuilds")
    func longStroke() throws {
        let original = SampleStroke.stroke(style: .pen, index: 0, pointCount: 2_000)
        let record = StrokeCodec.record(from: original, layerID: Self.layerID)
        #expect(record.points.count == 2_000)

        let rebuilt = try StrokeCodec.stroke(from: record)
        #expect(rebuilt.path.count == 2_000)
        #expect(rebuilt.id == original.id)
        #expect(rebuilt.path.id == original.path.id)

        let second = StrokeCodec.record(from: rebuilt, layerID: Self.layerID)
        #expect(second.points.count == 2_000)
        if let a = second.points.first, let b = record.points.first {
            #expect(a.x == b.x)
            #expect(a.y == b.y)
            #expect(a.timeOffset == b.timeOffset)
            #expect(a.width == b.width)
        }
        if let a = second.points.last, let b = record.points.last {
            #expect(a.x == b.x)
            #expect(a.y == b.y)
            #expect(abs(a.height - b.height) <= sizeHeightTolerance)
        }
    }

    @Test("drawing(from:) keeps every stroke id")
    func drawingKeepsIDs() {
        let records = PenStyle.allCases.enumerated().map { index, style in
            StrokeCodec.record(from: SampleStroke.stroke(style: style, index: index % 3), layerID: Self.layerID)
        }
        let drawing = StrokeCodec.drawing(from: records)
        #expect(drawing.strokes.count == records.count)
        #expect(drawing.strokes.map(\.id) == records.map(\.id))
        #expect(drawing.strokes.map(\.path.id) == records.compactMap(\.pathID))
    }

    @Test("An unknown ink string throws unsupportedInkType")
    func unknownInk() throws {
        var record = StrokeCodec.record(
            from: SampleStroke.stroke(style: .pen, index: 0),
            layerID: Self.layerID
        )
        record.tool.inkType = "com.apple.ink.noSuchInk"
        #expect(throws: StrokeCodecError.unsupportedInkType("com.apple.ink.noSuchInk")) {
            try StrokeCodec.stroke(from: record)
        }
    }

    @Test("A page with mixed records skips only the unsupported one")
    func mixedPage() throws {
        let good = StrokeCodec.record(
            from: SampleStroke.stroke(style: .marker, index: 1),
            layerID: Self.layerID
        )

        var badInk = good
        badInk.id = UUID()
        badInk.tool.inkType = "com.apple.ink.noSuchInk"

        var noPoints = good
        noPoints.id = UUID()
        noPoints.points = []

        var badTransform = good
        badTransform.id = UUID()
        badTransform.transform = [1, 0, 0, 1, 0]

        let drawing = StrokeCodec.drawing(from: [good, badInk, noPoints, badTransform])
        #expect(drawing.strokes.map(\.id) == [good.id])
        #expect(!drawing.strokes.isEmpty)
    }

    @Test("A malformed transform and an empty path are rejected")
    func malformedRecord() throws {
        var record = StrokeCodec.record(
            from: SampleStroke.stroke(style: .pencil, index: 0),
            layerID: Self.layerID
        )
        record.transform = [1, 0, 0, 1, 0]
        #expect(throws: StrokeCodecError.invalidTransform) {
            try StrokeCodec.stroke(from: record)
        }

        record.transform = StrokeRecord.identityTransform
        record.points = []
        #expect(throws: StrokeCodecError.emptyPoints) {
            try StrokeCodec.stroke(from: record)
        }
    }

    @Test("A quadratic-only mask is dropped instead of trapping")
    func quadraticMaskIsDropped() throws {
        var record = StrokeCodec.record(
            from: SampleStroke.stroke(style: .crayon, index: 0),
            layerID: Self.layerID
        )
        #expect(record.mask == nil)

        record.mask = [
            .move(x: 10, y: 10),
            .quad(cx: 40, cy: 90, x: 70, y: 10),
            .quad(cx: 100, cy: -70, x: 130, y: 10),
            .close,
        ]
        let rebuilt = try StrokeCodec.stroke(from: record)
        #expect(rebuilt.mask == nil)

        record.mask = []
        #expect(try StrokeCodec.stroke(from: record).mask == nil)
    }

    @Test("PenStyle raw values stay stable")
    func penStyleRawValues() {
        #expect(PenStyle.allCases.map(\.rawValue) == [
            "pen", "pencil", "marker", "monoline",
            "fountainPen", "watercolor", "crayon", "reed",
        ])
        #expect(PenStyle.pen.inkType.rawValue == "com.apple.ink.pen")
        #expect(PenStyle.reed.inkType.rawValue == "com.apple.ink.reedcalligraphy")
        #expect(PenStyle(inkType: .watercolor) == .watercolor)
    }

    @Test("sRGB conversion is exact and keeps translucency")
    func colourConversion() {
        let opaque = RGBAColor(r: 0.1, g: 0.2, b: 0.3, a: 1)
        #expect(RGBAColor(srgb: opaque.inkColor) == opaque)

        let translucent = RGBAColor(r: 0.9, g: 0.1, b: 0.1, a: 0.35)
        let roundTripped = RGBAColor(srgb: translucent.inkColor)
        #expect(roundTripped?.a == 0.35)
    }
}

@Suite("Page renderer")
struct PageRendererTests {
    @Test("Renders paper, template and ink at the requested scale")
    func rendersPage() throws {
        let pageSize = CGSize(width: 200, height: 300)
        let template = PageTemplate(
            kind: "grid",
            spacing: 20,
            lineColor: RGBAColor(r: 0.8, g: 0.8, b: 0.9),
            paperColor: RGBAColor(r: 1, g: 0.99, b: 0.95)
        )
        let record = StrokeCodec.record(
            from: SampleStroke.stroke(style: .pen, index: 1),
            layerID: UUID()
        )

        let image = try #require(PageRenderer.image(
            strokes: [record],
            pageSize: pageSize,
            template: template,
            scale: 2
        ))
        #if os(iOS)
        #expect(image.size == pageSize)
        #expect(image.scale == 2)
        #expect(image.cgImage?.width == 400)
        #expect(image.cgImage?.height == 600)
        #else
        #expect(image.size == pageSize)
        #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width == 400)
        #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height == 600)
        #endif
    }
}
