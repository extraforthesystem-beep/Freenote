import Foundation
import StudyKit
import Testing

@Suite("FSRS scheduler")
struct FSRSSchedulerTests {
    private let scheduler = FSRSScheduler()
    private let weights = FSRSScheduler.defaultWeights

    @Test func firstReviewStartsFromTheGradesInitialStability() {
        let expected: [(quality: Int, weight: Double)] = [
            (1, weights[0]),
            (3, weights[1]),
            (4, weights[2]),
            (5, weights[3]),
        ]

        for (quality, weight) in expected {
            let reviewed = scheduler.review(
                state: .new(cardID: UUID(), now: testNow),
                quality: quality,
                now: testNow
            )

            #expect(abs((reviewed.stability ?? 0) - weight) < 1e-12)
            #expect(reviewed.difficulty != nil)
            #expect(reviewed.lastReviewedAt == testNow)
            #expect(reviewed.dueDate == testNow.addingTimeInterval(Double(reviewed.intervalDays) * 86_400))
        }
    }

    @Test func aGoodFirstReviewIsDueInThreeDays() {
        let reviewed = scheduler.review(
            state: .new(cardID: UUID(), now: testNow),
            quality: 4,
            now: testNow
        )

        #expect(reviewed.intervalDays == 3)
        #expect(reviewed.dueDate == testNow.addingTimeInterval(3 * 86_400))
        #expect(reviewed.repetitions == 1)
        #expect(reviewed.lapses == 0)
        #expect(reviewed.isLeech == false)
    }

    @Test func easyBeatsHardAndGoodOutOfTheSameState() {
        let state = ReviewState(
            cardID: UUID(),
            easeFactor: 2.5,
            intervalDays: 10,
            repetitions: 3,
            dueDate: testNow,
            lastReviewedAt: testNow.addingTimeInterval(-10 * 86_400),
            lapses: 0,
            stability: 10,
            difficulty: 5
        )

        let hard = scheduler.review(state: state, quality: 3, now: testNow)
        let good = scheduler.review(state: state, quality: 4, now: testNow)
        let easy = scheduler.review(state: state, quality: 5, now: testNow)

        #expect(hard.intervalDays < good.intervalDays)
        #expect(good.intervalDays < easy.intervalDays)
        #expect(hard.difficulty ?? 0 > good.difficulty ?? 0)
        #expect(good.difficulty ?? 0 > easy.difficulty ?? 0)
    }

    @Test func laterSuccessGrowsTheIntervalPastTheFirstOne() {
        var state = ReviewState.new(cardID: UUID(), now: testNow)
        state = scheduler.review(state: state, quality: 4, now: testNow)
        let firstInterval = state.intervalDays

        let second = scheduler.review(
            state: state,
            quality: 4,
            now: state.dueDate
        )

        #expect(second.intervalDays > firstInterval)
        #expect((second.stability ?? 0) > (state.stability ?? 0))
        #expect(second.repetitions == 2)
    }

    @Test func aFailureNeverLengthensTheInterval() {
        let state = ReviewState(
            cardID: UUID(),
            intervalDays: 50,
            repetitions: 6,
            dueDate: testNow.addingTimeInterval(-60 * 86_400),
            lastReviewedAt: testNow.addingTimeInterval(-110 * 86_400),
            lapses: 2,
            stability: 50,
            difficulty: 5
        )

        let reviewed = scheduler.review(state: state, quality: 1, now: testNow)

        #expect((reviewed.stability ?? .infinity) <= 50)
        #expect(reviewed.intervalDays <= 50)
        #expect(reviewed.intervalDays >= 1)
        #expect(reviewed.lapses == 3)
        #expect(reviewed.repetitions == 0)
    }

    @Test func aForgottenCardLosesStabilityAndGainsALapse() {
        let state = ReviewState(
            cardID: UUID(),
            intervalDays: 10,
            repetitions: 3,
            dueDate: testNow,
            lastReviewedAt: testNow.addingTimeInterval(-10 * 86_400),
            lapses: 2,
            stability: 10,
            difficulty: 5
        )

        let reviewed = scheduler.review(state: state, quality: 2, now: testNow)

        #expect(reviewed.lapses == 3)
        #expect((reviewed.stability ?? 0) < 10)
        #expect(reviewed.dueDate == testNow.addingTimeInterval(Double(reviewed.intervalDays) * 86_400))
    }

    @Test func aLowerDesiredRetentionBuysLongerIntervals() {
        let state = ReviewState(
            cardID: UUID(),
            intervalDays: 10,
            repetitions: 3,
            dueDate: testNow,
            lastReviewedAt: testNow.addingTimeInterval(-10 * 86_400),
            lapses: 0,
            stability: 10,
            difficulty: 5
        )
        let relaxed = FSRSScheduler(
            parameters: .init(desiredRetention: 0.8)
        ).review(state: state, quality: 4, now: testNow)

        let strict = FSRSScheduler(
            parameters: .init(desiredRetention: 0.95)
        ).review(state: state, quality: 4, now: testNow)

        #expect(relaxed.intervalDays > strict.intervalDays)
    }

    @Test func qualitiesOutsideZeroToFiveAreClamped() {
        let high = scheduler.review(
            state: .new(cardID: UUID(), now: testNow),
            quality: 99,
            now: testNow
        )
        #expect(abs((high.stability ?? 0) - weights[3]) < 1e-12)
        #expect(high.lapses == 0)

        let low = scheduler.review(
            state: .new(cardID: UUID(), now: testNow),
            quality: -7,
            now: testNow
        )
        #expect(abs((low.stability ?? 0) - weights[0]) < 1e-12)
        #expect(low.lapses == 1)
    }

    @Test func previewMatchesTheReviewItPredicts() {
        let state = ReviewState(
            cardID: UUID(),
            intervalDays: 10,
            repetitions: 3,
            dueDate: testNow,
            lastReviewedAt: testNow.addingTimeInterval(-10 * 86_400),
            lapses: 0,
            stability: 10,
            difficulty: 5
        )

        for quality in 0...5 {
            let preview = scheduler.previewIntervalDays(state: state, quality: quality, now: testNow)
            let reviewed = scheduler.review(state: state, quality: quality, now: testNow)
            #expect(preview == reviewed.intervalDays)
        }
    }

    @Test func dueCardsAnswerFromStatesLikeSM2Did() {
        let set = makeSet(cardCount: 3)
        let states: [UUID: ReviewState] = [
            set.cards[0].id: ReviewState(
                cardID: set.cards[0].id,
                dueDate: testNow.addingTimeInterval(-100)
            ),
            set.cards[1].id: ReviewState(
                cardID: set.cards[1].id,
                dueDate: testNow.addingTimeInterval(100)
            ),
        ]

        let engine = FSRSScheduler(states: states)
        let due = engine.dueCards(in: set, now: testNow)

        #expect(due.map(\.id) == [set.cards[0].id, set.cards[2].id])
        #expect(engine.dueCount(in: set, now: testNow) == 2)
    }
}
