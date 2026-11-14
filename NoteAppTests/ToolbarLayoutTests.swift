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
        XCTAssertEqual(
            ToolbarLayout.defaultStorage,
            "undo,redo,highlighter,eraser,lasso,elements,insert"
        )
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

    // MARK: - Undo and Redo

    func testUndoAndRedoLeadTheDefaults() {
        XCTAssertEqual(Array(ToolbarLayout.defaultItems.prefix(2)), [.undo, .redo])
        XCTAssertTrue(ToolbarLayout.defaultItems.contains(.undo))
        XCTAssertTrue(ToolbarLayout.defaultItems.contains(.redo))
        XCTAssertTrue(ToolbarLayout().hasHistoryItems)
        XCTAssertFalse(ToolbarLayout().available.contains(.undo))
        XCTAssertFalse(ToolbarLayout().available.contains(.redo))
    }

    func testToolItemsLeaveOutUndoAndRedo() {
        let layout = ToolbarLayout(items: [.undo, .redo, .highlighter, .eraser])
        XCTAssertEqual(layout.toolItems, [.highlighter, .eraser])
        XCTAssertTrue(layout.hasHistoryItems)
        XCTAssertFalse(ToolbarLayout(items: [.highlighter]).hasHistoryItems)
    }

    func testInsertHistoryItemsGoesFirstWithoutDuplicates() {
        var layout = ToolbarLayout(items: [.highlighter, .eraser])
        layout.insertHistoryItemsAtFront()
        XCTAssertEqual(layout.items, [.undo, .redo, .highlighter, .eraser])

        layout.insertHistoryItemsAtFront()
        XCTAssertEqual(layout.items, [.undo, .redo, .highlighter, .eraser])

        var partial = ToolbarLayout(items: [.highlighter, .undo])
        partial.insertHistoryItemsAtFront()
        XCTAssertEqual(partial.items, [.redo, .highlighter, .undo])
    }

    func testMigrationAddsUndoAndRedoToAnExistingLayout() {
        let defaults = makeDefaults()
        defaults.set("highlighter,eraser,lasso,elements,insert", forKey: ToolbarLayout.storageKey)

        XCTAssertTrue(ToolbarLayout.migrateUndoRedoIfNeeded(in: defaults))
        XCTAssertEqual(
            defaults.string(forKey: ToolbarLayout.storageKey),
            "undo,redo,highlighter,eraser,lasso,elements,insert"
        )
        XCTAssertTrue(defaults.bool(forKey: ToolbarLayout.undoRedoMigrationKey))
    }

    func testMigrationRunsOnceAndRespectsLaterRemoval() {
        let defaults = makeDefaults()
        defaults.set("highlighter,eraser", forKey: ToolbarLayout.storageKey)
        XCTAssertTrue(ToolbarLayout.migrateUndoRedoIfNeeded(in: defaults))

        // The user removes Undo and Redo in Customise Toolbar.
        defaults.set("highlighter,eraser", forKey: ToolbarLayout.storageKey)
        XCTAssertFalse(ToolbarLayout.migrateUndoRedoIfNeeded(in: defaults))
        XCTAssertEqual(defaults.string(forKey: ToolbarLayout.storageKey), "highlighter,eraser")
    }

    func testMigrationLeavesALayoutThatAlreadyHasAHistoryControl() {
        let defaults = makeDefaults()
        defaults.set("redo,highlighter,eraser", forKey: ToolbarLayout.storageKey)

        XCTAssertFalse(ToolbarLayout.migrateUndoRedoIfNeeded(in: defaults))
        XCTAssertEqual(defaults.string(forKey: ToolbarLayout.storageKey), "redo,highlighter,eraser")
    }

    func testMigrationWithoutAStoredLayoutWritesNothingButRecordsTheRun() {
        let defaults = makeDefaults()

        XCTAssertFalse(ToolbarLayout.migrateUndoRedoIfNeeded(in: defaults))
        XCTAssertNil(defaults.string(forKey: ToolbarLayout.storageKey))
        XCTAssertTrue(defaults.bool(forKey: ToolbarLayout.undoRedoMigrationKey))
    }

    func testMigrationAddsUndoAndRedoToAPenOnlyLayout() {
        // An explicitly emptied toolbar still gets the history controls once:
        // they were never offered when the layout was emptied.
        let defaults = makeDefaults()
        defaults.set("", forKey: ToolbarLayout.storageKey)

        XCTAssertTrue(ToolbarLayout.migrateUndoRedoIfNeeded(in: defaults))
        XCTAssertEqual(defaults.string(forKey: ToolbarLayout.storageKey), "undo,redo")
    }

    // MARK: - Titles and symbols

    func testEveryItemHasATitleAndSymbol() {
        for item in ToolbarItemID.allCases {
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.systemImage.isEmpty)
        }
    }

    func testSelectObjectsKeepsItsStorageIDAndReadsAsASelection() {
        XCTAssertEqual(ToolbarItemID.elements.rawValue, "elements")
        XCTAssertEqual(ToolbarItemID.elements.title, "Select Objects")
        XCTAssertEqual(ToolbarItemID.elements.systemImage, "rectangle.and.hand.point.up.left")
        XCTAssertEqual(ToolbarLayout(storage: "elements").items, [.elements])
    }

    private func makeDefaults() -> UserDefaults {
        let name = "ToolbarLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        // Only the suite name crosses into the teardown block: UserDefaults
        // itself is not Sendable.
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return defaults
    }
}
