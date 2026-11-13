import XCTest
@testable import NoteApp

final class ToolbarLayoutTests: XCTestCase {
    func testUnusableStorageFallsBackToDefaults() {
        XCTAssertEqual(ToolbarLayout(storage: " , ").items, ToolbarLayout.defaultItems)
        XCTAssertEqual(ToolbarLayout(storage: "notAnItem").items, ToolbarLayout.defaultItems)
    }

    func testEmptyStorageIsPenOnlyAndRoundTrips() {
        XCTAssertTrue(ToolbarLayout(storage: "").items.isEmpty)
        XCTAssertEqual(ToolbarLayout(storage: ToolbarLayout(items: []).storage).items, [])
    }

    func testUnknownAndDuplicateIDsAreDropped() {
        let layout = ToolbarLayout(storage: "eraser,unknown,eraser,search,notAnItem,search")
        XCTAssertEqual(layout.items, [.eraser, .search])
    }

    func testOnlyUnknownIDsFallBackToDefaults() {
        XCTAssertEqual(ToolbarLayout(storage: "nope,alsoNope").items, ToolbarLayout.defaultItems)
    }

    func testStorageRoundTrip() {
        let layout = ToolbarLayout(items: [.laser, .stickyNote, .addPage])
        XCTAssertEqual(layout.storage, "laser,stickyNote,addPage")
        XCTAssertEqual(ToolbarLayout(storage: layout.storage).items, layout.items)
    }

    func testDefaultStorageRoundTrip() {
        XCTAssertEqual(ToolbarLayout(storage: ToolbarLayout.defaultStorage).items, ToolbarLayout.defaultItems)
        XCTAssertEqual(ToolbarLayout.defaultStorage, "highlighter,eraser,lasso,elements,insert")
    }

    func testMoveKeepsOrder() {
        var layout = ToolbarLayout(items: [.highlighter, .eraser, .lasso])
        layout.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(layout.items, [.lasso, .highlighter, .eraser])

        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(layout.items, [.highlighter, .eraser, .lasso])
    }

    func testRemoveAndAdd() {
        var layout = ToolbarLayout(items: [.highlighter, .eraser])
        layout.remove(.highlighter)
        XCTAssertEqual(layout.items, [.eraser])
        layout.remove(.eraser)
        XCTAssertTrue(layout.items.isEmpty)

        layout.add(.search)
        layout.add(.search)
        XCTAssertEqual(layout.items, [.search])
    }

    func testRemoveAtOffsets() {
        var layout = ToolbarLayout(items: [.highlighter, .eraser, .lasso, .elements])
        layout.remove(atOffsets: IndexSet([1, 3]))
        XCTAssertEqual(layout.items, [.highlighter, .lasso])
    }

    func testReset() {
        var layout = ToolbarLayout(items: [.laser, .search])
        XCTAssertFalse(layout.isDefault)
        layout.reset()
        XCTAssertEqual(layout.items, ToolbarLayout.defaultItems)
        XCTAssertTrue(layout.isDefault)
    }

    func testAvailableExcludesShownItems() {
        let layout = ToolbarLayout(items: [.highlighter, .search, .laser])
        XCTAssertFalse(layout.available.contains(.highlighter))
        XCTAssertFalse(layout.available.contains(.search))
        XCTAssertFalse(layout.available.contains(.laser))
        XCTAssertEqual(layout.available.count, ToolbarItemID.allCases.count - 3)
        // Declaration order is kept.
        let available = ToolbarLayout(items: []).available
        XCTAssertEqual(available, ToolbarItemID.allCases)
    }

    func testUndoAndRedoAreOptIn() {
        XCTAssertFalse(ToolbarLayout.defaultItems.contains(.undo))
        XCTAssertFalse(ToolbarLayout.defaultItems.contains(.redo))
        XCTAssertTrue(ToolbarLayout().available.contains(.undo))
        XCTAssertTrue(ToolbarLayout().available.contains(.redo))
    }

    func testEveryItemHasATitleAndSymbol() {
        for item in ToolbarItemID.allCases {
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.systemImage.isEmpty)
        }
    }
}
