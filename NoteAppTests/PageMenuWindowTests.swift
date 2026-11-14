import XCTest
@testable import NoteApp

@MainActor
final class PageMenuWindowTests: XCTestCase {
    private let radius = 3

    /// The menu lists a window, not the notebook: sorted, unique, in range and
    /// always containing the current page.
    func testWindowIsAValidPageList() {
        for count in 0...12 {
            for current in 0..<count {
                let window = pageMenuWindow(current: current, count: count, radius: radius)
                XCTAssertEqual(window, window.sorted(), "count \(count), current \(current)")
                XCTAssertEqual(Set(window).count, window.count, "count \(count), current \(current)")
                XCTAssertTrue(window.contains(current), "count \(count), current \(current)")
                XCTAssertTrue(
                    window.allSatisfy { (0..<count).contains($0) },
                    "count \(count), current \(current)"
                )
                XCTAssertLessThanOrEqual(
                    window.count,
                    2 * radius + 1,
                    "count \(count), current \(current)"
                )
            }
        }
    }

    func testEmptyNotebookHasNoWindow() {
        XCTAssertEqual(pageMenuWindow(current: 0, count: 0), [])
    }

    func testWindowIsClampedAtTheEnds() {
        XCTAssertEqual(pageMenuWindow(current: 0, count: 10), [0, 1, 2, 3])
        XCTAssertEqual(pageMenuWindow(current: 4, count: 10), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(pageMenuWindow(current: 9, count: 10), [6, 7, 8, 9])
    }

    func testShortNotebookListsEveryPage() {
        XCTAssertEqual(pageMenuWindow(current: 1, count: 3), [0, 1, 2])
    }

    func testLargeNotebookStaysSmall() {
        for current in [0, 1, 2_500, 4_998, 4_999] {
            let window = pageMenuWindow(current: current, count: 5_000)
            XCTAssertLessThanOrEqual(window.count, 9, "current \(current)")
            XCTAssertTrue(window.contains(current))
        }
    }

    func testInvalidCurrentHasNoWindow() {
        XCTAssertEqual(pageMenuWindow(current: -1, count: 10), [])
        XCTAssertEqual(pageMenuWindow(current: 10, count: 10), [])
    }
}
