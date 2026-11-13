import Foundation
import Testing
@testable import TextDocKit

@Suite("Text document history")
struct TextDocumentHistoryTests {
    private func document(_ title: String) -> TextDocument {
        TextDocument(title: title)
    }

    @Test("Structural snapshots undo and redo in order")
    func structuralUndoRedo() throws {
        let first = document("First")
        let second = document("Second")
        let third = document("Third")
        var history = TextDocumentHistory()
        history.recordStructural(first)
        history.recordStructural(second)

        #expect(history.canUndo)
        #expect(!history.canRedo)

        let undoSecondValue = history.undo(current: third)
        let undoSecond = try #require(undoSecondValue)
        #expect(undoSecond == second)
        #expect(history.canRedo)

        let undoFirstValue = history.undo(current: undoSecond)
        let undoFirst = try #require(undoFirstValue)
        #expect(undoFirst == first)
        #expect(!history.canUndo)

        let redoSecondValue = history.redo(current: undoFirst)
        let redoSecond = try #require(redoSecondValue)
        #expect(redoSecond == second)

        let redoThirdValue = history.redo(current: redoSecond)
        let redoThird = try #require(redoThirdValue)
        #expect(redoThird == third)
        #expect(!history.canRedo)
    }

    @Test("Typing coalesces until the idle interval passes")
    func typingCoalesces() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let firstRun = document("First run")
        let secondRun = document("Second run")
        var history = TextDocumentHistory(typingCoalescingInterval: 0.6)

        history.recordTyping(firstRun, at: start)
        #expect(history.undoStack.count == 1)

        // Continuous typing updates the run but adds no snapshot.
        history.recordTyping(firstRun, at: start.addingTimeInterval(0.2))
        history.recordTyping(firstRun, at: start.addingTimeInterval(0.7))
        #expect(history.undoStack.count == 1)

        // A pause longer than the interval starts a new step.
        history.recordTyping(secondRun, at: start.addingTimeInterval(1.4))
        #expect(history.undoStack.count == 2)
    }

    @Test("A focus change starts a new typing step")
    func focusChangeEndsTypingRun() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let firstRun = document("First run")
        let secondRun = document("Second run")
        var history = TextDocumentHistory(typingCoalescingInterval: 0.6)

        history.recordTyping(firstRun, at: start)
        history.endTypingRun()
        history.recordTyping(secondRun, at: start.addingTimeInterval(0.1))

        #expect(history.undoStack.count == 2)
    }

    @Test("A structural snapshot is not duplicated by the first keystroke")
    func structuralSnapshotIsNotDuplicatedByTyping() {
        let snapshot = document("Typed")
        let changed = TextDocument(
            title: "Typed",
            blocks: [TextBlock(kind: .paragraph(text: "x"))]
        )
        var history = TextDocumentHistory()
        history.recordStructural(snapshot)

        history.recordTyping(snapshot, at: Date())
        #expect(history.undoStack.count == 1)

        // The next keystroke is its own step, not part of the structural one.
        history.recordTyping(changed, at: Date().addingTimeInterval(0.05))
        #expect(history.undoStack.count == 2)
    }

    @Test("The stack is capped at the limit")
    func stackIsCapped() {
        var history = TextDocumentHistory(limit: 3)
        for index in 0..<5 {
            history.recordStructural(document("Doc \(index)"))
        }

        #expect(history.undoStack.count == 3)
        #expect(history.undoStack.map(\.title) == ["Doc 2", "Doc 3", "Doc 4"])
    }

    @Test("A new edit clears the redo stack")
    func newEditClearsRedo() {
        let first = document("First")
        let second = document("Second")
        var history = TextDocumentHistory()
        history.recordStructural(first)
        history.recordStructural(second)

        _ = history.undo(current: document("Current"))
        #expect(history.canRedo)

        history.recordStructural(document("New"))
        #expect(!history.canRedo)
    }
}
