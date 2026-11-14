import XCTest
@testable import NoteApp

/// The paper pre-render queue: one at a time, one draw per key, and a page
/// that left never draws. The queue is tested without a renderer.
final class PagePrewarmQueueTests: XCTestCase {
    /// Runs the queue the way `PagesView` does, recording what drew.
    private func run(_ queue: inout PagePrewarmQueue) -> [String] {
        var drawn: [String] = []
        while let key = queue.start() {
            drawn.append(key)
            queue.finish(key)
        }
        return drawn
    }

    func testKeyEnqueuedTwiceRunsOnce() {
        var queue = PagePrewarmQueue()
        XCTAssertTrue(queue.enqueue("a"))
        XCTAssertFalse(queue.enqueue("a"))
        XCTAssertEqual(run(&queue), ["a"])
    }

    func testKeyEnqueuedWhileDrawingDoesNotRunAgain() {
        var queue = PagePrewarmQueue()
        queue.enqueue("a")
        XCTAssertEqual(queue.start(), "a")
        XCTAssertEqual(queue.running, "a")

        XCTAssertFalse(queue.enqueue("a"), "a draw in flight is not queued again")
        queue.finish("a")
        XCTAssertNil(queue.start(), "the key already drew")
    }

    func testOneDrawAtATime() {
        var queue = PagePrewarmQueue()
        queue.enqueue("a")
        queue.enqueue("b")

        XCTAssertEqual(queue.start(), "a")
        XCTAssertNil(queue.start(), "b waits for a")
        XCTAssertEqual(queue.start(), nil)
        queue.finish("a")
        XCTAssertEqual(queue.start(), "b")
        queue.finish("b")
        XCTAssertTrue(queue.isIdle)
    }

    func testDroppedKeyNeverRuns() {
        var queue = PagePrewarmQueue()
        queue.enqueue("a")
        queue.enqueue("b")

        XCTAssertTrue(queue.drop("a"))
        XCTAssertFalse(queue.contains("a"))
        XCTAssertEqual(run(&queue), ["b"], "a dropped key never draws")
    }

    func testDrawingKeyIsNotDropped() {
        var queue = PagePrewarmQueue()
        queue.enqueue("a")
        XCTAssertEqual(queue.start(), "a")

        XCTAssertFalse(queue.drop("a"), "a draw already underway finishes")
        XCTAssertEqual(queue.running, "a")
    }

    func testFinishedKeyCanBeQueuedAgain() {
        var queue = PagePrewarmQueue()
        queue.enqueue("a")
        queue.finish(queue.start()!)

        XCTAssertTrue(queue.enqueue("a"), "a page that left and came back renders again")
        XCTAssertEqual(run(&queue), ["a"])
    }

    func testWaitingKeysKeepsEnqueueOrder() {
        var queue = PagePrewarmQueue()
        queue.enqueue("a")
        queue.enqueue("b")
        queue.enqueue("c")

        XCTAssertEqual(queue.waitingKeys, ["a", "b", "c"])
    }
}
