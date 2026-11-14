import NoteCore
import Observation
import StudyKit
import XCTest
@testable import NoteApp

/// The memoised study values and the playhead's observable writes must not go
/// stale or notify their readers for a value that did not change.
@MainActor
final class StudyAudioPolishTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyAudioPolishTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Study model memoisation

    func testMemoisedStatesMatchAFreshComputationAfterEachMutation() async throws {
        let study = StudyModel(root: root)
        await study.load()
        XCTAssertEqual(study.allStates, freshStates(study))

        let createdFirst = await study.createSet(title: "First")
        let first = try XCTUnwrap(createdFirst)
        XCTAssertEqual(study.allStates, freshStates(study))

        var withCard = first
        withCard.cards.append(StudyCard(question: "Question", answer: "Answer"))
        let saved = await study.save(withCard)
        XCTAssertTrue(saved)
        XCTAssertEqual(study.allStates, freshStates(study))

        let cardID = withCard.cards[0].id
        study.record(.new(cardID: cardID, now: Date()), for: first.id)
        XCTAssertEqual(study.allStates, freshStates(study))

        let createdSecond = await study.createSet(title: "Second")
        let second = try XCTUnwrap(createdSecond)
        XCTAssertEqual(study.allStates, freshStates(study))

        await study.delete(second)
        XCTAssertEqual(study.allStates, freshStates(study))
        XCTAssertEqual(study.allStates, freshStates(study), "a second read must hit the cache")

        await study.load()
        XCTAssertEqual(study.allStates, freshStates(study))

        for set in study.sets {
            XCTAssertEqual(
                study.dueCountsBySet[set.id] ?? 0,
                StudyQueue.dueCount(in: [set], states: study.allStates, now: Date()),
                "per-set due counts must match a one-set computation"
            )
        }
        XCTAssertEqual(
            study.totalDueCount,
            study.dueCountsBySet.values.reduce(0, +)
        )
    }

    func testCorruptReviewStatesAreReportedAndSetAside() async throws {
        let bytes = Data("{\"sets\":{\"broken\"".utf8)
        let file = root.appendingPathComponent("review-states.json")
        try bytes.write(to: file)

        let study = StudyModel(root: root)
        await study.load()

        XCTAssertEqual(
            study.lastError,
            "Review progress could not be read; cards were rescheduled as new."
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        let quarantine = root.appendingPathComponent("quarantine", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: quarantine.path)
        let saved = try XCTUnwrap(names.first)
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(
            try Data(contentsOf: quarantine.appendingPathComponent(saved)),
            bytes
        )
    }

    // MARK: - Playhead observation

    func testUnchangedActiveStrokeDoesNotNotifyObservers() {
        let audio = NotebookAudio(
            store: LibraryStore(root: root),
            notebookID: UUID()
        )
        let strokeID = UUID()
        audio.publishActiveStroke(strokeID)

        let counter = NotificationCounter()
        withObservationTracking {
            _ = audio.activeStrokeID
        } onChange: {
            counter.value += 1
        }

        audio.publishActiveStroke(strokeID)
        XCTAssertEqual(counter.value, 0, "the same stroke must not notify the page")

        audio.publishActiveStroke(nil)
        XCTAssertEqual(counter.value, 1)

        audio.publishActiveStroke(nil)
        XCTAssertEqual(counter.value, 1, "a repeated nil must not notify either")
    }

    private func freshStates(_ study: StudyModel) -> [UUID: [UUID: ReviewState]] {
        var result: [UUID: [UUID: ReviewState]] = [:]
        for set in study.sets {
            result[set.id] = study.states(for: set.id)
        }
        return result
    }
}

private final class NotificationCounter: @unchecked Sendable {
    var value = 0
}
