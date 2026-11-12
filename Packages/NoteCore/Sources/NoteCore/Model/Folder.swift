import Foundation

/// One folder in the library tree.
public struct Folder: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// `nil` means the folder sits at the root of the tree.
    public var parentID: UUID?
    /// A palette token such as `blue`, or nil for the default folder colour.
    public var colorName: String?
    /// An SF Symbol name, or nil for the folder symbol.
    public var iconName: String?

    public init(
        id: UUID,
        name: String,
        parentID: UUID? = nil,
        colorName: String? = nil,
        iconName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.colorName = colorName
        self.iconName = iconName
    }
}

/// The folder tree, the notebook-to-folder map, tags and favourites, stored as
/// `folders.json`.
public struct FolderTree: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var folders: [Folder]
    /// Notebook id to folder id; an absent notebook is at the root.
    public var notebookFolder: [UUID: UUID]
    /// Notebook id to tags.
    public var tags: [UUID: [String]]
    public var favourites: Set<UUID>

    public init(
        schemaVersion: Int = SchemaVersion.current,
        folders: [Folder] = [],
        notebookFolder: [UUID: UUID] = [:],
        tags: [UUID: [String]] = [:],
        favourites: Set<UUID> = []
    ) {
        self.schemaVersion = schemaVersion
        self.folders = folders
        self.notebookFolder = notebookFolder
        self.tags = tags
        self.favourites = favourites
    }

    public func folder(withID id: UUID) -> Folder? {
        folders.first { $0.id == id }
    }

    /// A flat wire shape whose keys are UUID strings, so that JSON object sorting
    /// alone makes the encoding deterministic.
    private struct Wire: Codable {
        var schemaVersion: Int
        var folders: [Folder]
        var notebookFolder: [String: String]
        var tags: [String: [String]]
        var favourites: [String]
    }

    private enum CodingKeys: String, CodingKey {
        case notebookFolder, favourites
    }

    public init(from decoder: any Decoder) throws {
        let wire = try Wire(from: decoder)

        var notebookFolder: [UUID: UUID] = [:]
        for (key, value) in wire.notebookFolder {
            guard let notebookID = UUID(uuidString: key), let folderID = UUID(uuidString: value) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath + [CodingKeys.notebookFolder],
                        debugDescription: "notebookFolder contains a value that is not a UUID"
                    )
                )
            }
            notebookFolder[notebookID] = folderID
        }

        var tags: [UUID: [String]] = [:]
        for (key, value) in wire.tags {
            guard let notebookID = UUID(uuidString: key) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath + [CodingKeys.notebookFolder],
                        debugDescription: "tags contains a key that is not a UUID"
                    )
                )
            }
            tags[notebookID] = value
        }

        var favourites = Set<UUID>()
        for identifier in wire.favourites {
            guard let notebookID = UUID(uuidString: identifier) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath + [CodingKeys.favourites],
                        debugDescription: "favourites contains a value that is not a UUID"
                    )
                )
            }
            favourites.insert(notebookID)
        }

        self.schemaVersion = wire.schemaVersion
        self.folders = wire.folders
        self.notebookFolder = notebookFolder
        self.tags = tags
        self.favourites = favourites
    }

    public func encode(to encoder: any Encoder) throws {
        let wire = Wire(
            schemaVersion: schemaVersion,
            folders: folders,
            notebookFolder: notebookFolder.reduce(into: [:]) { result, pair in
                result[pair.key.uuidString] = pair.value.uuidString
            },
            tags: tags.reduce(into: [:]) { result, pair in
                result[pair.key.uuidString] = pair.value
            },
            favourites: favourites.map(\.uuidString).sorted()
        )
        try wire.encode(to: encoder)
    }
}
