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
        // A card flagged as a leech leaves the pass even though it has
        // requeues left: the rewrite sheet is the next step, and a stale copy
        // must not come back after the card is rewritten.
        #expect(pass.reviewedCount == 1)
        #expect(pass.remainingCount == 0)
        #expect(pass.isFinished)
    }

    @Test func anAgainCardComesBackAfterTheGap() throws {
        let set = makeSet(cardCount: 6)
        var pass = ReviewPass(items: StudyQueue.due(in: [set], now: testNow), now: testNow)
        let failed = try #require(pass.currentItem)

        try pass.gradeCurrent(quality: 1, now: testNow)

        // An attempt is not a completed card: the pass still holds all six
        // unique cards and the progress bar does not move.
        #expect(pass.reviewedCount == 0)
        #expect(pass.remainingCount == pass.itemCount)
        #expect(pass.progress == 0)

        for _ in 0..<ReviewPass.requeueGap {
            let item = try #require(pass.currentItem)
            #expect(item.card.id != failed.card.id)
            try pass.gradeCurrent(quality: 4, now: testNow)
        }

        #expect(pass.currentItem?.card.id == failed.card.id)
        #expect(pass.reviewedCount == ReviewPass.requeueGap)
        #expect(pass.remainingCount == 3)
    }

    @Test func anAgainCardAtTheEndOfAShortQueueComesBackLast() throws {
        let set = makeSet(cardCount: 2)
        var pass = ReviewPass(items: StudyQueue.due(in: [set], now: testNow), now: testNow)
        let failed = try #require(pass.currentItem)

        try pass.gradeCurrent(quality: 1, now: testNow)

        // Fewer than the gap remain, so the card waits at the end.
        let other = try #require(pass.currentItem)
        #expect(other.card.id != failed.card.id)
        try pass.gradeCurrent(quality: 4, now: testNow)

        #expect(pass.currentItem?.card.id == failed.card.id)
        #expect(pass.reviewedCount == 1)
        #expect(pass.remainingCount == 1)
    }

    @Test func aCardPassedAfterARequeueIsCountedOnce() throws {
        let set = makeSet(cardCount: 4)
        var pass = ReviewPass(items: StudyQueue.due(in: [set], now: testNow), now: testNow)
        let failed = try #require(pass.currentItem)

        try pass.gradeCurrent(quality: 1, now: testNow)

        var steps = 0
        while pass.currentItem?.card.id != failed.card.id, steps < 20 {
            try pass.gradeCurrent(quality: 4, now: testNow)
            steps += 1
        }
        #expect(pass.currentItem?.card.id == failed.card.id)

        try pass.gradeCurrent(quality: 4, now: testNow)

        #expect(pass.reviewedCardIDs.filter { $0 == failed.card.id }.count == 1)
        #expect(pass.reviewedCount == pass.itemCount)
        #expect(pass.reviewedCount == 4)
        #expect(pass.remainingCount == 0)
        #expect(pass.isFinished)
        #expect(pass.progress == 1)
    }

    @Test func requeuesAreCappedPerCard() throws {
        let set = makeSet(cardCount: 1)
        let cardID = set.cards[0].id
        var pass = ReviewPass(items: StudyQueue.due(in: [set], now: testNow), now: testNow)
        let attempts = ReviewPass.maximumRequeuesPerCard + 1

        for attempt in 1...attempts {
            let result = try pass.gradeCurrent(quality: 1, now: testNow)
            #expect(result.state.cardID == cardID)
            if attempt < attempts {
                #expect(!pass.isFinished)
                #expect(pass.remainingCount == 1)
                #expect(pass.reviewedCount == 0)
            }
        }

        // The fourth failure has used every requeue, so the card leaves the
        // pass and stays scheduled by FSRS.
        #expect(pass.isFinished)
        #expect(pass.reviewedCount == 1)
        #expect(pass.reviewedCardIDs == [cardID])
        let scheduled = try #require(pass.states[set.id]?[cardID])
        #expect(scheduled.lapses == attempts)
        #expect(scheduled.isLeech)
        #expect(scheduled.dueDate >= testNow.addingTimeInterval(86_400))
    }

    @Test func canRequeueMatchesWhatAnAgainGradeDoes() throws {
        let set = makeSet(cardCount: 1)
        var pass = ReviewPass(items: StudyQueue.due(in: [set], now: testNow), now: testNow)
        let item = try #require(pass.currentItem)

        for _ in 0..<ReviewPass.maximumRequeuesPerCard {
            #expect(pass.canRequeue(item))
            try pass.gradeCurrent(quality: 1, now: testNow)
            #expect(pass.currentItem?.card.id == item.card.id)
        }

        #expect(!pass.canRequeue(item))
        try pass.gradeCurrent(quality: 1, now: testNow)
        #expect(pass.isFinished)
    }

    @Test func progressCountsUniqueCardsAndNeverExceedsThePass() throws {
        let set = makeSet(cardCount: 3)
        let failingCardID = set.cards[0].id
        var pass = ReviewPass(items: StudyQueue.due(in: [set], now: testNow), now: testNow)
        var lastProgress = 0.0
        var attempts = 0
        let maximumAttempts = pass.itemCount * (ReviewPass.maximumRequeuesPerCard + 1)

        while let item = pass.currentItem {
            #expect(pass.reviewedCount <= pass.itemCount)
            #expect(pass.remainingCount <= pass.itemCount)
            #expect(pass.reviewedCount + pass.remainingCount == pass.itemCount)
            #expect(pass.progress <= 1)
            #expect(pass.progress >= lastProgress)
            #expect(pass.progress == Double(pass.reviewedCount) / Double(pass.itemCount))
            lastProgress = pass.progress

            try pass.gradeCurrent(
                quality: item.card.id == failingCardID ? 1 : 4,
                now: testNow
            )
            attempts += 1
            #expect(attempts <= maximumAttempts)
        }

        #expect(pass.reviewedCount == pass.itemCount)
        #expect(pass.reviewedCount == 3)
        #expect(pass.progress == 1)
    }

    @Test func aNewPassDoesNotResurrectAnAgainCardThatIsNotDue() throws {
        let set = makeSet(cardCount: 3)
        var pass = ReviewPass(items: StudyQueue.due(in: [set], now: testNow), now: testNow)
        let failed = try #require(pass.currentItem)

        try pass.gradeCurrent(quality: 1, now: testNow)

        let nextPass = StudyQueue.due(in: [set], states: pass.states, now: testNow)

        #expect(!nextPass.contains { $0.card.id == failed.card.id })
        #expect(nextPass.count == 2)
        #expect(pass.remainingCount == 3, "the card is still in the current pass")
    }
}
