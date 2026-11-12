import Foundation
import StudyKit
import Testing

@Suite("Smart Learn session")
struct SmartLearnSessionTests {
    @Test func hundredCardSessionDrainsEveryDueCardExactlyOnce() throws {
        let set = makeSet(cardCount: 100)
        var session = SmartLearnSession(set: set, now: testNow)

        #expect(session.sessionCardCount == 100)
        #expect(session.reviewedCount == 0)
        #expect(session.remainingCount == 100)
        #expect(session.progress == 0)

        var served = Set<UUID>()
        var step = 0
        let qualities = [0, 2, 3, 4, 5]

        while let card = session.currentCard {
            #expect(served.insert(card.id).inserted, "card \(card.id) was served twice")
            let quality = qualities[step % qualities.count]
            _ = try session.gradeCurrent(quality: quality, now: testNow)
            step += 1

            #expect(session.reviewedCount == step)
            #expect(session.remainingCount == 100 - step)
            #expect(abs(session.progress - Double(step) / 100) < 1e-12)
        }

        #expect(step == 100)
        #expect(served.count == 100)
        #expect(Set(session.reviewedCardIDs) == Set(set.cards.map(\.id)))
        #expect(session.reviewedCardIDs.count == 100)
        #expect(session.isFinished)
        #expect(session.progress == 1)
        #expect(session.currentCard == nil)

        expectError(.noCurrentCard) {
            _ = try session.gradeCurrent(quality: 4, now: testNow)
        }
    }

    @Test func onlyCardsDueAtTheStartAreServed() throws {
        let set = makeSet(cardCount: 3)
        let scheduledCard = set.cards[1]
        let futureState = ReviewState(
            cardID: scheduledCard.id,
            easeFactor: 2.4,
            intervalDays: 8,
            repetitions: 3,
            dueDate: testNow.addingTimeInterval(86_400),
            lastReviewedAt: testNow.addingTimeInterval(-100),
            lapses: 1
        )

        var session = SmartLearnSession(
            set: set,
            states: [scheduledCard.id: futureState],
            now: testNow
        )

        #expect(session.remainingCount == 2)
        #expect(session.sessionCardCount == 2)
        #expect(session.states.count == 3, "the future card and both new cards should have states")

        while session.currentCard != nil {
            _ = try session.gradeCurrent(quality: 4, now: testNow)
        }

        #expect(session.reviewedCount == 2)
        #expect(!session.reviewedCardIDs.contains(scheduledCard.id))
        #expect(session.states[scheduledCard.id] == futureState, "a card that was not due is untouched")
        #expect(session.isFinished)
    }

    @Test func newCardsGetImmediateStatesAtTheSessionClock() {
        let set = makeSet(cardCount: 2)
        let session = SmartLearnSession(set: set, now: testNow)

        for card in set.cards {
            let state = session.states[card.id]
            #expect(state?.dueDate == testNow)
            #expect(state?.easeFactor == 2.5)
            #expect(state?.repetitions == 0)
        }
    }

    @Test func gradingUpdatesTheStateAndReturnsIt() throws {
        let set = makeSet(cardCount: 1)
        var session = SmartLearnSession(set: set, now: testNow)
        let card = set.cards[0]

        let state = try session.gradeCurrent(quality: 5, now: testNow)

        #expect(state.cardID == card.id)
        #expect(state.repetitions == 1)
        #expect(state.intervalDays == 1)
        #expect(state.dueDate == testNow.addingTimeInterval(86_400))
        #expect(session.states[card.id] == state)
        #expect(session.reviewedCardIDs == [card.id])
        #expect(session.currentCard == nil)
        #expect(session.progress == 1)
    }

    @Test func fixedHistoryProducesIdenticalStatesAndOrder() throws {
        let set = makeSet(cardCount: 5)
        let qualities = [5, 3, 2, 4, 0]
        let times = (0..<qualities.count).map { testNow.addingTimeInterval(Double($0) * 3_600) }

        var first = SmartLearnSession(set: set, now: testNow)
        var second = SmartLearnSession(set: set, now: testNow)
        var order: [UUID] = []

        for (index, quality) in qualities.enumerated() {
            guard let card = first.currentCard else {
                Issue.record("session ran out of cards at step \(index)")
                return
            }
            order.append(card.id)
            _ = try first.gradeCurrent(quality: quality, now: times[index])
            _ = try second.gradeCurrent(quality: quality, now: times[index])
        }

        #expect(first.reviewedCardIDs == order)
        #expect(first.reviewedCardIDs == second.reviewedCardIDs)
        #expect(first.states == second.states)
        #expect(first.progress == 1)
    }

    @Test func invalidQualityIsRejectedWithoutAdvancing() throws {
        let set = makeSet(cardCount: 2)
        var session = SmartLearnSession(set: set, now: testNow)
        let current = session.currentCard

        expectError(.invalidQuality(6)) {
            _ = try session.gradeCurrent(quality: 6, now: testNow)
        }
        expectError(.invalidQuality(-1)) {
            _ = try session.gradeCurrent(quality: -1, now: testNow)
        }

        #expect(session.currentCard == current)
        #expect(session.reviewedCount == 0)
        #expect(session.remainingCount == 2)
    }

    @Test func anEmptyPassIsAlreadyFinished() {
        let set = makeSet(cardCount: 0)
        var session = SmartLearnSession(set: set, now: testNow)

        #expect(session.isFinished)
        #expect(session.reviewedCount == 0)
        #expect(session.remainingCount == 0)
        #expect(session.progress == 1)
        #expect(session.currentCard == nil)

        expectError(.noCurrentCard) {
            _ = try session.gradeCurrent(quality: 5, now: testNow)
        }
    }

    @Test func dueQueueKeepsEarliestDueFirst() {
        let set = makeSet(cardCount: 3)
        let states: [UUID: ReviewState] = [
            set.cards[1].id: ReviewState(
                cardID: set.cards[1].id,
                dueDate: testNow.addingTimeInterval(-500)
            ),
            set.cards[2].id: ReviewState(
                cardID: set.cards[2].id,
                dueDate: testNow.addingTimeInterval(-100)
            ),
        ]

        var session = SmartLearnSession(set: set, states: states, now: testNow)
        var order: [UUID] = []
        while let card = session.currentCard {
            order.append(card.id)
            _ = try? session.gradeCurrent(quality: 3, now: testNow)
        }

        #expect(order == [set.cards[1].id, set.cards[2].id, set.cards[0].id])
    }
}
