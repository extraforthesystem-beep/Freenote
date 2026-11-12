import Foundation

/// A stroke as it is stored in a page file.
///
/// This is the source of truth for ink; a `PKDrawing` or a Metal mesh is a cache
/// built from these records.
public struct StrokeRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var layerID: UUID
    public var tool: StrokeTool
    public var createdAt: Date
    /// Exactly six numbers: `a, b, c, d, tx, ty`.
    public var transform: [Double]
    public var randomSeed: UInt32
    public var mask: [PathElement]?
    public var renderGroupID: UUID?
    public var points: [StrokePoint]

    public static let transformElementCount = 6
    public static let identityTransform: [Double] = [1, 0, 0, 1, 0, 0]

    public init(
        id: UUID,
        layerID: UUID,
        tool: StrokeTool,
        createdAt: Date,
        transform: [Double] = StrokeRecord.identityTransform,
        randomSeed: UInt32,
        mask: [PathElement]? = nil,
        renderGroupID: UUID? = nil,
        points: [StrokePoint]
    ) {
        self.id = id
        self.layerID = layerID
        self.tool = tool
        self.createdAt = createdAt
        self.transform = transform
        self.randomSeed = randomSeed
        self.mask = mask
        self.renderGroupID = renderGroupID
        self.points = points
    }

    private enum CodingKeys: String, CodingKey {
        case id, layerID, tool, createdAt, transform, randomSeed, mask, renderGroupID, points
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let transform = try container.decode([Double].self, forKey: .transform)
        guard transform.count == StrokeRecord.transformElementCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .transform,
                in: container,
                debugDescription: "transform must contain exactly \(StrokeRecord.transformElementCount) numbers"
            )
        }
        self.id = try container.decode(UUID.self, forKey: .id)
        self.layerID = try container.decode(UUID.self, forKey: .layerID)
        self.tool = try container.decode(StrokeTool.self, forKey: .tool)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.transform = transform
        self.randomSeed = try container.decode(UInt32.self, forKey: .randomSeed)
        self.mask = try container.decodeIfPresent([PathElement].self, forKey: .mask)
        self.renderGroupID = try container.decodeIfPresent(UUID.self, forKey: .renderGroupID)
        self.points = try container.decode([StrokePoint].self, forKey: .points)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard transform.count == StrokeRecord.transformElementCount else {
            throw EncodingError.invalidValue(
                transform,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "transform must contain exactly \(StrokeRecord.transformElementCount) numbers"
                )
            )
        }
        try container.encode(id, forKey: .id)
        try container.encode(layerID, forKey: .layerID)
        try container.encode(tool, forKey: .tool)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(transform, forKey: .transform)
        try container.encode(randomSeed, forKey: .randomSeed)
        try container.encodeIfPresent(mask, forKey: .mask)
        try container.encodeIfPresent(renderGroupID, forKey: .renderGroupID)
        try container.encode(points, forKey: .points)
    }
}
