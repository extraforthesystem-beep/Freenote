import Foundation

/// One page of a notebook. Stored as a single `.page` file.
public struct Page: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var id: UUID
    public var width: Double
    public var height: Double
    public var template: PageTemplate
    /// A new page always has exactly one layer.
    public var layers: [Layer]
    public var strokes: [StrokeRecord]
    public var elements: [PageElement]
    /// Strokes removed since the page was created, kept so that a later merge
    /// does not resurrect them.
    public var deletedStrokeIDs: Set<UUID>

    public init(
        schemaVersion: Int = SchemaVersion.current,
        id: UUID,
        width: Double,
        height: Double,
        template: PageTemplate,
        layers: [Layer],
        strokes: [StrokeRecord] = [],
        elements: [PageElement] = [],
        deletedStrokeIDs: Set<UUID> = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.width = width
        self.height = height
        self.template = template
        self.layers = layers
        self.strokes = strokes
        self.elements = elements
        self.deletedStrokeIDs = deletedStrokeIDs
    }

    public struct Layer: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var isVisible: Bool
        public var isLocked: Bool

        public init(id: UUID, name: String, isVisible: Bool = true, isLocked: Bool = false) {
            self.id = id
            self.name = name
            self.isVisible = isVisible
            self.isLocked = isLocked
        }
    }

    /// Builds a new, empty page with its required single layer.
    public init(id: UUID = UUID(), width: Double, height: Double, template: PageTemplate) {
        self.init(
            id: id,
            width: width,
            height: height,
            template: template,
            layers: [Layer(id: UUID(), name: "Layer 1")]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, width, height, template, layers, strokes, elements, deletedStrokeIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        template = try container.decode(PageTemplate.self, forKey: .template)
        layers = try container.decode([Layer].self, forKey: .layers)
        strokes = try container.decode([StrokeRecord].self, forKey: .strokes)
        elements = try container.decode([PageElement].self, forKey: .elements)
        let identifiers = try container.decode([String].self, forKey: .deletedStrokeIDs)
        var deleted = Set<UUID>()
        for identifier in identifiers {
            guard let uuid = UUID(uuidString: identifier) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .deletedStrokeIDs,
                    in: container,
                    debugDescription: "not a UUID: \(identifier)"
                )
            }
            deleted.insert(uuid)
        }
        deletedStrokeIDs = deleted
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(template, forKey: .template)
        try container.encode(layers, forKey: .layers)
        try container.encode(strokes, forKey: .strokes)
        try container.encode(elements, forKey: .elements)
        try container.encode(deletedStrokeIDs.map(\.uuidString).sorted(), forKey: .deletedStrokeIDs)
    }
}
