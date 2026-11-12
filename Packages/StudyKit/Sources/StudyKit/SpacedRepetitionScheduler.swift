import Foundation

/// A deterministic, SM-2 style scheduler.
///
/// The scheduler owns a snapshot of review states so that
/// ``dueCards(in:now:)`` can answer from a `StudySet` alone. ``review(state:quality:now:)``
/// is pure: it returns a new state and never mutates the snapshot. The caller
/// stores the returned state and continues with it.
///
/// Days are fixed 24-hour periods (`86_400` seconds), not calendar days, so the
/// same inputs produce the same dates on every device and time zone.
public struct SpacedRepetitionScheduler: Equatable, Sendable {
    /// Review states by card id. Cards without an entry are treated as new and
    /// due at the clock passed to ``dueCards(in:now:)``.
    public private(set) var states: [UUID: ReviewState]

    /// Creates a scheduler over a snapshot of review states.
    public init(states: [UUID: ReviewState] = [:]) {
        self.states = states
    }

    /// The stored state for a card, or a fresh state due at `now` when none exists.
    public func state(for cardID: UUID, now: Date) -> ReviewState {
        states[cardID] ?? .new(cardID: cardID, now: now)
    }

    /// Applies one review and returns the card's next state.
    ///
    /// `quality` is clamped to 0...5. Grades below 3 reset the repetition count,
    /// set a one-day interval, add a lapse and lower ease by 0.2. Grades of 3 or
    /// more advance the 1-day / 6-day / `interval × ease` ladder and adjust ease
    /// with the standard SM-2 formula. In every case ease is floored at 1.3, the
    /// due date is `now` plus the new interval, and `lastReviewedAt` becomes `now`.
    ///
    /// The interval for the third and later successes uses the ease factor from
    /// before this review, matching the original SM-2 definition.
    public func review(state: ReviewState, quality: Int, now: Date) -> ReviewState {
        let quality = min(5, max(0, quality))
        let previousEase = max(ReviewState.minimumEaseFactor, state.easeFactor)

        var next = state
        next.lastReviewedAt = now

        if quality < 3 {
            next.repetitions = 0
            next.intervalDays = 1
            next.lapses = max(0, state.lapses) + 1
            next.easeFactor = max(ReviewState.minimumEaseFactor, previousEase - 0.2)
        } else {
            next.repetitions = max(0, state.repetitions) + 1
            switch next.repetitions {
            case 1:
                next.intervalDays = 1
            case 2:
                next.intervalDays = 6
            default:
                let scaled = Double(max(0, state.intervalDays)) * previousEase
                next.intervalDays = Self.wholeDays(scaled)
            }

            let distance = Double(5 - quality)
            let adjustment = 0.1 - distance * (0.08 + distance * 0.02)
            next.easeFactor = max(ReviewState.minimumEaseFactor, previousEase + adjustment)
        }

        next.dueDate = now.addingTimeInterval(Double(next.intervalDays) * 86_400)
        return next
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

    /// Rounds a positive day count to a whole day, never below one.
    private static func wholeDays(_ value: Double) -> Int {
        guard value.isFinite else { return 1 }
        let rounded = value.rounded()
        // Keep the conversion in Int's range even if a caller supplied a wild state.
        guard rounded < Double(Int.max) else { return Int.max }
        return max(1, Int(rounded))
    }
}
