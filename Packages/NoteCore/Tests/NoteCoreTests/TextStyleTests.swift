import Foundation
import Testing
@testable import NoteCore

struct TextStyleTests {
    @Test
    func textStyleSurvivesPageRoundTrip() throws {
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let element = PageElement(
            id: UUID(),
            layerID: layer.id,
            frame: ElementFrame(x: 20, y: 40, width: 300, height: 80),
            zIndex: 0,
            updatedAt: Date(timeIntervalSinceReferenceDate: 780_000_000),
            content: .text("Hello", fontName: "System", fontSize: 18, color: .black),
            isLocked: true,
            textStyle: TextStyle(
                isBold: true,
                isItalic: true,
                isUnderline: true,
                alignment: .center,
                lineSpacing: 3
            )
        )
        let page = Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: .blank,
            layers: [layer],
            elements: [element],
            deletedElementIDs: [UUID()]
        )

        let data = try PageCodec.encode(page)
        let decoded = try PageCodec.decode(data)

        #expect(decoded.elements.first?.isLocked == true)
        #expect(decoded.elements.first?.textStyle?.isBold == true)
        #expect(decoded.elements.first?.textStyle?.isItalic == true)
        #expect(decoded.elements.first?.textStyle?.isUnderline == true)
        #expect(decoded.elements.first?.textStyle?.alignment == .center)
        #expect(decoded.deletedElementIDs == page.deletedElementIDs)
    }

    @Test
    func olderPageJSONWithoutNewElementKeysStillDecodes() throws {
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let element = PageElement(
            id: UUID(),
            layerID: layer.id,
            frame: ElementFrame(x: 0, y: 0, width: 100, height: 40),
            zIndex: 0,
            updatedAt: Date(timeIntervalSinceReferenceDate: 780_000_000),
            content: .text("Old", fontName: "System", fontSize: 14, color: .black)
        )
        let page = Page(
            id: UUID(),
            width: 595,
            height: 842,
            template: .blank,
            layers: [layer],
            elements: [element]
        )

        let encoded = try NoteCoreJSON.encoder().encode(page)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "deletedElementIDs")
        var elements = try #require(object["elements"] as? [[String: Any]])
        elements[0].removeValue(forKey: "isLocked")
        elements[0].removeValue(forKey: "textStyle")
        object["elements"] = elements

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try NoteCoreJSON.decoder().decode(Page.self, from: legacy)

        #expect(decoded.deletedElementIDs.isEmpty)
        #expect(decoded.elements.first?.isLocked == false)
        #expect(decoded.elements.first?.textStyle == nil)
    }
}
