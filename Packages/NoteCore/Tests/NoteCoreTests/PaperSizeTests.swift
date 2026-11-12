import Foundation
import Testing
@testable import NoteCore

/// Paper sizes are stored by raw value, so a new case must not disturb the
/// sizes already on disk.
@Suite("Paper size")
struct PaperSizeTests {
    @Test func screenIsAnIPadShapedPortraitPage() {
        let size = PaperSize.screen.portraitSize
        #expect(size.width == 768)
        #expect(size.height == 1024)
        #expect(abs(size.width / size.height - 0.75) < 0.001)
        #expect(PaperSize.screen.displayName == "Screen (Optimised)")
    }

    @Test func screenLandscapeSwapsTheEdges() {
        let size = PaperSize.screen.size(.landscape)
        #expect(size.width == 1024)
        #expect(size.height == 768)
    }

    @Test func matchFindsScreenInBothOrientations() {
        let portrait = PaperSize.match(width: 768, height: 1024)
        #expect(portrait?.0 == .screen)
        #expect(portrait?.1 == .portrait)

        let landscape = PaperSize.match(width: 1024, height: 768)
        #expect(landscape?.0 == .screen)
        #expect(landscape?.1 == .landscape)
    }

    @Test func storedRawValuesStillDecode() throws {
        let old = try JSONDecoder().decode(PaperSize.self, from: Data(#""a4""#.utf8))
        #expect(old == .a4)

        let roundTrip = try JSONDecoder().decode(
            PaperSize.self,
            from: JSONEncoder().encode(PaperSize.screen)
        )
        #expect(roundTrip == .screen)
    }
}
