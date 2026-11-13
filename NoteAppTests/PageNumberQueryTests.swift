import XCTest
@testable import NoteApp

final class PageNumberQueryTests: XCTestCase {
    func testPlainNumber() {
        XCTAssertEqual(PageNumberQuery.page(in: "12", pageCount: 20), 12)
    }

    func testShortPrefix() {
        XCTAssertEqual(PageNumberQuery.page(in: "p12", pageCount: 20), 12)
    }

    func testDottedPrefix() {
        XCTAssertEqual(PageNumberQuery.page(in: "p.12", pageCount: 20), 12)
    }

    func testPageWord() {
        XCTAssertEqual(PageNumberQuery.page(in: "Page 3", pageCount: 20), 3)
    }

    func testShortWord() {
        XCTAssertEqual(PageNumberQuery.page(in: "pg 7", pageCount: 20), 7)
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(PageNumberQuery.page(in: " 7 ", pageCount: 10), 7)
    }

    func testZeroIsNotAPage() {
        XCTAssertNil(PageNumberQuery.page(in: "0", pageCount: 10))
    }

    func testPagePastTheEndIsRejected() {
        XCTAssertNil(PageNumberQuery.page(in: "99", pageCount: 10))
    }

    func testOtherWordsAreRejected() {
        XCTAssertNil(PageNumberQuery.page(in: "abc", pageCount: 10))
    }

    func testTrailingLettersAreRejected() {
        XCTAssertNil(PageNumberQuery.page(in: "12a", pageCount: 10))
    }

    func testEmptyQueryIsRejected() {
        XCTAssertNil(PageNumberQuery.page(in: "", pageCount: 10))
        XCTAssertNil(PageNumberQuery.page(in: "   ", pageCount: 10))
    }
}
