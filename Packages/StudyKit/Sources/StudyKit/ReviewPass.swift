import Foundation

/// One card in a review queue, with the set it belongs to and when it is due.
public struct StudyQueueItem: Identifiable, Hashable, Sendable {
    /// The set holding the card.
    public let setID: UUID
    /// The set's title, for a mixed queue across sets.
    public let setTitle: String
    /// The card to show.
    public let card: StudyCard
    /// When the card became due.
    public let dueDate: Date

    /// A card appears once in a queue, so its id identifies the item.
    public var id: UUID { card.id }

    public init(setID: UUID, setTitle: String, card: StudyCard, dueDate: Date) {
        self.setID = setID
        self.setTitle = setTitle
        self.card = card
        self.dueDate = dueDate
    }
}

/// Builds one queue over any number of sets.
///
/// A card with no review state is new and due at the clock the queue is built
/// with. Cards can be narrowed to a notebook or a page through the source ids a
/// card carries, which is what the notebook's review entry points use.
public enum StudyQueue {
    /// Every due card, earliest due first then by set and card order.
    public static func due(
        in sets: [StudySet],
        states: [UUID: [UUID: ReviewState]] = [:],
        now: Date,
        notebookID: UUID? = nil,
        pageID: UUID? = nil,
        limit: Int? = nil
    ) -> [StudyQueueItem] {
        var items = collected(
            in: sets,
            states: states,
            now: now,
            notebookID: notebookID,
            pageID: pageID,
            dueOnly: true
        )
        items.sort { left, right in
            if left.item.dueDate != right.item.dueDate {
                return left.item.dueDate < right.item.dueDate
            }
            if left.item.setID != right.item.setID {
                return left.item.setID.uuidString < right.item.setID.uuidString
            }
            return left.position < right.position
        }
        let ordered = items.map(\.item)
        guard let limit, limit >= 0, limit < ordered.count else { return ordered }
        return Array(ordered.prefix(limit))
    }

    /// How many cards match a queue's filters at `now`.
    public static func dueCount(
        in sets: [StudySet],
        states: [UUID: [UUID: ReviewState]] = [:],
        now: Date,
        notebookID: UUID? = nil,
        pageID: UUID? = nil
    ) -> Int {
        collected(
            in: sets,
            states: states,
            now: now,
            notebookID: notebookID,
            pageID: pageID,
            dueOnly: true
        ).count
    }

    /// Every card that matches the filters, due or not, earliest due first and
    /// then in set and card order.
    ///
    /// Used by the notebook sheet to list the cards from one page or notebook
    /// beside their due dates; it does not filter by due date.
    public static func cards(
        in sets: [StudySet],
        states: [UUID: [UUID: ReviewState]] = [:],
        now: Date,
        notebookID: UUID? = nil,
        pageID: UUID? = nil
    ) -> [StudyQueueItem] {
        collected(
            in: sets,
            states: states,
            now: now,
            notebookID: notebookID,
            pageID: pageID,
            dueOnly: false
        )
        .sorted { left, right in
            if left.item.dueDate != right.item.dueDate {
                return left.item.dueDate < right.item.dueDate
            }
            if left.item.setID != right.item.setID {
                return left.item.setID.uuidString < right.item.setID.uuidString
            }
            return left.position < right.position
        }
        .map(\.item)
    }

    private static func collected(
        in sets: [StudySet],
        states: [UUID: [UUID: ReviewState]],
        now: Date,
        notebookID: UUID?,
        pageID: UUID?,
        dueOnly: Bool
    ) -> [(position: Int, item: StudyQueueItem)] {
        var items: [(position: Int, item: StudyQueueItem)] = []
        for set in sets {
            let setStates = states[set.id] ?? [:]
            for (position, card) in set.cards.enumerated() {
                if let notebookID, card.sourceNotebookID != notebookID { continue }
                if let pageID, card.sourcePageID != pageID { continue }
                let dueDate = setStates[card.id]?.dueDate ?? now
                if dueOnly, dueDate > now { continue }
                items.append((
                    position,
                    StudyQueueItem(
                        setID: set.id,
                        setTitle: set.title,
                        card: card,
                        dueDate: dueDate
                    )
                ))
            }
        }
        return items
    }
}

/// A single pass through a due queue, possibly across several sets.
///
/// The queue is captured at `init`, so its order is stable for the whole pass
/// even if the clock advances. Each card is served once; grading it updates the
/// state for its set. ``gradeCurrent(quality:now:)`` returns both the set id and
/// the new state so the caller can store them in the right place.
public struct ReviewPass: Sendable {
    /// The cards in this pass, reviewed plus remaining.
    public let itemCount: Int
    /// Current states, keyed by set id and then card id. Cards in the queue
    /// without a state are seeded as new at the pass clock.
    public private(set) var states: [UUID: [UUID: ReviewState]]
    /// The cards graded so far, in the order they were served.
    public private(set) var reviewedCardIDs: [UUID]

    private var pending: [StudyQueueItem]
    private let scheduler = FSRSScheduler()

    public init(items: [StudyQueueItem], states: [UUID: [UUID: ReviewState]] = [:], now: Date) {
        var seeded = states
        for item in items where seeded[item.setID]?[item.card.id] == nil {
            seeded[item.setID, default: [:]][item.card.id] = .new(cardID: item.card.id, now: now)
        }
        self.pending = items
        self.states = seeded
        self.reviewedCardIDs = []
        self.itemCount = items.count
    }

    /// The item to show next, or `nil` when the pass is finished.
    public var currentItem: StudyQueueItem? {
        pending.first
    }

    /// The card to show next, or `nil` when the pass is finished.
    public var currentCard: StudyCard? {
        pending.first?.card
    }

    /// Cards graded so far.
    public var reviewedCount: Int {
        reviewedCardIDs.count
    }

    /// Cards still waiting in this pass.
    public var remainingCount: Int {
        pending.count
    }

    /// Fraction of this pass that is graded, from 0 to 1. A pass with no cards
    /// reports 1 because there is nothing left to do.
    public var progress: Double {
        guard itemCount > 0 else { return 1 }
        return Double(reviewedCardIDs.count) / Double(itemCount)
    }

    /// True when every card in this pass has been graded, including an empty pass.
    public var isFinished: Bool {
        pending.isEmpty
    }

    /// The stored state for an item, or a fresh state due at `now`.
    public func state(for item: StudyQueueItem, now: Date) -> ReviewState {
        states[item.setID]?[item.card.id] ?? .new(cardID: item.card.id, now: now)
    }

    /// Grades the current card and advances the queue.
    ///
    /// `quality` must be 0...5, or the call throws
    /// ``StudyKitError/invalidQuality(_:)`` and leaves the pass unchanged.
    /// If the pass is already finished, it throws
    /// ``StudyKitError/noCurrentCard``.
    ///
    /// - Returns: The set the card belongs to and its new review state.
    @discardableResult
    public mutating func gradeCurrent(
        quality: Int,
        now: Date
    ) throws -> (setID: UUID, state: ReviewState) {
        guard (0...5).contains(quality) else {
            throw StudyKitError.invalidQuality(quality)
        }
        guard let item = pending.first else {
            throw StudyKitError.noCurrentCard
        }

        let updated = scheduler.review(state: state(for: item, now: now), quality: quality, now: now)
        states[item.setID, default: [:]][item.card.id] = updated
        pending.removeFirst()
        reviewedCardIDs.append(item.card.id)
        return (item.setID, updated)
    }
}
