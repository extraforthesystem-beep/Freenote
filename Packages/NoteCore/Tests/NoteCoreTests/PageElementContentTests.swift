import Foundation
import Testing
@testable import NoteCore

/// Sticky notes and tape were added after the first page files were written, so
/// the codec must carry them exactly while still reading the elements it wrote
/// before they existed.
@Suite("Page element content")
struct PageElementContentTests {
    private static let sticky = RGBAColor(r: 1, g: 0.87, b: 0.75)
    private static let tapeRed = RGBAColor(r: 0.9, g: 0.22, b: 0.2)

    // MARK: - New kinds

    @Test func stickyNoteRoundTripsThroughAPageFile() throws {
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let element = PageElement(
            id: UUID(),
            layerID: layer.id,
            frame: ElementFrame(x: 20, y: 30, width: 200, height: 200, rotation: 0.25),
            zIndex: 2,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000.123456),
            content: .stickyNote("Buy milk\nand eggs", color: Self.sticky)
        )
        let page = Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: .blank,
            layers: [layer],
            elements: [element]
        )

        let decoded = try PageCodec.decode(try PageCodec.encode(page))
        #expect(decoded == page)
        #expect(decoded.elements.count == 1)
        #expect(decoded.elements[0].content == .stickyNote("Buy milk\nand eggs", color: Self.sticky))
        // An empty note is a blank note, not a decode failure.
        let blank = try Self.roundTrip(.stickyNote("", color: Self.sticky))
        #expect(blank == .stickyNote("", color: Self.sticky))
    }

    @Test func tapeRoundTripsThroughAPageFile() throws {
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let element = PageElement(
            id: UUID(),
            layerID: layer.id,
            frame: ElementFrame(x: 100, y: 400, width: 240, height: 36),
            zIndex: 1,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            content: .tape(color: Self.tapeRed)
        )
        let page = Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: .blank,
            layers: [layer],
            elements: [element]
        )

        let decoded = try PageCodec.decode(try PageCodec.encode(page))
        #expect(decoded == page)
        #expect(decoded.elements[0].content == .tape(color: Self.tapeRed))
    }

    @Test func newKindsSurviveRepeatedEncoding() throws {
        for content in [
            ElementContent.stickyNote("Note", color: Self.sticky),
            .tape(color: Self.tapeRed),
        ] {
            let encoded = try NoteCoreJSON.encoder().encode(content)
            let decoded = try NoteCoreJSON.decoder().decode(ElementContent.self, from: encoded)
            #expect(decoded == content)
            let reencoded = try NoteCoreJSON.encoder().encode(decoded)
            #expect(reencoded == encoded, "re-encoding changed the bytes")
        }
    }

    // MARK: - Files written before these kinds existed

    /// The JSON a text box has always been written as.
    @Test func legacyTextElementJSONStillDecodes() throws {
        let json = """
        {
          "id": "5E50C4B2-3A6E-4C43-9C7F-4B5F5A0D2F1B",
          "layerID": "0C1F0C4E-9D3A-4A0E-9F8B-5E1C2B3A4D5E",
          "frame": { "x": 10, "y": 20, "width": 200, "height": 40, "rotation": 0 },
          "zIndex": 3,
          "updatedAt": "2024-01-02T03:04:05.000000000Z",
          "content": {
            "kind": "text",
            "text": "Hello",
            "fontName": "Helvetica",
            "fontSize": 16,
            "color": { "r": 0, "g": 0, "b": 0, "a": 1 }
          }
        }
        """
        let element = try NoteCoreJSON.decoder().decode(PageElement.self, from: Data(json.utf8))
        #expect(element.content == .text("Hello", fontName: "Helvetica", fontSize: 16, color: .black))
        #expect(element.zIndex == 3)
        // No locking key in files from before locking existed.
        #expect(element.isLocked == false)
        #expect(element.textStyle == nil)
    }

    /// Shapes are written with `kind` plus `shapeKind`, so a new `kind` value must
    /// not disturb them.
    @Test func legacyShapeElementJSONStillDecodes() throws {
        let json = """
        {
          "kind": "shape",
          "shapeKind": "ellipse",
          "stroke": { "r": 0, "g": 0, "b": 0, "a": 1 },
          "fill": { "r": 1, "g": 0, "b": 0, "a": 0.5 },
          "lineWidth": 2
        }
        """
        let content = try NoteCoreJSON.decoder().decode(ElementContent.self, from: Data(json.utf8))
        #expect(content == .shape(
            kind: "ellipse",
            stroke: .black,
            fill: RGBAColor(r: 1, g: 0, b: 0, a: 0.5),
            lineWidth: 2
        ))
    }

    @Test func legacyElementsInAPageFileStillDecode() throws {
        var rng = SplitMix64(seed: 0x57_1C4E)
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let page = Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: .blank,
            layers: [layer],
            elements: [
                PageElement(
                    id: randomUUID(&rng),
                    layerID: layer.id,
                    frame: ElementFrame(x: 10, y: 10, width: 100, height: 30),
                    zIndex: 0,
                    updatedAt: randomDate(&rng),
                    content: .text("Text", fontName: "System", fontSize: 16, color: .black)
                ),
                PageElement(
                    id: randomUUID(&rng),
                    layerID: layer.id,
                    frame: ElementFrame(x: 10, y: 100, width: 100, height: 100),
                    zIndex: 1,
                    updatedAt: randomDate(&rng),
                    content: .shape(kind: "rect", stroke: .black, fill: nil, lineWidth: 1)
                ),
            ]
        )
        let decoded = try PageCodec.decode(try PageCodec.encode(page))
        #expect(decoded == page)
    }

    /// An element kind this build does not know is a normal decode failure, the
    /// same as any other unreadable page: it must not crash or trap.
    @Test func unknownKindIsADecodeErrorNotACrash() throws {
        let json = """
        { "kind": "hologram", "text": "from the future" }
        """
        #expect(throws: DecodingError.self) {
            _ = try NoteCoreJSON.decoder().decode(ElementContent.self, from: Data(json.utf8))
        }
    }

    // MARK: - Helpers

    private static func roundTrip(_ content: ElementContent) throws -> ElementContent {
        let encoded = try NoteCoreJSON.encoder().encode(content)
        return try NoteCoreJSON.decoder().decode(ElementContent.self, from: encoded)
    }
}
