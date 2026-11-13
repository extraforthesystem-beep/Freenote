import Foundation

/// A single pass through the cards that are due when the session starts.
///
/// The session captures its due queue at `init`, so the order is stable for the
/// whole pass even if the clock advances. Each unique card holds one slot:
/// grading it updates the FSRS state for that card, and an Again grade returns
/// it to this session under the same rule as ``ReviewPass``. With the same set,
/// states, clock and grade history, every session produces the same queue and
/// the same states.
///
/// The queue only contains cards that are due. Cards scheduled for the future
/// keep their existing states in ``states`` but are not served.
///
/// This is the one-set form of ``ReviewPass``; both share their grading, so a
/// pass over one set and a pass over a mixed queue schedule cards identically.
public struct SmartLearnSession: Sendable {
    /// The set being studied.
    public let set: StudySet
    /// The unique cards that have left this session, in the order they left.
    /// A card requeued by an Again grade appears once.
    public var reviewedCardIDs: [UUID] {
        pass.reviewedCardIDs
    }

    private var pass: ReviewPass

    /// Captures the cards due at `now` and seeds a new state for every card
    /// that does not already have one.
    public init(set: StudySet, states: [UUID: ReviewState] = [:], now: Date) {
        var seeded = states
        for card in set.cards where seeded[card.id] == nil {
            seeded[card.id] = .new(cardID: card.id, now: now)
        }

        self.set = set
        self.pass = ReviewPass(
            items: StudyQueue.due(in: [set], states: [set.id: seeded], now: now),
            states: [set.id: seeded],
            now: now
        )
    }

    /// Current states for every card in the set, including cards with no card
    /// in this pass. New cards start due at the session's clock.
    public var states: [UUID: ReviewState] {
        pass.states[set.id] ?? [:]
    }

    /// The card to show next, or `nil` when the pass is finished.
    public var currentCard: StudyCard? {
        pass.currentCard
    }

    /// Unique cards that have left this session. Attempts are not counted, so a
    /// card requeued by an Again grade and then passed counts once.
    public var reviewedCount: Int {
        pass.reviewedCount
    }

    /// Unique cards still waiting in this session.
    public var remainingCount: Int {
        pass.remainingCount
    }

    /// Cards in this pass, reviewed plus remaining. Not the size of the whole set.
    public var sessionCardCount: Int {
        pass.itemCount
    }

    /// Fraction of this pass that is finished, from 0 to 1. A pass with no due
    /// cards reports 1 because there is nothing left to do.
    public var progress: Double {
        pass.progress
    }

    /// True when every card in this pass has left it, including an empty pass.
    public var isFinished: Bool {
        pass.isFinished
    }

    /// Grades the current card and advances the queue.
    ///
    /// `quality` must be 0...5, or the call throws
    /// ``StudyKitError/invalidQuality(_:)`` and leaves the session unchanged.
    /// If the pass is already finished, it throws
    /// ``StudyKitError/noCurrentCard``. Quality below 3 requeues the card under
    /// the same rule as ``ReviewPass``.
    ///
    /// - Returns: The card's new review state, ready to be stored by the caller.
    @discardableResult
    public mutating func gradeCurrent(quality: Int, now: Date) throws -> ReviewState {
        try pass.gradeCurrent(quality: quality, now: now).state
    }
}
