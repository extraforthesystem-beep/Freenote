import Foundation

/// The table of contents of one notebook, stored as `notebooks/<id>/notebook.json`.
public struct NotebookManifest: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var id: UUID
    public var title: String
    public var coverName: String?
    /// Page order as the user sees it. Page files are the truth; a load reconciles
    /// this list with the files that are actually present.
    public var pageOrder: [UUID]
    public var createdAt: Date
    public var updatedAt: Date
    /// When the notebook was moved to the trash. Absent on library notebooks and
    /// on files written by builds that did not record it, so the field is
    /// optional and decoding an old manifest still succeeds.
    public var deletedAt: Date?
    /// The notebook's own scroll direction. Absent (nil) means "use the app's
    /// default", and on files from builds that did not record it.
    public var pageScrollMode: PageScrollMode?

    public init(
        schemaVersion: Int = SchemaVersion.current,
        id: UUID,
        title: String,
        coverName: String? = nil,
        pageOrder: [UUID] = [],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        pageScrollMode: PageScrollMode? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.coverName = coverName
        self.pageOrder = pageOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.pageScrollMode = pageScrollMode
    }
}
