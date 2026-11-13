import Foundation

/// One question/answer pair in a study set.
///
/// Cards are plain text in v1. `imageAssetName` optionally points at an image
/// in the notebook's asset store, and the source ids record where the card was
/// captured from without making the card depend on that notebook or page.
public struct StudyCard: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity across edits, imports and syncs.
    public var id: UUID
    /// The prompt shown first.
    public var question: String
    /// The revealed answer.
    public var answer: String
    /// Optional asset file name for an image shown with the card.
    public var imageAssetName: String?
    /// The notebook this card was captured from, when known.
    public var sourceNotebookID: UUID?
    /// The page this card was captured from, when known.
    public var sourcePageID: UUID?
    /// When the card was created.
    public var createdAt: Date
    /// Updated whenever the card's content changes; defaults to `createdAt`.
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        imageAssetName: String? = nil,
        sourceNotebookID: UUID? = nil,
        sourcePageID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.imageAssetName = imageAssetName
        self.sourceNotebookID = sourceNotebookID
        self.sourcePageID = sourcePageID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
