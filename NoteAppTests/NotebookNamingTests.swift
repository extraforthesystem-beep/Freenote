import XCTest
@testable import NoteApp

/// The default name of a new notebook, and the numbering of same-day ones.
final class NotebookNamingTests: XCTestCase {
    private let british = Locale(identifier: "en_GB")
    private let american = Locale(identifier: "en_US")

    /// Noon on a given day, so the test does not depend on the time zone or on
    /// a daylight-saving edge.
    private func date(day: Int = 14, month: Int = 11, year: Int = 2024) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    func testFirstNotebookOfTheDayIsNamedAfterIt() {
        XCTAssertEqual(
            NotebookNaming.defaultNotebookTitle(for: date(), existing: [], locale: british),
            "Notes 14 Nov"
        )
    }

    func testTitleFollowsTheLocaleDayAndMonthOrder() {
        XCTAssertEqual(
            NotebookNaming.defaultNotebookTitle(for: date(), existing: [], locale: american),
            "Notes Nov 14"
        )
    }

    func testSameDayNotebooksAreNumbered() {
        let base = "Notes 14 Nov"
        XCTAssertEqual(
            NotebookNaming.defaultNotebookTitle(for: date(), existing: [base], locale: british),
            "Notes 14 Nov 2"
        )
        XCTAssertEqual(
            NotebookNaming.defaultNotebookTitle(
                for: date(),
                existing: [base, "Notes 14 Nov 2"],
                locale: british
            ),
            "Notes 14 Nov 3"
        )
    }

    func testAFreeNumberIsReused() {
        XCTAssertEqual(
            NotebookNaming.defaultNotebookTitle(
                for: date(),
                existing: ["Notes 14 Nov", "Notes 14 Nov 3"],
                locale: british
            ),
            "Notes 14 Nov 2"
        )
    }

    func testAnotherDaysNotebookDoesNotAffectTheName() {
        XCTAssertEqual(
            NotebookNaming.defaultNotebookTitle(
                for: date(),
                existing: ["Notes 13 Nov", "Untitled Notebook"],
                locale: british
            ),
            "Notes 14 Nov"
        )
    }
}
