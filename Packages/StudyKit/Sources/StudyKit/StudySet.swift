import Foundation

/// A named collection of study cards.
///
/// `colorTag` is free-form for v1; the app can treat it as a palette token
/// such as `blue` or `important`. An empty string means no tag.
public struct StudySet: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity for the set file and for syncs.
    public var id: UUID
    /// The name shown in the study library.
    public var title: String
    /// The set's cards, in display and study order.
    public var cards: [StudyCard]
    /// When the set was created.
    public var createdAt: Date
    /// Updated whenever the set's title, cards or color tag changes.
    public var updatedAt: Date
    /// Free-form palette token, or an empty string for no tag.
    public var colorTag: String

    public init(
        id: UUID = UUID(),
        title: String,
        cards: [StudyCard] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        colorTag: String = ""
    ) {
        self.id = id
        self.title = title
        self.cards = cards
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.colorTag = colorTag
    }

    /// The card with this id, or `nil` when the set does not contain it.
    public func card(id: UUID) -> StudyCard? {
        cards.first { $0.id == id }
    }
}
