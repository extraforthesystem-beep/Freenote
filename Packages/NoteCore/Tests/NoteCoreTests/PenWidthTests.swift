import Foundation
import Testing
@testable import NoteCore

struct PenWidthTests {
    @Test
    func convertsBetweenPointsAndMillimetres() {
        #expect(abs(PenWidth.millimetres(fromPoints: 72) - 25.4) < 0.0001)
        #expect(abs(PenWidth.points(fromMillimetres: 25.4) - 72) < 0.0001)
        #expect(abs(PenWidth.points(fromMillimetres: 0.5) - 1.4173) < 0.001)
        #expect(abs(PenWidth.points(fromMillimetres: 0.7) - 1.9843) < 0.001)
        #expect(abs(PenWidth.points(fromMillimetres: 0.9) - 2.5512) < 0.001)
    }

    @Test
    func snapsToTenthsOfAMillimetre() {
        #expect(abs(PenWidth.snappedMillimetres(0.54) - 0.5) < 0.0001)
        #expect(abs(PenWidth.snappedMillimetres(0.56) - 0.6) < 0.0001)
        #expect(abs(PenWidth.snappedMillimetres(12.04) - 12.0) < 0.0001)
        let snapped = PenWidth.snappedPoints(fromMillimetres: 0.549)
        #expect(abs(PenWidth.millimetres(fromPoints: snapped) - 0.5) < 0.0001)
    }

    @Test
    func clampsWidthsIntoARange() {
        #expect(PenWidth.clamp(1.417, to: 2.4...16) == 2.4)
        #expect(PenWidth.clamp(20, to: 2.4...16) == 16)
        #expect(PenWidth.clamp(4, to: 2.4...16) == 4)
    }

    @Test
    func labelsWidthsInMillimetresWithOneDecimal() {
        #expect(PenWidth.label(PenWidth.points(fromMillimetres: 0.5)) == "0.5 mm")
        #expect(PenWidth.label(PenWidth.points(fromMillimetres: 0.9)) == "0.9 mm")
        #expect(PenWidth.label(72) == "25.4 mm")
    }

    @Test
    func millimetreRangeStaysOnTenthStepsAndInsideThePointRange() {
        let range = PenWidth.millimetreRange(for: 0.878...25.66)
        #expect(abs(range.lowerBound - 0.4) < 0.0001)
        #expect(abs(range.upperBound - 9.0) < 0.0001)
        #expect(PenWidth.points(fromMillimetres: range.lowerBound) >= 0.878)
        #expect(PenWidth.points(fromMillimetres: range.upperBound) <= 25.66)
    }
}

struct WidthPresetsTests {
    @Test
    func defaultsUseFinePenAndFamiliarHighlighterWidths() {
        #expect(WidthPresetDefaults.pen.count == 3)
        #expect(abs(PenWidth.millimetres(fromPoints: WidthPresetDefaults.pen[0]) - 0.5) < 0.0001)
        #expect(abs(PenWidth.millimetres(fromPoints: WidthPresetDefaults.pen[1]) - 0.7) < 0.0001)
        #expect(abs(PenWidth.millimetres(fromPoints: WidthPresetDefaults.pen[2]) - 0.9) < 0.0001)
        #expect(WidthPresetDefaults.highlighter == [12, 24, 40])
    }

    @Test
    func normalisesToThreeSlots() {
        #expect(WidthPresets([]).widths.count == 3)
        #expect(WidthPresets([4]).widths == [4, 4, 4])
        #expect(WidthPresets([1, 2]).widths == [1, 2, 1])
        #expect(WidthPresets([1, 2, 3, 4]).widths == [1, 2, 3])
    }

    @Test
    func replacingASlotClampsToTheStyleRange() {
        var presets = WidthPresets(WidthPresetDefaults.pen)
        let replaced = presets.setWidth(1.417, at: 0, range: 2.4...16)
        #expect(replaced)
        #expect(presets.widths[0] == 2.4)

        let outOfRange = presets.setWidth(3, at: 5, range: 2.4...16)
        #expect(!outOfRange)
        #expect(presets.widths.count == 3)
    }

    @Test
    func clampedGivesEverySlotTheStylesRange() {
        let presets = WidthPresets(WidthPresetDefaults.pen)
        let clamped = presets.clamped(to: 2.4...16)
        #expect(clamped.allSatisfy { (2.4...16).contains($0) })
        #expect(clamped[0] == 2.4)
    }

    @Test
    func ranksGiveEqualWidthsTheSameSize() {
        #expect(WidthPresets.ranks(for: [1, 2, 3]) == [0, 1, 2])
        #expect(WidthPresets.ranks(for: [3, 1, 3]) == [1, 0, 1])
        #expect(WidthPresets.ranks(for: [5, 5, 5]) == [0, 0, 0])
    }

    @Test
    func roundTripsThroughJSONAndRejectsMalformedWidths() throws {
        let presets = WidthPresets(WidthPresetDefaults.highlighter)
        let data = try JSONEncoder().encode(presets)
        let decoded = try JSONDecoder().decode(WidthPresets.self, from: data)
        #expect(decoded == presets)

        let malformed = #"{"widths":[1,2]}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WidthPresets.self, from: malformed)
        }
    }
}
