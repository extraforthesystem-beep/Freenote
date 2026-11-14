import Foundation
import NoteCore
import Testing
@testable import SearchKit

private func hashFixture() -> Page {
    let layerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    let tool = StrokeTool(
        engine: "metal",
        inkType: "pen",
        color: RGBAColor(r: 0.2, g: 0.3, b: 0.4, a: 0.9),
        width: 3,
        isHighlighter: false
    )
    let points = [
        StrokePoint(
            x: 10,
            y: 20,
            timeOffset: 0.01,
            width: 2,
            height: 2,
            opacity: 1,
            force: 0.5,
            azimuth: 0.1,
            altitude: 1.4,
            secondaryScale: 1,
            threshold: 0.2,
            lateralJitter: 0.03
        ),
        StrokePoint(
            x: 11,
            y: 21,
            timeOffset: 0.02,
            width: 2,
            height: 2,
            opacity: 1,
            force: 0.6,
            azimuth: 0.2,
            altitude: 1.3,
            secondaryScale: 1,
            threshold: 0.2,
            lateralJitter: 0.03
        )
    ]
    func stroke(
        index: Int,
        id: UUID
    ) -> StrokeRecord {
        StrokeRecord(
            id: id,
            layerID: layerID,
            tool: tool,
            createdAt: Date(timeIntervalSince1970: 1_234),
            transform: [1, 0, 0, 1, 12, 34],
            randomSeed: 42,
            mask: [.move(x: 0, y: 0), .line(x: 1, y: 1)],
            renderGroupID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
            pathID: UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
            grainOffset: StrokeRecord.GrainOffset(x: 0.1, y: 0.2),
            points: points.map { point in
                var copy = point
                copy.x += Double(index)
                return copy
            }
        )
    }
    var page = Page(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
        width: 612,
        height: 792,
        template: .blank
    )
    page.strokes = [
        stroke(index: 0, id: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID()),
        stroke(index: 1, id: UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID())
    ]
    page.deletedStrokeIDs = [
        UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID(),
        UUID(uuidString: "88888888-8888-8888-8888-888888888888") ?? UUID()
    ]
    page.elements = [
        PageElement(
            id: UUID(),
            layerID: layerID,
            frame: ElementFrame(x: 20, y: 20, width: 200, height: 60),
            zIndex: 0,
            updatedAt: Date(timeIntervalSince1970: 0),
            content: .text("Meeting notes", fontName: "System", fontSize: 14, color: .black)
        ),
        PageElement(
            id: UUID(),
            layerID: layerID,
            frame: ElementFrame(x: 0, y: 0, width: 612, height: 792),
            zIndex: 1,
            updatedAt: Date(timeIntervalSince1970: 0),
            content: .pdfPage(assetName: "handout.pdf", pageIndex: 1)
        )
    ]
    return page
}

private func expectHashChanges(_ name: String, mutate: (inout Page) -> Void) {
    var page = hashFixture()
    mutate(&page)
    #expect(
        SearchIndex.contentHash(of: page) != SearchIndex.contentHash(of: hashFixture()),
        Comment(rawValue: name)
    )
}

@Test func contentHashIsStableAndIgnoresDeletedIDOrder() {
    let page = hashFixture()
    #expect(SearchIndex.contentHash(of: page) == SearchIndex.contentHash(of: page))

    var reordered = page
    reordered.deletedStrokeIDs = Set(page.deletedStrokeIDs.reversed())
    #expect(SearchIndex.contentHash(of: reordered) == SearchIndex.contentHash(of: page))
}

@Test func contentHashChangesWithStrokeIdentity() {
    expectHashChanges("stroke id") { $0.strokes[0].id = UUID() }
    expectHashChanges("layer id") { $0.strokes[0].layerID = UUID() }
    expectHashChanges("stroke createdAt") {
        $0.strokes[0].createdAt = Date(timeIntervalSince1970: 9_999)
    }
    expectHashChanges("random seed") { $0.strokes[0].randomSeed = 7 }
    expectHashChanges("mask") { $0.strokes[0].mask?.append(.close) }
    expectHashChanges("render group id") { $0.strokes[0].renderGroupID = nil }
    expectHashChanges("path id") { $0.strokes[0].pathID = UUID() }
    expectHashChanges("grain offset") { $0.strokes[0].grainOffset?.x = 0.9 }
    expectHashChanges("stroke count") { $0.strokes.removeLast() }
}

@Test func contentHashChangesWithTheTool() {
    expectHashChanges("engine") { $0.strokes[0].tool.engine = "pencilkit" }
    expectHashChanges("ink type") { $0.strokes[0].tool.inkType = "marker" }
    expectHashChanges("colour red") { $0.strokes[0].tool.color.r = 0.9 }
    expectHashChanges("colour green") { $0.strokes[0].tool.color.g = 0.9 }
    expectHashChanges("colour blue") { $0.strokes[0].tool.color.b = 0.9 }
    expectHashChanges("colour alpha") { $0.strokes[0].tool.color.a = 0.5 }
    expectHashChanges("width") { $0.strokes[0].tool.width = 8 }
    expectHashChanges("highlighter") { $0.strokes[0].tool.isHighlighter = true }
}

@Test func contentHashChangesWithTheTransform() {
    for index in 0..<StrokeRecord.transformElementCount {
        expectHashChanges("transform element \(index)") { page in
            page.strokes[0].transform[index] += 1
        }
    }
    expectHashChanges("transform length") {
        $0.strokes[0].transform = [1, 0, 0, 1, 0]
    }
}

@Test func contentHashChangesWithEveryPointValue() {
    expectHashChanges("point x") { $0.strokes[0].points[0].x += 1 }
    expectHashChanges("point y") { $0.strokes[0].points[0].y += 1 }
    expectHashChanges("point time") { $0.strokes[0].points[0].timeOffset += 1 }
    expectHashChanges("point width") { $0.strokes[0].points[0].width += 1 }
    expectHashChanges("point height") { $0.strokes[0].points[0].height += 1 }
    expectHashChanges("point opacity") { $0.strokes[0].points[0].opacity = 0.5 }
    expectHashChanges("point force") { $0.strokes[0].points[0].force += 1 }
    expectHashChanges("point azimuth") { $0.strokes[0].points[0].azimuth += 1 }
    expectHashChanges("point altitude") { $0.strokes[0].points[0].altitude += 1 }
    expectHashChanges("point secondary scale") { $0.strokes[0].points[0].secondaryScale += 1 }
    expectHashChanges("point threshold") { $0.strokes[0].points[0].threshold += 1 }
    expectHashChanges("point lateral jitter") { $0.strokes[0].points[0].lateralJitter += 1 }
    expectHashChanges("point count") { $0.strokes[0].points.removeLast() }
}

@Test func contentHashChangesWithDeletedTypedAndPDFContent() {
    expectHashChanges("deleted stroke ids") { $0.deletedStrokeIDs.insert(UUID()) }
    expectHashChanges("typed text") {
        $0.elements[0].content = .text("Holiday plans", fontName: "System", fontSize: 14, color: .black)
    }
    expectHashChanges("typed text source added") { page in
        let element = page.elements[0]
        page.elements.append(element)
    }
    expectHashChanges("pdf asset") {
        $0.elements[1].content = .pdfPage(assetName: "other.pdf", pageIndex: 1)
    }
    expectHashChanges("pdf page index") {
        $0.elements[1].content = .pdfPage(assetName: "handout.pdf", pageIndex: 2)
    }
    expectHashChanges("pdf reference removed") { $0.elements.removeLast() }
}
