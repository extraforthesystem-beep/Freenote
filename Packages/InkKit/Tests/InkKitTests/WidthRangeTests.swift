import PencilKit
import Testing
@testable import InkKit

struct WidthRangeTests {
    @Test
    func everyStyleUsesPencilKitsOwnWidthRange() {
        for style in PenStyle.allCases {
            let expected = style.inkType.validWidthRange
            #expect(style.widthRange.lowerBound == Double(expected.lowerBound))
            #expect(style.widthRange.upperBound == Double(expected.upperBound))
            #expect(style.widthRange.contains(style.defaultWidth))
        }
    }

    @Test
    func highlighterTakesTheMarkerRange() {
        #expect(InkTool.highlighter.widthRange == PenStyle.marker.widthRange)
        #expect(InkTool.highlighter.widthRange.contains(24))
    }
}
