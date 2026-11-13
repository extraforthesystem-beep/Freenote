import Foundation
import Testing
@testable import NoteCore

/// A custom template only changes the `kind` string, so pages written before
/// custom templates existed keep decoding, and a page written with one keeps
/// naming its picture after a round trip.
@Suite("Page template")
struct PageTemplateTests {
    @Test func customKindNamesItsAsset() {
        let template = PageTemplate.custom(assetName: "abc123.png")
        #expect(template.customAssetName == "abc123.png")
        #expect(template.kind == PageTemplate.customKindPrefix + "abc123.png")
        #expect(template.paperColor == .white)
    }

    @Test func builtInKindsHaveNoAsset() {
        #expect(PageTemplate.blank.customAssetName == nil)
        let ruled = PageTemplate(
            kind: "ruled",
            spacing: 24,
            lineColor: RGBAColor(r: 0.6, g: 0.7, b: 0.8),
            paperColor: .white
        )
        #expect(ruled.customAssetName == nil)
        #expect(PageTemplate(kind: "custom:", spacing: 0, lineColor: .white, paperColor: .white).customAssetName == nil)
    }

    @Test func customKindSurvivesAPageRoundTrip() throws {
        let template = PageTemplate.custom(assetName: "planner.png")
        let page = Page(id: UUID(), width: 595, height: 842, template: template)
        let decoded = try PageCodec.decode(PageCodec.encode(page))
        #expect(decoded.template == template)
        #expect(decoded.template.customAssetName == "planner.png")
    }
}
