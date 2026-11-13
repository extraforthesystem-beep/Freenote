import Foundation
import StudyKit
import Testing

@Suite("Review pass and due queue")
struct ReviewPassTests {
    private func card(_ index: Int, notebookID: UUID?, pageID: UUID?, now: Date = testNow) -> StudyCard {
        StudyCard(
            question: "Question \(index)",
            answer: "Answer \(index)",
            sourceNotebookID: notebookID,
            sourcePageID: pageID,
            createdAt: now,
            updatedAt: now
        )
    }

    @Test func oneQueueMixesSetsEarliestDueFirst() {
        let first = StudySet(
            title: "First",
            cards: [card(0, notebookID: nil, pageID: nil)],
            createdAt: testNow.addingTimeInterval(-10),
            updatedAt: testNow
        )
        let second = StudySet(
            title: "Second",
            cards: [card(1, notebookID: nil, pageID: nil)],
            createdAt: testNow.addingTimeInterval(-5),
            updatedAt: testNow
        )
        let states: [UUID: [UUID: ReviewState]] = [
            first.id: [first.cards[0].id: ReviewState(cardID: first.cards[0].id, dueDate: testNow.addingTimeInterval(-100))],
            second.id: [second.cards[0].id: ReviewState(cardID: second.cards[0].id, dueDate: testNow.addingTimeInterval(-500))],
        ]

        let queue = StudyQueue.due(in: [first, second], states: states, now: testNow)

        #expect(queue.map(\.card.id) == [second.cards[0].id, first.cards[0].id])
        #expect(queue.map(\.setTitle) == ["Second", "First"])
        #expect(StudyQueue.dueCount(in: [first, second], states: states, now: testNow) == 2)
    }

    @Test func aFutureCardIsNotInTheDueQueue() {
        let set = makeSet(cardCount: 2)
        let states: [UUID: [UUID: ReviewState]] = [
            set.id: [set.cards[0].id: ReviewState(cardID: set.cards[0].id, dueDate: testNow.addingTimeInterval(86_400))],
        ]

        let queue = StudyQueue.due(in: [set], states: states, now: testNow)

        #expect(queue.map(\.card.id) == [set.cards[1].id])
    }

    @Test func sourcesNarrowTheQueueToANotebookOrAPage() {
        let notebookID = UUID()
        let pageID = UUID()
        let otherPageID = UUID()
        let set = StudySet(
            title: "Sourced",
            cards: [
                card(0, notebookID: notebookID, pageID: pageID),
                card(1, notebookID: notebookID, pageID: otherPageID),
                card(2, notebookID: nil, pageID: nil),
            ],
            createdAt: testNow,
            updatedAt: testNow
        )

        let notebook = StudyQueue.due(in: [set], now: testNow, notebookID: notebookID)
        let page = StudyQueue.due(in: [set], now: testNow, notebookID: notebookID, pageID: pageID)

        #expect(notebook.map(\.card.id) == [set.cards[0].id, set.cards[1].id])
        #expect(page.map(\.card.id) == [set.cards[0].id])
        #expect(StudyQueue.dueCount(in: [set], now: testNow, notebookID: notebookID) == 2)
    }

    @Test func cardsListsEveryMatchingCardEvenWhenItIsNotDue() {
        let notebookID = UUID()
        let pageID = UUID()
        let set = StudySet(
            title: "Sourced",
            cards: [card(0, notebookID: notebookID, pageID: pageID)],
            createdAt: testNow,
            updatedAt: testNow
        )
        let future = ReviewState(cardID: set.cards[0].id, dueDate: testNow.addingTimeInterval(86_400))

        let listed = StudyQueue.cards(
            in: [set],
            states: [set.id: [set.cards[0].id: future]],
            now: testNow,
            notebookID: notebookID,
            pageID: pageID
        )

        #expect(listed.map(\.card.id) == [set.cards[0].id])
        #expect(listed.first?.dueDate == future.dueDate)
    }

    @Test func gradingWritesBackToTheSetTheCardCameFrom() throws {
        let first = StudySet(title: "First", cards: [card(0, notebookID: nil, pageID: nil)], createdAt: testNow, updatedAt: testNow)
        let second = StudySet(title: "Second", cards: [card(1, notebookID: nil, pageID: nil)], createdAt: testNow, updatedAt: testNow)
        let items = StudyQueue.due(in: [first, second], now: testNow)
        var pass = ReviewPass(items: items, now: testNow)
        let firstItem = try #require(pass.currentItem)
        let secondItem = try #require(items.last)

        let result = try pass.gradeCurrent(quality: 4, now: testNow)

        #expect(result.setID == firstItem.setID)
        #expect(pass.states[firstItem.setID]?[firstItem.card.id] == result.state)
        #expect(pass.states[secondItem.setID]?[secondItem.card.id]?.lapses == 0)
        #expect(result.state.lastReviewedAt == testNow)
        #expect(pass.reviewedCount == 1)
        #expect(pass.remainingCount == 1)

        let next = try pass.gradeCurrent(quality: 5, now: testNow)
        #expect(next.setID == secondItem.setID)
        #expect(pass.isFinished)
        #expect(pass.progress == 1)
    }

    @Test func aPassRejectsAGradeOutsideTheQualityRange() {
        let set = makeSet(cardCount: 1)
        var pass = ReviewPass(items: StudyQueue.due(in: [set], now: testNow), now: testNow)

        expectError(.invalidQuality(6)) {
            _ = try pass.gradeCurrent(quality: 6, now: testNow)
        }

        #expect(pass.remainingCount == 1)
        #expect(pass.reviewedCount == 0)
    }

    @Test func anEmptyQueueIsAlreadyFinished() {
        var pass = ReviewPass(items: [], now: testNow)

        #expect(pass.isFinished)
        #expect(pass.progress == 1)
        #expect(pass.currentCard == nil)

        expectError(.noCurrentCard) {
            _ = try pass.gradeCurrent(quality: 4, now: testNow)
        }
    }

    @Test func theQueueOrderIsStableAcrossPasses() {
        let set = makeSet(cardCount: 5)
        let first = StudyQueue.due(in: [set], now: testNow)
        let second = StudyQueue.due(in: [set], now: testNow)

        #expect(first.map(\.card.id) == second.map(\.card.id))
        #expect(first.count == 5)
    }

    @Test func aLeechIsFlaggedAfterItsFourthLapseInAPass() throws {
        let set = makeSet(cardCount: 1)
        let state = ReviewState(
            cardID: set.cards[0].id,
            intervalDays: 4,
            repetitions: 2,
            dueDate: testNow.addingTimeInterval(-86_400),
            lastReviewedAt: testNow.addingTimeInterval(-5 * 86_400),
            lapses: 3,
            stability: 4,
            difficulty: 6
        )
        var pass = ReviewPass(
            items: StudyQueue.due(in: [set], states: [set.id: [state.cardID: state]], now: testNow),
            states: [set.id: [state.cardID: state]],
            now: testNow
        )

        let result = try pass.gradeCurrent(quality: 1, now: testNow)

        #expect(result.state.lapses == 4)
        #expect(result.state.isLeech)
    }
}
