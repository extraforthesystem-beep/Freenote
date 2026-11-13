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
    /// Elements removed since the page was created, kept for the same reason.
    public var deletedElementIDs: Set<UUID>

    public init(
        schemaVersion: Int = SchemaVersion.current,
        id: UUID,
        width: Double,
        height: Double,
        template: PageTemplate,
        layers: [Layer],
        strokes: [StrokeRecord] = [],
        elements: [PageElement] = [],
        deletedStrokeIDs: Set<UUID> = [],
        deletedElementIDs: Set<UUID> = []
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
        self.deletedElementIDs = deletedElementIDs
    }

    /// Elements whose layer is visible. Hiding a layer is a render rule; the
    /// stored page keeps every element.
    public var visibleElements: [PageElement] {
        let visibleLayers = Set(layers.filter(\.isVisible).map(\.id))
        return elements.filter { visibleLayers.contains($0.layerID) }
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

        private enum CodingKeys: String, CodingKey {
            case id, name, isVisible, isLocked
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
            isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
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
        case schemaVersion, id, width, height, template, layers, strokes, elements
        case deletedStrokeIDs, deletedElementIDs
    }

    /// `id`, `width` and `height` were part of the first format, so a file
    /// without them is not a page. Everything else may be absent: a file written
    /// before a field existed decodes with the same default its initialiser
    /// gives, and a file that has the field round-trips it exactly.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? SchemaVersion.initial
        id = try container.decode(UUID.self, forKey: .id)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        template = try container.decodeIfPresent(PageTemplate.self, forKey: .template) ?? .blank
        layers = try container.decodeIfPresent([Layer].self, forKey: .layers)
            ?? [Layer(id: UUID(), name: "Layer 1")]
        strokes = try container.decodeIfPresent([StrokeRecord].self, forKey: .strokes) ?? []
        elements = try container.decodeIfPresent([PageElement].self, forKey: .elements) ?? []
        let identifiers = try container.decodeIfPresent([String].self, forKey: .deletedStrokeIDs) ?? []
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

        let elementIdentifiers = try container.decodeIfPresent([String].self, forKey: .deletedElementIDs) ?? []
        var deletedElements = Set<UUID>()
        for identifier in elementIdentifiers {
            guard let uuid = UUID(uuidString: identifier) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .deletedElementIDs,
                    in: container,
                    debugDescription: "not a UUID: \(identifier)"
                )
            }
            deletedElements.insert(uuid)
        }
        deletedElementIDs = deletedElements
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
        try container.encode(deletedElementIDs.map(\.uuidString).sorted(), forKey: .deletedElementIDs)
    }
}
