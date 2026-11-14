import NoteCore
import XCTest
@testable import NoteApp

/// The paper background's cache key: the live page and the pre-render must key
/// the same page identically, or the pre-rendered paper is never found.
@MainActor
final class PageBackgroundKeyTests: XCTestCase {
    private func page(
        elements: [PageElement] = [],
        strokes: [StrokeRecord] = []
    ) -> Page {
        var page = Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: PageTemplate(
                kind: "ruled",
                spacing: 24,
                lineColor: RGBAColor(r: 0.6, g: 0.67, b: 0.77),
                paperColor: .white
            )
        )
        page.elements = elements
        page.strokes = strokes
        return page
    }

    private func element(
        on layerID: UUID,
        zIndex: Int = 0,
        updatedAt: Date = Date()
    ) -> PageElement {
        PageElement(
            id: UUID(),
            layerID: layerID,
            frame: ElementFrame(x: 0, y: 0, width: 100, height: 100),
            zIndex: zIndex,
            updatedAt: updatedAt,
            content: .image(assetName: "photo.png")
        )
    }

    private func stroke(on layerID: UUID) -> StrokeRecord {
        StrokeRecord(
            id: UUID(),
            layerID: layerID,
            tool: StrokeTool(engine: "metal", inkType: "pen", color: .init(r: 0, g: 0, b: 0), width: 3),
            createdAt: Date(),
            randomSeed: 1,
            points: [StrokePoint(
                x: 1,
                y: 2,
                timeOffset: 0,
                width: 3,
                height: 3,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: 1.5,
                secondaryScale: 1
            )]
        )
    }

    func testKeyMatchesThePrewarmKey() {
        let page = page(elements: [])
        var withPicture = page
        withPicture.elements = [element(on: page.layers[0].id)]
        let assets = URL(fileURLWithPath: "/tmp/notebook-assets")
        let memo = BackgroundKeyMemo()

        XCTAssertEqual(
            memo.key(for: withPicture, assetsDirectory: assets, usesDarkPaper: true),
            PageBackgroundCache.baseKey(
                for: withPicture.withoutTape,
                assetsDirectory: assets,
                usesDarkPaper: true
            )
        )
    }

    func testTapeDoesNotChangeTheKey() {
        let plain = page()
        let tape = PageElement(
            id: UUID(),
            layerID: plain.layers[0].id,
            frame: ElementFrame(x: 20, y: 20, width: 100, height: 40),
            zIndex: 1,
            updatedAt: Date(),
            content: .tape(color: .init(r: 1, g: 0.9, b: 0.5))
        )
        var taped = plain
        taped.elements = [tape]
        let memo = BackgroundKeyMemo()

        // Tape is an overlay, not paper: the live page draws its tape without
        // the background, and the pre-render is keyed the same way.
        XCTAssertEqual(
            memo.key(for: taped, assetsDirectory: nil, usesDarkPaper: false),
            memo.key(for: plain, assetsDirectory: nil, usesDarkPaper: false)
        )
    }

    func testKeyIsReusedWhileOnlyInkChanges() {
        let plain = page()
        var first = plain
        first.elements = [element(on: plain.layers[0].id)]
        let memo = BackgroundKeyMemo()
        let key = memo.key(for: first, assetsDirectory: nil, usesDarkPaper: false)

        // The page is handed back after every stroke, with the same paper.
        var inked = first
        inked.strokes = [stroke(on: first.layers[0].id)]
        XCTAssertEqual(memo.key(for: inked, assetsDirectory: nil, usesDarkPaper: false), key)
    }

    func testKeyChangesWhenAnElementChanges() {
        var page = page()
        let element = element(on: page.layers[0].id)
        page.elements = [element]
        let memo = BackgroundKeyMemo()
        let key = memo.key(for: page, assetsDirectory: nil, usesDarkPaper: false)

        var moved = page
        moved.elements = [element]
        moved.elements[0].frame.x = 40
        moved.elements[0].updatedAt = Date()

        XCTAssertNotEqual(memo.key(for: moved, assetsDirectory: nil, usesDarkPaper: false), key)
    }

    func testKeyChangesWithDarkPaper() {
        let page = page()
        let memo = BackgroundKeyMemo()

        XCTAssertNotEqual(
            memo.key(for: page, assetsDirectory: nil, usesDarkPaper: true),
            memo.key(for: page, assetsDirectory: nil, usesDarkPaper: false)
        )
    }
}
