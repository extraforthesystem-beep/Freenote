import SearchKit
import XCTest
@testable import NoteApp

/// The result list's grouping, its titles and its VoiceOver label.
@MainActor
final class FindBarResultsTests: XCTestCase {
    private let notebookID = UUID()
    private let pageOne = UUID()
    private let pageThree = UUID()

    private func hit(pageID: UUID, pageIndex: Int, snippet: String, source: PageTextSource = .handwriting) -> SearchHit {
        SearchHit(
            id: "\(pageID.uuidString):\(source.rawValue)",
            notebookID: notebookID,
            pageID: pageID,
            pageIndex: pageIndex,
            source: source,
            snippet: snippet,
            matchedTermCount: 1
        )
    }

    // MARK: Grouping

    func testOneRowPerPageInPageOrder() {
        let hits = [
            hit(pageID: pageThree, pageIndex: 3, snippet: "third page"),
            hit(pageID: pageOne, pageIndex: 1, snippet: "first page"),
            hit(pageID: pageThree, pageIndex: 3, snippet: "third page again"),
        ]

        let rows = FindBarPageResult.group(hits)

        XCTAssertEqual(rows.map(\.pageIndex), [1, 3])
        XCTAssertEqual(rows.map(\.pageID), [pageOne, pageThree])
        XCTAssertEqual(rows.last?.hits.count, 2)
    }

    func testRowIsTitledByItsOneBasedPage() {
        let rows = FindBarPageResult.group([hit(pageID: pageThree, pageIndex: 3, snippet: "ink")])
        XCTAssertEqual(rows.first?.title, "Page 3")
    }

    func testPageWithoutANumberIsJustPage() {
        let rows = FindBarPageResult.group([hit(pageID: pageOne, pageIndex: 0, snippet: "ink")])
        XCTAssertEqual(rows.first?.title, "Page")
    }

    func testNoHitsMakeNoRows() {
        XCTAssertTrue(FindBarPageResult.group([]).isEmpty)
    }

    // MARK: VoiceOver

    func testRowLabelNamesPageSnippetAndMatchCount() {
        let rows = FindBarPageResult.group([
            hit(pageID: pageThree, pageIndex: 3, snippet: "quarterly report"),
            hit(pageID: pageThree, pageIndex: 3, snippet: "quarterly figures", source: .typedText),
        ])

        XCTAssertEqual(rows.first?.accessibilityLabel, "Page 3, “quarterly report”, 2 matches")
    }

    func testSingleMatchRowOmitsTheCount() {
        let rows = FindBarPageResult.group([hit(pageID: pageOne, pageIndex: 1, snippet: "bread")])

        XCTAssertEqual(rows.first?.accessibilityLabel, "Page 1, “bread”")
    }
}
