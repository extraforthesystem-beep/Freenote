import Foundation

/// The spaced-repetition state of one card.
///
/// A state is created when a card is first shown, then replaced by the value
/// returned from ``SpacedRepetitionScheduler/review(state:quality:now:)``.
/// New states are due immediately, with no repetitions and no lapses.
public struct ReviewState: Codable, Identifiable, Hashable, Sendable {
    /// The SM-2 ease factor never drops below this value.
    public static let minimumEaseFactor = 1.3
    /// The SM-2 starting ease factor for a new card.
    public static let initialEaseFactor = 2.5

    public var cardID: UUID
    /// SM-2 ease factor; always at least 1.3 when built through this type.
    public var easeFactor: Double
    /// Days until the next review; zero for a card that has never been reviewed.
    public var intervalDays: Int
    /// Consecutive successful reviews; reset to zero on a failing grade.
    public var repetitions: Int
    /// The moment the card next becomes due.
    public var dueDate: Date
    /// When the card was last graded, or `nil` for a new card.
    public var lastReviewedAt: Date?
    /// How many times a grade below 3 has reset this card.
    public var lapses: Int

    /// `ReviewState` is identified by the card it schedules.
    public var id: UUID { cardID }

    public init(
        cardID: UUID,
        easeFactor: Double = ReviewState.initialEaseFactor,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        dueDate: Date,
        lastReviewedAt: Date? = nil,
        lapses: Int = 0
    ) {
        self.cardID = cardID
        self.easeFactor = max(ReviewState.minimumEaseFactor, easeFactor)
        self.intervalDays = max(0, intervalDays)
        self.repetitions = max(0, repetitions)
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
        self.lapses = max(0, lapses)
    }

    /// A fresh state for a card that has never been reviewed, due at `now`.
    public static func new(cardID: UUID, now: Date) -> ReviewState {
        ReviewState(cardID: cardID, dueDate: now)
    }
}
