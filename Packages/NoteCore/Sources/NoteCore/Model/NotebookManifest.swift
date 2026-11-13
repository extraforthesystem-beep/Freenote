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
    /// When the notebook was last opened in the editor. Kept apart from
    /// `updatedAt` so opening a notebook does not reorder a grid sorted by date
    /// modified. Absent (nil) on notebooks never opened and on files written by
    /// builds that did not record it; an unknown key is ignored by older builds,
    /// so the manifest schema version does not change.
    public var lastOpenedAt: Date?

    public init(
        schemaVersion: Int = SchemaVersion.current,
        id: UUID,
        title: String,
        coverName: String? = nil,
        pageOrder: [UUID] = [],
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        pageScrollMode: PageScrollMode? = nil,
        lastOpenedAt: Date? = nil
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
        self.lastOpenedAt = lastOpenedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, coverName, pageOrder, createdAt, updatedAt
        case deletedAt, pageScrollMode, lastOpenedAt
    }

    /// `id`, `title`, `createdAt` and `updatedAt` identify the notebook and were
    /// part of the first manifest format. The rest may be absent: defaults match
    /// the initialiser, and a manifest that has them round-trips them exactly.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? SchemaVersion.initial
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        coverName = try container.decodeIfPresent(String.self, forKey: .coverName)
        pageOrder = try container.decodeIfPresent([UUID].self, forKey: .pageOrder) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        pageScrollMode = try container.decodeIfPresent(PageScrollMode.self, forKey: .pageScrollMode)
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }
}
