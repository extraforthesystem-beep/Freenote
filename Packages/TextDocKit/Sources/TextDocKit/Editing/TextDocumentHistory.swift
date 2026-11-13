import Foundation

/// A bounded undo/redo stack of whole-document snapshots for the block editor.
///
/// Structural edits are recorded one step at a time. Typing is coalesced into
/// one step per idle gap, so holding down a key does not fill the stack with a
/// snapshot per character. The editor calls ``endTypingRun()`` when focus moves
/// to another block, which starts a new typing step even inside the gap.
public struct TextDocumentHistory: Sendable {
    /// The number of snapshots kept in each direction.
    public static let defaultLimit = 50
    /// How long typing has to pause before the next keystroke starts a new step.
    public static let defaultTypingCoalescingInterval: TimeInterval = 0.6

    /// Snapshots older than the current document, oldest first.
    public private(set) var undoStack: [TextDocument] = []
    /// Snapshots undone from the current document, oldest first.
    public private(set) var redoStack: [TextDocument] = []

    /// The most snapshots kept in each direction.
    public let limit: Int
    /// The idle gap that separates two typing steps.
    public let typingCoalescingInterval: TimeInterval

    private var lastTypingAt: Date?

    /// Creates an empty history.
    public init(
        limit: Int = TextDocumentHistory.defaultLimit,
        typingCoalescingInterval: TimeInterval = TextDocumentHistory.defaultTypingCoalescingInterval
    ) {
        self.limit = max(limit, 1)
        self.typingCoalescingInterval = max(typingCoalescingInterval, 0)
    }

    /// True when ``undo(current:)`` has a snapshot to restore.
    public var canUndo: Bool { !undoStack.isEmpty }

    /// True when ``redo(current:)`` has a snapshot to restore.
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Records the document as it was before a discrete edit such as an insert,
    /// delete, move, split, merge, conversion or checklist toggle.
    public mutating func recordStructural(_ snapshot: TextDocument) {
        guard undoStack.last != snapshot else {
            redoStack.removeAll()
            lastTypingAt = nil
            return
        }
        Self.append(snapshot, to: &undoStack, limit: limit)
        redoStack.removeAll()
        lastTypingAt = nil
    }

    /// Records the document as it was before a keystroke, at most once per
    /// ``typingCoalescingInterval`` of continuous typing.
    public mutating func recordTyping(_ snapshot: TextDocument, at date: Date = Date()) {
        // A structural edit already captured this exact state. Start a new run
        // so the next keystroke becomes its own undo step.
        guard undoStack.last != snapshot else {
            lastTypingAt = nil
            redoStack.removeAll()
            return
        }
        if let lastTypingAt,
           date.timeIntervalSince(lastTypingAt) < typingCoalescingInterval {
            self.lastTypingAt = date
            return
        }
        Self.append(snapshot, to: &undoStack, limit: limit)
        redoStack.removeAll()
        lastTypingAt = date
    }

    /// Ends the current typing run, so the next keystroke records a new step.
    public mutating func endTypingRun() {
        lastTypingAt = nil
    }

    /// Replaces `current` with the newest undo snapshot and returns it, or
    /// returns `nil` when there is nothing to undo.
    public mutating func undo(current: TextDocument) -> TextDocument? {
        guard let snapshot = undoStack.popLast() else { return nil }
        Self.append(current, to: &redoStack, limit: limit)
        lastTypingAt = nil
        return snapshot
    }

    /// Replaces `current` with the newest redo snapshot and returns it, or
    /// returns `nil` when there is nothing to redo.
    public mutating func redo(current: TextDocument) -> TextDocument? {
        guard let snapshot = redoStack.popLast() else { return nil }
        Self.append(current, to: &undoStack, limit: limit)
        lastTypingAt = nil
        return snapshot
    }

    /// Forgets every snapshot.
    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastTypingAt = nil
    }

    private static func append(
        _ snapshot: TextDocument,
        to stack: inout [TextDocument],
        limit: Int
    ) {
        stack.append(snapshot)
        if stack.count > limit {
            stack.removeFirst(stack.count - limit)
        }
    }
}
