import CoreGraphics
import Foundation
import NoteCore
import Testing
@testable import InkKit

@Suite("Template renderer")
struct TemplateRendererTests {
    static let kinds = [
        "blank", "ruled", "ruled-margin", "grid", "dotted", "cornell", "todo",
        "meeting", "weekly", "monthly", "daily", "music", "isometric", "hex",
        "handwriting", "storyboard",
    ]

    @Test("Every template kind renders a page-sized image", arguments: kinds)
    func renders(kind: String) {
        let page = CGSize(width: 595, height: 842)
        let image = TemplateRenderer.image(
            PageTemplate(
                kind: kind,
                spacing: 24,
                lineColor: RGBAColor(r: 0.6, g: 0.7, b: 0.8),
                paperColor: .white
            ),
            pageSize: page,
            scale: 1
        )
        #expect(image != nil)
        #if os(macOS)
        #expect(image?.size == page)
        #endif
    }
}
