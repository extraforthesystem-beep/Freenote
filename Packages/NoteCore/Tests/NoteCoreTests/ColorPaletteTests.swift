import Foundation
import Testing
@testable import NoteCore

struct ColorPaletteTests {
    @Test
    func paletteHasEightRowsOfEightDistinctColours() {
        #expect(ColorPalette.rows.count == 8)
        #expect(ColorPalette.rows.allSatisfy { $0.count == 8 })
        #expect(ColorPalette.presets.count == 64)
        #expect(Set(ColorPalette.presets.map { ColorHex.string(from: $0) }).count == 64)
    }

    @Test
    func eachHueRowGetsDarkerFromLeftToRight() {
        for row in ColorPalette.rows.dropFirst() {
            let first = row[0]
            let last = row[7]
            #expect(first.r + first.g + first.b > last.r + last.g + last.b)
        }
    }

    @Test
    func namesColoursByHueAndBrightness() {
        #expect(ColorPalette.name(for: .black) == "Black")
        #expect(ColorPalette.name(for: .white) == "White")
        #expect(ColorPalette.name(for: RGBAColor(r: 0, g: 1, b: 1)) == "Teal")
        #expect(ColorPalette.name(for: RGBAColor(r: 0, g: 0.36, b: 0.86)) == "Blue")
        #expect(ColorPalette.name(for: RGBAColor(r: 0.85, g: 0.13, b: 0.15)) == "Red")
        #expect(ColorPalette.name(for: RGBAColor(r: 1, g: 0.91, b: 0.30)) == "Yellow")
        #expect(ColorPalette.name(for: RGBAColor(r: 0.1, g: 0.15, b: 0.35)) == "Dark Blue")
        #expect(ColorPalette.name(for: RGBAColor(r: 0.32, g: 0.32, b: 0.34)) == "Dark Grey")
        #expect(ColorPalette.name(for: RGBAColor(r: 0.47, g: 0.30, b: 0.16)) == "Brown")
    }

    @Test
    func hexRoundTripsAndRejectsMalformedText() {
        let blue = RGBAColor(r: 0x1E / 255, g: 0x90 / 255, b: 0xFF / 255)
        #expect(ColorHex.string(from: blue) == "#1E90FF")
        let parsed = ColorHex.color(from: "#1E90FF")
        #expect(parsed.map { ColorHex.string(from: $0) } == "#1E90FF")
        #expect(ColorHex.color(from: "1e90ff")?.b == parsed?.b)

        #expect(ColorHex.color(from: "") == nil)
        #expect(ColorHex.color(from: "#12345") == nil)
        #expect(ColorHex.color(from: "#GGGGGG") == nil)
        #expect(ColorHex.color(from: "#1234567") == nil)
    }
}

struct ColorFavoritesTests {
    @Test
    func defaultsFillBothTools() {
        #expect(ColorFavorites(InkColorDefaults.pen).colors.count == 8)
        #expect(ColorFavorites(InkColorDefaults.highlighter).colors.count == 8)
        #expect(ColorFavorites(InkColorDefaults.pen).colors.first == .black)
    }

    @Test
    func migrationKeepsOldSwatchesFirstThenFillsDefaults() {
        let old = [
            RGBAColor(r: 0.1, g: 0.2, b: 0.3),
            RGBAColor(r: 0.4, g: 0.5, b: 0.6),
        ]
        let migrated = ColorFavorites(migrating: old, defaults: InkColorDefaults.pen)
        #expect(migrated.colors.count == 8)
        #expect(migrated.colors[0] == old[0])
        #expect(migrated.colors[1] == old[1])
        #expect(migrated.contains(old[0]))
    }

    @Test
    func migrationOfAFullOldListDropsDuplicates() {
        let old = Array(repeating: RGBAColor(r: 0.2, g: 0.4, b: 0.6), count: 5)
        let migrated = ColorFavorites(migrating: old, defaults: InkColorDefaults.pen)
        #expect(migrated.colors.count == 8)
        #expect(migrated.colors.first == RGBAColor(r: 0.2, g: 0.4, b: 0.6))
    }

    @Test
    func addRemoveAndReplaceRespectCapacity() {
        var favorites = ColorFavorites(InkColorDefaults.pen)
        #expect(favorites.isFull)
        let addedWhileFull = favorites.add(RGBAColor(r: 1, g: 0, b: 1))
        #expect(addedWhileFull == false)

        let removed = favorites.remove(at: 0)
        #expect(removed)
        #expect(favorites.colors.count == 7)
        #expect(favorites.isFull == false)
        let addedAfterRemoval = favorites.add(RGBAColor(r: 1, g: 0, b: 1))
        #expect(addedAfterRemoval)
        #expect(favorites.colors.count == 8)

        let replaced = favorites.replace(at: 0, with: RGBAColor(r: 0, g: 0, b: 1))
        #expect(replaced)
        #expect(favorites.colors[0] == RGBAColor(r: 0, g: 0, b: 1))
        let replacedOutOfRange = favorites.replace(at: 8, with: .black)
        #expect(replacedOutOfRange == false)
        let removedOutOfRange = favorites.remove(at: 99)
        #expect(removedOutOfRange == false)
    }

    @Test
    func addIgnoresColoursAlreadyShown() {
        var favorites = ColorFavorites([RGBAColor(r: 0, g: 0, b: 0)])
        let addedDuplicate = favorites.add(RGBAColor(r: 0.004, g: 0.002, b: 0.001))
        #expect(addedDuplicate == false)
        #expect(favorites.colors.count == 1)
        #expect(favorites.contains(RGBAColor(r: 0, g: 0, b: 0, a: 0.35)))
    }

    @Test
    func favouritesStoreOpaqueColours() {
        let favorites = ColorFavorites([RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 0.35)])
        #expect(favorites.colors.first?.a == 1)
    }

    @Test
    func moveForwardShiftsTheColoursItPasses() {
        let colors = (0..<4).map { RGBAColor(r: Double($0) / 10, g: 0, b: 0) }
        var favorites = ColorFavorites(colors)
        let moved = favorites.move(from: 0, to: 2)
        #expect(moved)
        #expect(favorites.colors == [colors[1], colors[2], colors[0], colors[3]])
    }

    @Test
    func swapTradesTwoSlotsAndKeepsTheLength() {
        let colors = (0..<4).map { RGBAColor(r: Double($0) / 10, g: 0, b: 0) }
        var favorites = ColorFavorites(colors)
        let swapped = favorites.swapAt(0, 3)
        #expect(swapped)
        #expect(favorites.colors == [colors[3], colors[1], colors[2], colors[0]])
        let sameSlot = favorites.swapAt(1, 1)
        let outOfRange = favorites.swapAt(0, 9)
        #expect(!sameSlot)
        #expect(!outOfRange)
    }

    @Test
    func moveBackwardShiftsTheColoursItPasses() {
        let colors = (0..<4).map { RGBAColor(r: Double($0) / 10, g: 0, b: 0) }
        var favorites = ColorFavorites(colors)
        let movedToMiddle = favorites.move(from: 3, to: 1)
        #expect(movedToMiddle)
        #expect(favorites.colors == [colors[0], colors[3], colors[1], colors[2]])
        let movedToFront = favorites.move(from: 2, to: 0)
        #expect(movedToFront)
        #expect(favorites.colors == [colors[1], colors[0], colors[3], colors[2]])
    }

    @Test
    func moveToTheSameSlotOrOutOfRangeChangesNothing() {
        let colors = (0..<3).map { RGBAColor(r: Double($0) / 10, g: 0, b: 0) }
        var favorites = ColorFavorites(colors)
        let sameSlot = favorites.move(from: 1, to: 1)
        let pastTheEnd = favorites.move(from: 0, to: 3)
        let negativeDestination = favorites.move(from: 2, to: -1)
        let negativeSource = favorites.move(from: -1, to: 0)
        #expect(sameSlot == false)
        #expect(pastTheEnd == false)
        #expect(negativeDestination == false)
        #expect(negativeSource == false)
        #expect(favorites.colors == colors)
    }
}

struct ColorRecentsTests {
    @Test
    func recordMovesAColourToTheFront() {
        var recents = ColorRecents([])
        recents.record(.black)
        recents.record(RGBAColor(r: 1, g: 0, b: 0))
        recents.record(.black)
        #expect(recents.colors.count == 2)
        #expect(recents.colors.first == .black)
    }

    @Test
    func recordKeepsOnlyTheLastEight() {
        var recents = ColorRecents([])
        for step in 0..<12 {
            recents.record(RGBAColor(r: Double(step) / 12, g: 0, b: 0))
        }
        #expect(recents.colors.count == 8)
        #expect(abs((recents.colors.first?.r ?? 0) - 11.0 / 12) < 0.001)
    }

    @Test
    func recentsAcceptTheOldSwatchListShape() throws {
        let data = try JSONEncoder().encode([RGBAColor.black, RGBAColor(r: 1, g: 0, b: 0)])
        let old = try JSONDecoder().decode([RGBAColor].self, from: data)
        let recents = ColorRecents(old)
        #expect(recents.colors.count == 2)
        #expect(recents.colors.first == .black)
    }
}
