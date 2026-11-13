import Foundation

/// The spaced-repetition state of one card.
///
/// A state is created when a card is first shown, then replaced by the value
/// returned from a scheduler's `review(state:quality:now:)`. New states are due
/// immediately, with no repetitions and no lapses.
///
/// The SM-2 fields (`easeFactor`, `intervalDays`, `repetitions`) and the FSRS
/// fields (`stability`, `difficulty`) live side by side so a state written by
/// either scheduler can be read by both. `stability` and `difficulty` are
/// optional because every state written before FSRS existed has neither; the
/// file format has not changed and old review files still decode.
public struct ReviewState: Codable, Identifiable, Hashable, Sendable {
    /// The SM-2 ease factor never drops below this value.
    public static let minimumEaseFactor = 1.3
    /// The SM-2 starting ease factor for a new card.
    public static let initialEaseFactor = 2.5
    /// A card that has lapsed this many times is flagged as a leech.
    public static let leechThreshold = 4

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
    /// FSRS memory stability in days: how long recall is expected to last.
    /// `nil` for a card that has only ever been scheduled by SM-2.
    public var stability: Double?
    /// FSRS difficulty from 1 (easy) to 10 (hard); `nil` until FSRS grades
    /// the card, or until an SM-2 state is migrated.
    public var difficulty: Double?

    /// `ReviewState` is identified by the card it schedules.
    public var id: UUID { cardID }

    /// True once the card has lapsed enough times to need a rewrite.
    public var isLeech: Bool {
        lapses >= ReviewState.leechThreshold
    }

    public init(
        cardID: UUID,
        easeFactor: Double = ReviewState.initialEaseFactor,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        dueDate: Date,
        lastReviewedAt: Date? = nil,
        lapses: Int = 0,
        stability: Double? = nil,
        difficulty: Double? = nil
    ) {
        self.cardID = cardID
        self.easeFactor = max(ReviewState.minimumEaseFactor, easeFactor)
        self.intervalDays = max(0, intervalDays)
        self.repetitions = max(0, repetitions)
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
        self.lapses = max(0, lapses)
        self.stability = stability.map { max(0.1, $0) }
        self.difficulty = difficulty.map { min(10, max(1, $0)) }
    }

    /// A fresh state for a card that has never been reviewed, due at `now`.
    public static func new(cardID: UUID, now: Date) -> ReviewState {
        ReviewState(cardID: cardID, dueDate: now)
    }

    private enum CodingKeys: String, CodingKey {
        case cardID, easeFactor, intervalDays, repetitions, dueDate, lastReviewedAt, lapses
        case stability, difficulty
    }

    /// Decodes states written before FSRS existed: the two new keys are
    /// missing there and decode as `nil`, so no review history is lost.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let easeFactor = try container.decodeIfPresent(Double.self, forKey: .easeFactor)
            ?? ReviewState.initialEaseFactor
        self.init(
            cardID: try container.decode(UUID.self, forKey: .cardID),
            easeFactor: easeFactor,
            intervalDays: try container.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 0,
            repetitions: try container.decodeIfPresent(Int.self, forKey: .repetitions) ?? 0,
            dueDate: try container.decode(Date.self, forKey: .dueDate),
            lastReviewedAt: try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt),
            lapses: try container.decodeIfPresent(Int.self, forKey: .lapses) ?? 0,
            stability: try container.decodeIfPresent(Double.self, forKey: .stability),
            difficulty: try container.decodeIfPresent(Double.self, forKey: .difficulty)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cardID, forKey: .cardID)
        try container.encode(easeFactor, forKey: .easeFactor)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(repetitions, forKey: .repetitions)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(lastReviewedAt, forKey: .lastReviewedAt)
        try container.encode(lapses, forKey: .lapses)
        try container.encodeIfPresent(stability, forKey: .stability)
        try container.encodeIfPresent(difficulty, forKey: .difficulty)
    }
}
