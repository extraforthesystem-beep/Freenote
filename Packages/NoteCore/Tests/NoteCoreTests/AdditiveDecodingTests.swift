import Foundation
import Testing
@testable import NoteCore

/// A file written by an older build lacks the fields that build did not know.
/// These tests take a real encoding, delete the keys a newer build might add,
/// and check that the file still opens with the documented default. That is the
/// additive-change contract: the on-disk shape may grow without a schema bump,
/// while identity and content still round-trip exactly.
@Suite("Additive schema changes")
struct AdditiveDecodingTests {
    // MARK: - Page

    @Test func pageWithoutLayersGetsOneDefaultLayer() throws {
        let page = Page(
            id: UUID(),
            width: 612,
            height: 792,
            template: .blank,
            layers: [Page.Layer(id: UUID(), name: "Ink", isVisible: false, isLocked: true)]
        )
        var object = try pageObject(page)
        object.removeValue(forKey: "layers")

        let decoded = try PageCodec.decode(try pageData(object))

        #expect(decoded.id == page.id)
        #expect(decoded.width == page.width)
        #expect(decoded.height == page.height)
        #expect(decoded.template == page.template)
        #expect(decoded.strokes.isEmpty)
        #expect(decoded.elements.isEmpty)
        #expect(decoded.layers.count == 1)
        #expect(decoded.layers.first?.name == "Layer 1")
        #expect(decoded.layers.first?.isVisible == true)
        #expect(decoded.layers.first?.isLocked == false)
    }

    @Test func pageWithoutStrokesAndElementsIsEmpty() throws {
        var rng = SplitMix64(seed: 0xADA_17)
        let layer = Page.Layer(id: UUID(), name: "Ink")
        let page = Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: .blank,
            layers: [layer],
            strokes: [randomStroke(&rng, layerID: layer.id, pointCount: 6)],
            elements: [randomElement(&rng, layerID: layer.id)],
            deletedStrokeIDs: [randomUUID(&rng)],
            deletedElementIDs: [randomUUID(&rng)]
        )
        var object = try pageObject(page)
        object.removeValue(forKey: "strokes")
        object.removeValue(forKey: "elements")

        let decoded = try PageCodec.decode(try pageData(object))
        var expected = page
        expected.strokes = []
        expected.elements = []

        #expect(decoded == expected)
        #expect(decoded.layers == page.layers)
        #expect(decoded.deletedStrokeIDs == page.deletedStrokeIDs)
        #expect(decoded.deletedElementIDs == page.deletedElementIDs)
    }

    @Test func pageWithoutTemplateIsBlank() throws {
        let page = Page(
            id: UUID(),
            width: 612,
            height: 792,
            template: .custom(assetName: "planner.png"),
            layers: [Page.Layer(id: UUID(), name: "Layer 1")]
        )
        var object = try pageObject(page)
        object.removeValue(forKey: "template")

        let decoded = try PageCodec.decode(try pageData(object))
        var expected = page
        expected.template = .blank

        #expect(decoded == expected)
    }

    @Test func pageWithoutSchemaVersionReadsAsTheFirstSchema() throws {
        let page = Page(id: UUID(), width: 612, height: 792, template: .blank)
        var object = try pageObject(page)
        object.removeValue(forKey: "schemaVersion")

        let decoded = try PageCodec.decode(try pageData(object))

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.schemaVersion == SchemaVersion.initial)
        #expect(decoded == page)
    }

    @Test func pageWithoutDeletionTombstonesHasNoTombstones() throws {
        let page = Page(
            id: UUID(),
            width: 100,
            height: 100,
            template: .blank,
            layers: [Page.Layer(id: UUID(), name: "Layer 1")],
            deletedStrokeIDs: [UUID()],
            deletedElementIDs: [UUID()]
        )
        var object = try pageObject(page)
        object.removeValue(forKey: "deletedStrokeIDs")
        object.removeValue(forKey: "deletedElementIDs")

        let decoded = try PageCodec.decode(try pageData(object))

        #expect(decoded.deletedStrokeIDs.isEmpty)
        #expect(decoded.deletedElementIDs.isEmpty)
        #expect(decoded.id == page.id)
        #expect(decoded.layers == page.layers)
    }

    @Test func layerWithoutOptionalFlagsIsVisibleAndUnlocked() throws {
        let layer = Page.Layer(id: UUID(), name: "Ink", isVisible: false, isLocked: true)
        let page = Page(id: UUID(), width: 100, height: 100, template: .blank, layers: [layer])
        var object = try pageObject(page)
        var layers = try #require(object["layers"] as? [[String: Any]])
        layers[0].removeValue(forKey: "isVisible")
        layers[0].removeValue(forKey: "isLocked")
        object["layers"] = layers

        let decoded = try PageCodec.decode(try pageData(object))

        #expect(decoded.layers.count == 1)
        #expect(decoded.layers[0].id == layer.id)
        #expect(decoded.layers[0].name == "Ink")
        #expect(decoded.layers[0].isVisible)
        #expect(!decoded.layers[0].isLocked)
    }

    // MARK: - Strokes

    @Test func strokeWithoutOptionalFieldsUsesDefaults() throws {
        var rng = SplitMix64(seed: 0x570_7E)
        let layer = Page.Layer(id: UUID(), name: "Ink")
        var stroke = randomStroke(&rng, layerID: layer.id, pointCount: 4)
        stroke.tool.isHighlighter = true
        stroke.transform = [1, 0.25, 0, 1, 12, -4]
        let page = Page(
            id: UUID(),
            width: 100,
            height: 100,
            template: .blank,
            layers: [layer],
            strokes: [stroke]
        )

        var object = try pageObject(page)
        var strokes = try #require(object["strokes"] as? [[String: Any]])
        var tool = try #require(strokes[0]["tool"] as? [String: Any])
        tool.removeValue(forKey: "isHighlighter")
        strokes[0]["tool"] = tool
        strokes[0].removeValue(forKey: "transform")
        object["strokes"] = strokes

        let decoded = try PageCodec.decode(try pageData(object))
        var expected = stroke
        expected.tool.isHighlighter = false
        expected.transform = StrokeRecord.identityTransform

        #expect(decoded.strokes == [expected])
    }

    @Test func strokePointWithoutOptionalShadingDefaultsToZero() throws {
        var rng = SplitMix64(seed: 0x901_7A)
        let layer = Page.Layer(id: UUID(), name: "Ink")
        var stroke = randomStroke(&rng, layerID: layer.id, pointCount: 2)
        stroke.points[0].threshold = 0.75
        stroke.points[0].lateralJitter = 0.4
        let page = Page(
            id: UUID(),
            width: 100,
            height: 100,
            template: .blank,
            layers: [layer],
            strokes: [stroke]
        )

        var object = try pageObject(page)
        var strokes = try #require(object["strokes"] as? [[String: Any]])
        var points = try #require(strokes[0]["points"] as? [[String: Any]])
        points[0].removeValue(forKey: "threshold")
        points[0].removeValue(forKey: "lateralJitter")
        strokes[0]["points"] = points
        object["strokes"] = strokes

        let decoded = try PageCodec.decode(try pageData(object))
        var expected = stroke
        expected.points[0].threshold = 0
        expected.points[0].lateralJitter = 0

        #expect(decoded.strokes == [expected])
    }

    // MARK: - Elements

    @Test func elementWithoutOptionalFieldsUsesDefaults() throws {
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let element = PageElement(
            id: UUID(),
            layerID: layer.id,
            frame: ElementFrame(x: 10, y: 20, width: 200, height: 40, rotation: 0.5),
            zIndex: 3,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000.123456),
            content: .text("Hello", fontName: "Helvetica", fontSize: 16, color: .black),
            isLocked: true,
            textStyle: TextStyle(isBold: true, alignment: .center)
        )
        let page = Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: .blank,
            layers: [layer],
            elements: [element]
        )

        var object = try pageObject(page)
        var elements = try #require(object["elements"] as? [[String: Any]])
        elements[0].removeValue(forKey: "isLocked")
        elements[0].removeValue(forKey: "textStyle")
        var frame = try #require(elements[0]["frame"] as? [String: Any])
        frame.removeValue(forKey: "rotation")
        elements[0]["frame"] = frame
        object["elements"] = elements

        let decoded = try PageCodec.decode(try pageData(object))
        var expected = element
        expected.isLocked = false
        expected.textStyle = nil
        expected.frame.rotation = 0

        #expect(decoded.elements == [expected])
    }

    // MARK: - Manifest and library info

    @Test func manifestWithoutOptionalFieldsUsesDefaults() throws {
        let manifest = NotebookManifest(
            id: UUID(),
            title: "Trip",
            coverName: "cover.png",
            pageOrder: [UUID(), UUID()],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.123456),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500.654321),
            deletedAt: Date(timeIntervalSince1970: 1_700_000_600),
            pageScrollMode: .horizontal,
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_700)
        )
        var object = try manifestObject(manifest)
        for key in [
            "schemaVersion", "coverName", "pageOrder", "deletedAt",
            "pageScrollMode", "lastOpenedAt",
        ] {
            object.removeValue(forKey: key)
        }

        let decoded = try ManifestCodec.decode(try manifestData(object))

        #expect(decoded.schemaVersion == SchemaVersion.initial)
        #expect(decoded.id == manifest.id)
        #expect(decoded.title == manifest.title)
        #expect(decoded.coverName == nil)
        #expect(decoded.pageOrder.isEmpty)
        #expect(decoded.createdAt == manifest.createdAt)
        #expect(decoded.updatedAt == manifest.updatedAt)
        #expect(decoded.deletedAt == nil)
        #expect(decoded.pageScrollMode == nil)
        #expect(decoded.lastOpenedAt == nil)
    }

    @Test func libraryInfoWithoutSchemaVersionReadsAsTheFirstSchema() throws {
        let info = LibraryInfo(deviceID: UUID())
        var object = try object(from: try LibraryInfoCodec.encode(info))
        object.removeValue(forKey: "schemaVersion")

        let decoded = try LibraryInfoCodec.decode(try manifestData(object))

        #expect(decoded.schemaVersion == SchemaVersion.initial)
        #expect(decoded.deviceID == info.deviceID)
    }

    // MARK: - Unknown keys stay additive

    @Test func unknownKeysAreIgnoredAndNeverReencoded() throws {
        let page = Page(id: UUID(), width: 612, height: 792, template: .blank)
        var pageJSON = try pageObject(page)
        pageJSON["futurePageField"] = ["nested": true]

        let decodedPage = try PageCodec.decode(try pageData(pageJSON))
        #expect(decodedPage == page)

        let reencoded = try Zlib.decompress(try PageCodec.encode(decodedPage), path: "test")
        let text = String(decoding: reencoded, as: UTF8.self)
        #expect(!text.contains("futurePageField"))

        let manifest = NotebookManifest(
            id: UUID(),
            title: "Notes",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var manifestJSON = try manifestObject(manifest)
        manifestJSON["futureManifestField"] = 1
        #expect(try ManifestCodec.decode(try manifestData(manifestJSON)) == manifest)
    }

    // MARK: - What stays strict

    @Test func pageWithoutIDIsStillCorrupt() throws {
        let page = Page(id: UUID(), width: 612, height: 792, template: .blank)
        var object = try pageObject(page)
        object.removeValue(forKey: "id")

        #expect(throwsCorruptFile { _ = try PageCodec.decode(try pageData(object)) })
    }

    @Test func pageWithoutGeometryIsStillCorrupt() throws {
        let page = Page(id: UUID(), width: 612, height: 792, template: .blank)

        for key in ["width", "height"] {
            var object = try pageObject(page)
            object.removeValue(forKey: key)
            #expect(throwsCorruptFile { _ = try PageCodec.decode(try pageData(object)) })
        }
    }

    @Test func manifestWithoutIDOrTitleIsStillCorrupt() throws {
        let manifest = NotebookManifest(
            id: UUID(),
            title: "Notes",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        for key in ["id", "title"] {
            var object = try manifestObject(manifest)
            object.removeValue(forKey: key)
            #expect(throwsCorruptFile { _ = try ManifestCodec.decode(try manifestData(object)) })
        }
    }

    /// An element kind this build cannot render is still corrupt content. A
    /// placeholder would render wrong and hide the damage; see the report for
    /// why unknown cases are not mapped to a guessed representation.
    @Test func unknownElementKindIsStillCorrupt() throws {
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let element = PageElement(
            id: UUID(),
            layerID: layer.id,
            frame: ElementFrame(x: 0, y: 0, width: 10, height: 10),
            zIndex: 0,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            content: .text("Hello", fontName: "Helvetica", fontSize: 12, color: .black)
        )
        let page = Page(
            id: UUID(),
            width: 100,
            height: 100,
            template: .blank,
            layers: [layer],
            elements: [element]
        )

        var object = try pageObject(page)
        var elements = try #require(object["elements"] as? [[String: Any]])
        elements[0]["content"] = ["kind": "hologram", "text": "from the future"]
        object["elements"] = elements

        #expect(throwsCorruptFile { _ = try PageCodec.decode(try pageData(object)) })
    }

    // MARK: - Helpers

    private func object(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func pageObject(_ page: Page) throws -> [String: Any] {
        let json = try Zlib.decompress(try PageCodec.encode(page), path: "test")
        return try object(from: json)
    }

    private func pageData(_ object: [String: Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: object)
        return try #require(zlibCompress(json))
    }

    private func manifestObject(_ manifest: NotebookManifest) throws -> [String: Any] {
        try object(from: try ManifestCodec.encode(manifest))
    }

    private func manifestData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}
