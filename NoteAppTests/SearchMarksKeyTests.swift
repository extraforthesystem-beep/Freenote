import XCTest
@testable import NoteApp

/// The key the page's mark overlay refreshes on: the ink's length and last
/// stroke, not a copy of every stroke id.
@MainActor
final class SearchMarksKeyTests: XCTestCase {
    private let pageOne = UUID()
    private let pageThree = UUID()
    private let strokeID = UUID()
    private let highlight = SearchHighlight(query: "bread")

    private func key(strokeCount: Int, lastStrokeID: UUID?, pageID: UUID? = nil) -> SearchMarksKey {
        SearchMarksKey(
            highlight: highlight,
            pageID: pageID ?? pageOne,
            strokeCount: strokeCount,
            lastStrokeID: lastStrokeID,
            elements: []
        )
    }

    func testKeyIsStableForTheSameInk() {
        XCTAssertEqual(key(strokeCount: 4, lastStrokeID: strokeID), key(strokeCount: 4, lastStrokeID: strokeID))
    }

    func testKeyChangesWhenAStrokeIsAdded() {
        XCTAssertNotEqual(key(strokeCount: 4, lastStrokeID: strokeID), key(strokeCount: 5, lastStrokeID: strokeID))
    }

    func testKeyChangesWhenAStrokeIsErased() {
        XCTAssertNotEqual(key(strokeCount: 5, lastStrokeID: strokeID), key(strokeCount: 4, lastStrokeID: strokeID))
    }

    func testKeyChangesWhenTheLastStrokeChanges() {
        XCTAssertNotEqual(key(strokeCount: 4, lastStrokeID: strokeID), key(strokeCount: 4, lastStrokeID: UUID()))
    }

    func testKeyChangesWithThePage() {
        XCTAssertNotEqual(
            key(strokeCount: 4, lastStrokeID: strokeID),
            key(strokeCount: 4, lastStrokeID: strokeID, pageID: pageThree)
        )
    }
}
