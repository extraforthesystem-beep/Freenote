import Foundation
import StudyKit
import Testing

@Suite("SM-2 scheduler")
struct SpacedRepetitionSchedulerTests {
    private let scheduler = SpacedRepetitionScheduler()

    @Test func newStateIsDueImmediatelyAtInitialEase() {
        let cardID = UUID()
        let state = ReviewState.new(cardID: cardID, now: testNow)

        #expect(state.cardID == cardID)
        #expect(state.easeFactor == 2.5)
        #expect(state.intervalDays == 0)
        #expect(state.repetitions == 0)
        #expect(state.dueDate == testNow)
        #expect(state.lastReviewedAt == nil)
        #expect(state.lapses == 0)
    }

    @Test(arguments: [0, 1, 2])
    func failingGradeResetsScheduleAndAddsLapse(quality: Int) {
        let state = ReviewState(
            cardID: UUID(),
            easeFactor: 2.5,
            intervalDays: 18,
            repetitions: 5,
            dueDate: testNow.addingTimeInterval(-86_400),
            lastReviewedAt: testNow.addingTimeInterval(-86_400),
            lapses: 2
        )

        let reviewed = scheduler.review(state: state, quality: quality, now: testNow)

        #expect(reviewed.repetitions == 0)
        #expect(reviewed.intervalDays == 1)
        #expect(reviewed.lapses == 3)
        #expect(abs(reviewed.easeFactor - 2.3) < 1e-12)
        #expect(reviewed.dueDate == testNow.addingTimeInterval(86_400))
        #expect(reviewed.lastReviewedAt == testNow)
    }

    @Test func failingGradeNeverDropsEaseBelowOnePointThree() {
        var state = ReviewState(
            cardID: UUID(),
            easeFactor: 1.35,
            intervalDays: 4,
            repetitions: 2,
            dueDate: testNow,
            lastReviewedAt: testNow,
            lapses: 0
        )

        state = scheduler.review(state: state, quality: 0, now: testNow)
        #expect(abs(state.easeFactor - 1.3) < 1e-12)

        state = scheduler.review(state: state, quality: 0, now: testNow)
        #expect(abs(state.easeFactor - 1.3) < 1e-12)
        #expect(state.lapses == 2)
    }

    @Test(arguments: [3, 4, 5])
    func passingGradeStartsTheOneDayInterval(quality: Int) {
        let reviewed = scheduler.review(
            state: .new(cardID: UUID(), now: testNow),
            quality: quality,
            now: testNow
        )

        #expect(reviewed.repetitions == 1)
        #expect(reviewed.intervalDays == 1)
        #expect(reviewed.lapses == 0)
        #expect(reviewed.dueDate == testNow.addingTimeInterval(86_400))
        #expect(reviewed.lastReviewedAt == testNow)

        let expectedEase: Double = switch quality {
        case 3: 2.36
        case 4: 2.5
        default: 2.6
        }
        #expect(abs(reviewed.easeFactor - expectedEase) < 1e-12)
    }

    @Test func secondSuccessUsesSixDays() {
        var state = ReviewState.new(cardID: UUID(), now: testNow)
        state = scheduler.review(state: state, quality: 5, now: testNow)
        state = scheduler.review(state: state, quality: 5, now: testNow)

        #expect(state.repetitions == 2)
        #expect(state.intervalDays == 6)
        #expect(state.dueDate == testNow.addingTimeInterval(6 * 86_400))
    }

    @Test func laterSuccessesMultiplyThePreviousIntervalByThePreviousEase() {
        var state = ReviewState.new(cardID: UUID(), now: testNow)

        state = scheduler.review(state: state, quality: 5, now: testNow)
        #expect(state.intervalDays == 1)
        #expect(abs(state.easeFactor - 2.6) < 1e-12)

        state = scheduler.review(state: state, quality: 5, now: testNow)
        #expect(state.intervalDays == 6)
        #expect(abs(state.easeFactor - 2.7) < 1e-12)

        // 6 × 2.7 = 16.2, rounded with the ease from before this review.
        state = scheduler.review(state: state, quality: 5, now: testNow)
        #expect(state.intervalDays == 16)
        #expect(abs(state.easeFactor - 2.8) < 1e-12)

        // 16 × 2.8 = 44.8, rounded to 45.
        state = scheduler.review(state: state, quality: 5, now: testNow)
        #expect(state.intervalDays == 45)
        #expect(abs(state.easeFactor - 2.9) < 1e-12)
    }

    @Test func easeAdjustmentMatchesTheStandardFormula() {
        let expected: [Int: Double] = [
            3: 2.36,
            4: 2.5,
            5: 2.6,
        ]

        for quality in 3...5 {
            let reviewed = scheduler.review(
                state: .new(cardID: UUID(), now: testNow),
                quality: quality,
                now: testNow
            )
            #expect(abs(reviewed.easeFactor - (expected[quality] ?? 0)) < 1e-12)
        }
    }

    @Test func repeatedFailuresWalkEaseDownToTheFloor() {
        var state = ReviewState.new(cardID: UUID(), now: testNow)
        let expected = [2.3, 2.1, 1.9, 1.7, 1.5, 1.3, 1.3]

        for value in expected {
            state = scheduler.review(state: state, quality: 1, now: testNow)
            #expect(abs(state.easeFactor - value) < 1e-12)
        }
    }

    @Test func qualitiesOutsideZeroToFiveAreClamped() {
        let high = scheduler.review(
            state: .new(cardID: UUID(), now: testNow),
            quality: 99,
            now: testNow
        )
        #expect(high.repetitions == 1)
        #expect(high.lapses == 0)
        #expect(abs(high.easeFactor - 2.6) < 1e-12)

        let low = scheduler.review(
            state: .new(cardID: UUID(), now: testNow),
            quality: -7,
            now: testNow
        )
        #expect(low.repetitions == 0)
        #expect(low.intervalDays == 1)
        #expect(low.lapses == 1)
        #expect(abs(low.easeFactor - 2.3) < 1e-12)
    }

    @Test func dueCardsAreDeterministicAndOrderedByDueDate() {
        let set = makeSet(cardCount: 4)
        let states: [UUID: ReviewState] = [
            set.cards[0].id: ReviewState(
                cardID: set.cards[0].id,
                dueDate: testNow.addingTimeInterval(-100)
            ),
            set.cards[1].id: ReviewState(
                cardID: set.cards[1].id,
                dueDate: testNow.addingTimeInterval(100)
            ),
            // Card 2 has no state, so it is new and due at `now`.
            set.cards[3].id: ReviewState(
                cardID: set.cards[3].id,
                dueDate: testNow.addingTimeInterval(-200)
            ),
        ]

        let engine = SpacedRepetitionScheduler(states: states)
        let first = engine.dueCards(in: set, now: testNow)
        let second = engine.dueCards(in: set, now: testNow)

        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.id) == [set.cards[3].id, set.cards[0].id, set.cards[2].id])
    }

    @Test func cardDueExactlyNowIsIncluded() {
        let set = makeSet(cardCount: 1)
        let state = ReviewState(cardID: set.cards[0].id, dueDate: testNow)

        let due = SpacedRepetitionScheduler(states: [state.cardID: state])
            .dueCards(in: set, now: testNow)

        #expect(due.map(\.id) == [set.cards[0].id])
    }

    @Test func missingStateIsReportedAsANewDueState() {
        let card = makeCard(1)
        let engine = SpacedRepetitionScheduler()
        let state = engine.state(for: card.id, now: testNow)

        #expect(state.dueDate == testNow)
        #expect(state.easeFactor == 2.5)
        #expect(state.repetitions == 0)
    }
}
