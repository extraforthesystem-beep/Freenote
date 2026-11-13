import Foundation

/// A single pass through the cards that are due when the session starts.
///
/// The session captures its due queue at `init`, so the order is stable for the
/// whole pass even if the clock advances. Each card is served once; grading it
/// updates the scheduler state for that card. With the same set, states, clock
/// and grade history, every session produces the same queue and the same states.
///
/// The queue only contains cards that are due. Cards scheduled for the future
/// keep their existing states in ``states`` but are not served.
public struct SmartLearnSession: Sendable {
    /// The set being studied.
    public let set: StudySet
    /// Current states for every card in the set, including cards with no card
    /// in this pass. New cards start due at the session's clock.
    public private(set) var states: [UUID: ReviewState]
    /// The cards graded so far, in the order they were served.
    public private(set) var reviewedCardIDs: [UUID]

    private var pendingCards: [StudyCard]
    private let scheduler = SpacedRepetitionScheduler()

    /// Captures the cards due at `now` and seeds a new state for every card
    /// that does not already have one.
    public init(set: StudySet, states: [UUID: ReviewState] = [:], now: Date) {
        var seeded = states
        for card in set.cards where seeded[card.id] == nil {
            seeded[card.id] = .new(cardID: card.id, now: now)
        }

        self.set = set
        self.states = seeded
        self.reviewedCardIDs = []
        self.pendingCards = SpacedRepetitionScheduler(states: seeded).dueCards(in: set, now: now)
    }

    /// The card to show next, or `nil` when the pass is finished.
    public var currentCard: StudyCard? {
        pendingCards.first
    }

    /// Cards graded so far.
    public var reviewedCount: Int {
        reviewedCardIDs.count
    }

    /// Cards still waiting in this pass.
    public var remainingCount: Int {
        pendingCards.count
    }

    /// Cards in this pass, reviewed plus remaining. Not the size of the whole set.
    public var sessionCardCount: Int {
        reviewedCardIDs.count + pendingCards.count
    }

    /// Fraction of this pass that is graded, from 0 to 1. A pass with no due
    /// cards reports 1 because there is nothing left to do.
    public var progress: Double {
        let total = sessionCardCount
        guard total > 0 else { return 1 }
        return Double(reviewedCardIDs.count) / Double(total)
    }

    /// True when every card in this pass has been graded, including an empty pass.
    public var isFinished: Bool {
        pendingCards.isEmpty
    }

    /// Grades the current card and advances the queue.
    ///
    /// `quality` must be 0...5, or the call throws
    /// ``StudyKitError/invalidQuality(_:)`` and leaves the session unchanged.
    /// If the pass is already finished, it throws
    /// ``StudyKitError/noCurrentCard``.
    ///
    /// - Returns: The card's new review state, ready to be stored by the caller.
    @discardableResult
    public mutating func gradeCurrent(quality: Int, now: Date) throws -> ReviewState {
        guard (0...5).contains(quality) else {
            throw StudyKitError.invalidQuality(quality)
        }
        guard let card = pendingCards.first else {
            throw StudyKitError.noCurrentCard
        }

        let previous = states[card.id] ?? .new(cardID: card.id, now: now)
        let updated = scheduler.review(state: previous, quality: quality, now: now)

        states[card.id] = updated
        pendingCards.removeFirst()
        reviewedCardIDs.append(card.id)
        return updated
    }
}
