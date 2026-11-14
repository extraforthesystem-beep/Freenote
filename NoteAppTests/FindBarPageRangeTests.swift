import SearchKit
import XCTest
@testable import NoteApp

/// The pages panel's page-range filter, applied before the hits are grouped.
@MainActor
final class FindBarPageRangeTests: XCTestCase {
    private let notebookID = UUID()

    private func hit(pageIndex: Int) -> SearchHit {
        SearchHit(
            id: UUID().uuidString,
            notebookID: notebookID,
            pageID: UUID(),
            pageIndex: pageIndex,
            source: .handwriting,
            snippet: "ink",
            matchedTermCount: 1
        )
    }

    func testNoRangeKeepsEveryHit() {
        let hits = [1, 2, 3, 4].map(hit)

        XCTAssertEqual(FindBarPageResult.filter(hits, pageRange: nil).map(\.pageIndex), [1, 2, 3, 4])
    }

    func testRangeKeepsOnlyItsPages() {
        let hits = [1, 2, 3, 4].map(hit)

        XCTAssertEqual(FindBarPageResult.filter(hits, pageRange: 2...3).map(\.pageIndex), [2, 3])
    }

    func testPageWithoutANumberIsAlwaysKept() {
        let hits = [0, 1, 2, 4].map(hit)

        XCTAssertEqual(FindBarPageResult.filter(hits, pageRange: 2...3).map(\.pageIndex), [0, 2])
    }
}
