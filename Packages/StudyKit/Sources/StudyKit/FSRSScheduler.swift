import Foundation

/// The four grades a review offers, in FSRS's own 1...4 scale.
///
/// The app's buttons still speak SM-2 qualities (1, 3, 4, 5); ``init(quality:)``
/// maps them so both schedulers read the same tap.
public enum ReviewGrade: Int, CaseIterable, Codable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    /// Maps an SM-2 quality of 0...5 onto the four FSRS grades.
    public init(quality: Int) {
        switch quality {
        case ...2: self = .again
        case 3: self = .hard
        case 4: self = .good
        default: self = .easy
        }
    }
}

/// An FSRS-style scheduler: stability, difficulty and retrievability instead
/// of a single ease factor.
///
/// The scheduler owns a snapshot of review states so that
/// ``dueCards(in:now:)`` can answer from a `StudySet` alone. ``review(state:quality:now:)``
/// is pure: it returns a new state and never mutates the snapshot. The caller
/// stores the returned state and continues with it.
///
/// Days are fixed 24-hour periods (`86_400` seconds), as in SM-2, so the same
/// inputs produce the same dates on every device and time zone. The weights are
/// the published FSRS-5 defaults; they are a constant here because note review
/// has no review log large enough to fit its own.
public struct FSRSScheduler: Equatable, Sendable {
    /// Tunables for the scheduler and its interval target.
    public struct Parameters: Equatable, Sendable {
        /// FSRS-5 default weights. Seventeen values are used; the two
        /// same-day weights of later revisions are not. A shorter array falls
        /// back to the defaults rather than reading past its end.
        public var weights: [Double]
        /// The recall probability an interval aims for, from 0.7 to 0.99.
        public var desiredRetention: Double
        /// The longest interval the scheduler will set, in days.
        public var maximumIntervalDays: Int

        public init(
            weights: [Double] = FSRSScheduler.defaultWeights,
            desiredRetention: Double = 0.9,
            maximumIntervalDays: Int = 36_500
        ) {
            self.weights = weights.count >= 17 ? weights : FSRSScheduler.defaultWeights
            self.desiredRetention = min(0.99, max(0.7, desiredRetention))
            self.maximumIntervalDays = max(1, maximumIntervalDays)
        }
    }

    /// FSRS-5's default weights, in the order the formulas use them.
    public static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105,
        7.1949, 0.5345,
        1.4604, 0.0046,
        1.54575, 0.1192, 1.01925,
        1.9395, 0.11, 0.29605, 2.2698,
        0.2315, 2.9898,
    ]

    /// The FSRS forgetting curve's decay and scale.
    private static let decay = -0.5
    private static let factor = 19.0 / 81.0
    /// The stability a failure may never fall below.
    private static let minimumStability = 0.1
    /// A review that is more than this many days apart is capped before the
    /// curve is evaluated, so a clock jump cannot produce a NaN.
    private static let maximumElapsedDays = 100_000.0

    public let parameters: Parameters
    /// Review states by card id. Cards without an entry are treated as new and
    /// due at the clock passed to ``dueCards(in:now:)``.
    public private(set) var states: [UUID: ReviewState]

    /// Creates a scheduler over a snapshot of review states.
    public init(states: [UUID: ReviewState] = [:], parameters: Parameters = Parameters()) {
        self.parameters = parameters
        self.states = states
    }

    /// The stored state for a card, migrated to FSRS when it is still an SM-2
    /// state, or a fresh state due at `now` when none exists.
    public func state(for cardID: UUID, now: Date) -> ReviewState {
        guard let stored = states[cardID] else {
            return .new(cardID: cardID, now: now)
        }
        return migrate(stored)
    }

    /// Turns a reviewed SM-2 state into an FSRS state without changing when it
    /// is due or how much history it carries.
    ///
    /// The SM-2 interval is the old scheduler's estimate of how long the card
    /// was remembered, so it becomes the FSRS stability. The ease factor says
    /// how hard the card felt, so it shifts difficulty away from the "Good"
    /// starting value: 2.5 keeps it at that value, every 0.5 of ease below 2.5
    /// adds one point of difficulty. A card that has never been reviewed is
    /// left alone; its first FSRS grade supplies both values.
    public func migrate(_ state: ReviewState) -> ReviewState {
        guard state.stability == nil, state.lastReviewedAt != nil else { return state }
        var migrated = state
        migrated.stability = max(0.5, Double(max(1, state.intervalDays)))
        let difficulty = initialDifficulty(for: .good)
            - (ReviewState.initialEaseFactor - state.easeFactor) * 2
        migrated.difficulty = min(10, max(1, difficulty))
        return migrated
    }

    /// Applies one review and returns the card's next state.
    ///
    /// `quality` is clamped to 0...5 and mapped to an FSRS grade: 0...2 is
    /// Again, 3 is Hard, 4 is Good, 5 is Easy. A first review starts from the
    /// grade's initial stability; later reviews move stability by the FSRS
    /// curve for the elapsed time and the card's difficulty. A failure cannot
    /// lengthen the interval, and it adds a lapse. The due date is `now` plus
    /// the interval that reaches the requested retention.
    public func review(state: ReviewState, quality: Int, now: Date) -> ReviewState {
        let grade = ReviewGrade(quality: min(5, max(0, quality)))
        var next = migrate(state)
        next.lastReviewedAt = now

        let stability: Double
        let difficulty: Double
        if let previousStability = next.stability {
            let previousDifficulty = next.difficulty ?? initialDifficulty(for: .good)
            let elapsed = elapsedDays(since: state.lastReviewedAt, now: now)
            let retrievability = Self.retrievability(elapsedDays: elapsed, stability: previousStability)

            stability = nextStability(
                previous: previousStability,
                difficulty: previousDifficulty,
                retrievability: retrievability,
                grade: grade
            )
            difficulty = nextDifficulty(previous: previousDifficulty, grade: grade)
        } else {
            stability = initialStability(for: grade)
            difficulty = initialDifficulty(for: grade)
        }

        next.stability = min(
            max(stability, Self.minimumStability),
            Double(parameters.maximumIntervalDays)
        )
        next.difficulty = difficulty
        next.intervalDays = intervalDays(forStability: next.stability ?? stability)
        next.dueDate = now.addingTimeInterval(Double(next.intervalDays) * 86_400)
        next.lapses = max(0, state.lapses) + (grade == .again ? 1 : 0)
        next.repetitions = grade == .again ? 0 : max(0, state.repetitions) + 1
        return next
    }

    /// The interval a grade would produce, for the interval under each grade
    /// button.
    public func previewIntervalDays(state: ReviewState, quality: Int, now: Date) -> Int {
        review(state: state, quality: quality, now: now).intervalDays
    }

    /// Cards that are due at or before `now`, earliest due first.
    ///
    /// Ties keep the order the cards have in `set`. A card with no state is new
    /// and therefore included. The result is idempotent for a fixed clock.
    public func dueCards(in set: StudySet, now: Date) -> [StudyCard] {
        var due: [(position: Int, card: StudyCard, dueDate: Date)] = []
        due.reserveCapacity(set.cards.count)

        for (position, card) in set.cards.enumerated() {
            let dueDate = state(for: card.id, now: now).dueDate
            if dueDate <= now {
                due.append((position, card, dueDate))
            }
        }

        due.sort { left, right in
            if left.dueDate != right.dueDate { return left.dueDate < right.dueDate }
            return left.position < right.position
        }
        return due.map(\.card)
    }

    /// How many cards in `set` are due at `now`.
    public func dueCount(in set: StudySet, now: Date) -> Int {
        set.cards.reduce(0) { count, card in
            count + (state(for: card.id, now: now).dueDate <= now ? 1 : 0)
        }
    }

    // MARK: - FSRS maths

    /// The chance the card is still remembered after `elapsedDays`.
    public static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0, elapsedDays > 0 else { return 1 }
        return pow(1 + factor * elapsedDays / stability, decay)
    }

    private func initialStability(for grade: ReviewGrade) -> Double {
        max(Self.minimumStability, parameters.weights[grade.rawValue - 1])
    }

    private func initialDifficulty(for grade: ReviewGrade) -> Double {
        let weights = parameters.weights
        return min(10, max(1, weights[4] - exp(weights[5] * Double(grade.rawValue - 1)) + 1))
    }

    private func nextStability(
        previous: Double,
        difficulty: Double,
        retrievability: Double,
        grade: ReviewGrade
    ) -> Double {
        let weights = parameters.weights
        if grade == .again {
            let forgotten = weights[11]
                * pow(difficulty, -weights[12])
                * (pow(previous + 1, weights[13]) - 1)
                * exp((1 - retrievability) * weights[14])
            return min(forgotten, previous)
        }

        var grown = previous * (1 + exp(weights[8])
            * (11 - difficulty)
            * pow(previous, -weights[9])
            * (exp((1 - retrievability) * weights[10]) - 1))
        if grade == .hard { grown *= weights[15] }
        if grade == .easy { grown *= weights[16] }
        return grown
    }

    private func nextDifficulty(previous: Double, grade: ReviewGrade) -> Double {
        let weights = parameters.weights
        let delta = -weights[6] * Double(grade.rawValue - 3)
        let damped = previous + delta * (10 - previous) / 9
        let reverted = weights[7] * initialDifficulty(for: .good) + (1 - weights[7]) * damped
        return min(10, max(1, reverted))
    }

    private func intervalDays(forStability stability: Double) -> Int {
        let retention = parameters.desiredRetention
        let days = (stability / Self.factor) * (pow(retention, 1 / Self.decay) - 1)
        guard days.isFinite else { return 1 }
        let rounded = days.rounded()
        guard rounded < Double(parameters.maximumIntervalDays) else {
            return parameters.maximumIntervalDays
        }
        return max(1, Int(rounded))
    }

    private func elapsedDays(since lastReviewedAt: Date?, now: Date) -> Double {
        guard let lastReviewedAt else { return 0 }
        let days = now.timeIntervalSince(lastReviewedAt) / 86_400
        guard days.isFinite else { return 0 }
        return min(Self.maximumElapsedDays, max(0, days))
    }
}
