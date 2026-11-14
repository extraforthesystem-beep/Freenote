import XCTest
@testable import InkKit

#if os(iOS)
/// The toolbar's Undo/Redo items disable themselves from the controller's
/// published `canUndo`/`canRedo`, so those have to follow the canvas's own
/// undo manager without anyone reading it.
@MainActor
final class PencilCanvasControllerTests: XCTestCase {
    func testUndoAvailabilityFollowsTheUndoManager() async throws {
        let controller = PencilCanvasController()
        let canvas = InkCanvasView()
        controller.canvas = canvas
        XCTAssertFalse(controller.canUndo)
        XCTAssertFalse(controller.canRedo)

        let undoManager = try XCTUnwrap(canvas.undoManager)
        undoManager.beginUndoGrouping()
        Self.registerReversibleStep(on: undoManager, target: canvas)
        undoManager.endUndoGrouping()
        // The observation is delivered on the main queue.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.canUndo)
        XCTAssertFalse(controller.canRedo)

        controller.undo()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.canRedo)

        controller.redo()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.canUndo)
        XCTAssertFalse(controller.canRedo)
    }

    /// A step whose undo registers its redo, the way PencilKit's own steps do;
    /// an undo action that registers nothing leaves nothing to redo.
    private static func registerReversibleStep(on manager: UndoManager, target: InkCanvasView) {
        manager.registerUndo(withTarget: target) { target in
            registerReversibleStep(on: manager, target: target)
        }
    }

    func testOneCanvasReplacingAnotherRefreshesAvailability() async throws {
        let controller = PencilCanvasController()
        let first = InkCanvasView()
        controller.canvas = first
        let manager = try XCTUnwrap(first.undoManager)
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: first) { _ in }
        manager.endUndoGrouping()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.canUndo)

        // A new page gets a new canvas with an empty stack.
        controller.canvas = InkCanvasView()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(controller.canUndo)
        XCTAssertFalse(controller.canRedo)
    }
}
#endif
