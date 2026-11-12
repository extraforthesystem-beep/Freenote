import CoreGraphics
import Foundation
import NoteCore

/// The geometry drawn by a board shape item.
public enum BoardShapeKind: String, Codable, CaseIterable, Sendable {
    case rectangle
    case roundedRectangle
    case ellipse
    case triangle
    case line
    case arrow
    case star
}

/// How a connector routes between its two items.
public enum BoardConnectorStyle: String, Codable, CaseIterable, Sendable {
    case straight
    case curved
    case elbow
}

/// The payload of a board item: one case per kind of object on a board.
public enum BoardItemContent: Codable, Hashable, Sendable {
    /// Freehand ink stored as page-independent stroke records.
    case ink(strokes: [StrokeRecord])

    /// A bitmap referenced by asset name.
    case image(assetName: String, frame: CGRect)

    /// A text box.
    case text(String, frame: CGRect, fontSize: Double, color: RGBAColor)

    /// A geometric shape. A nil fill means no fill.
    case shape(
        kind: BoardShapeKind,
        frame: CGRect,
        strokeColor: RGBAColor,
        fillColor: RGBAColor?,
        lineWidth: Double
    )

    /// A line between two other items.
    case connector(fromItemID: UUID, toItemID: UUID, style: BoardConnectorStyle)

    private enum CodingKeys: String, CodingKey {
        case kind
        case strokes
        case assetName
        case frame
        case string
        case fontSize
        case color
        case shapeKind
        case strokeColor
        case fillColor
        case lineWidth
        case fromItemID
        case toItemID
        case style
    }

    private enum Kind: String, Codable {
        case ink, image, text, shape, connector
    }

    /// Decodes one content case; an unknown case is rejected.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ink:
            self = .ink(strokes: try container.decode([StrokeRecord].self, forKey: .strokes))
        case .image:
            self = .image(
                assetName: try container.decode(String.self, forKey: .assetName),
                frame: try container.decode(CGRect.self, forKey: .frame)
            )
        case .text:
            self = .text(
                try container.decode(String.self, forKey: .string),
                frame: try container.decode(CGRect.self, forKey: .frame),
                fontSize: try container.decode(Double.self, forKey: .fontSize),
                color: try container.decode(RGBAColor.self, forKey: .color)
            )
        case .shape:
            self = .shape(
                kind: try container.decode(BoardShapeKind.self, forKey: .shapeKind),
                frame: try container.decode(CGRect.self, forKey: .frame),
                strokeColor: try container.decode(RGBAColor.self, forKey: .strokeColor),
                fillColor: try container.decodeIfPresent(RGBAColor.self, forKey: .fillColor),
                lineWidth: try container.decode(Double.self, forKey: .lineWidth)
            )
        case .connector:
            self = .connector(
                fromItemID: try container.decode(UUID.self, forKey: .fromItemID),
                toItemID: try container.decode(UUID.self, forKey: .toItemID),
                style: try container.decode(BoardConnectorStyle.self, forKey: .style)
            )
        }
    }

    /// Encodes one content case with a `kind` discriminator.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .ink(strokes):
            try container.encode(Kind.ink, forKey: .kind)
            try container.encode(strokes, forKey: .strokes)
        case let .image(assetName, frame):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(assetName, forKey: .assetName)
            try container.encode(frame, forKey: .frame)
        case let .text(string, frame, fontSize, color):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(string, forKey: .string)
            try container.encode(frame, forKey: .frame)
            try container.encode(fontSize, forKey: .fontSize)
            try container.encode(color, forKey: .color)
        case let .shape(kind, frame, strokeColor, fillColor, lineWidth):
            try container.encode(Kind.shape, forKey: .kind)
            try container.encode(kind, forKey: .shapeKind)
            try container.encode(frame, forKey: .frame)
            try container.encode(strokeColor, forKey: .strokeColor)
            try container.encodeIfPresent(fillColor, forKey: .fillColor)
            try container.encode(lineWidth, forKey: .lineWidth)
        case let .connector(fromItemID, toItemID, style):
            try container.encode(Kind.connector, forKey: .kind)
            try container.encode(fromItemID, forKey: .fromItemID)
            try container.encode(toItemID, forKey: .toItemID)
            try container.encode(style, forKey: .style)
        }
    }
}

/// One object on a board, with shared metadata and one content payload.
public struct BoardItem: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity used by connectors, selection and merging.
    public var id: UUID
    /// Draw order; larger values are drawn later.
    public var zIndex: Int
    /// Locked items cannot be moved, resized or aligned.
    public var isLocked: Bool
    /// When the item first appeared.
    public var createdAt: Date
    /// When the item last changed; the merge winner for a given ID.
    public var updatedAt: Date
    /// The item's payload.
    public var content: BoardItemContent

    /// Creates an item. `updatedAt` defaults to `createdAt`.
    public init(
        id: UUID = UUID(),
        zIndex: Int = 0,
        isLocked: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        content: BoardItemContent
    ) {
        self.id = id
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.content = content
    }

    /// The frame of an image, text or shape item; nil for ink and connectors.
    public var frame: CGRect? {
        switch content {
        case .image(_, let frame):
            return frame
        case .text(_, let frame, _, _):
            return frame
        case .shape(_, let frame, _, _, _):
            return frame
        case .ink, .connector:
            return nil
        }
    }

    /// Approximate world bounds; nil for connectors, whose geometry depends on other items.
    public var bounds: CGRect? {
        switch content {
        case let .ink(strokes):
            return Self.inkBounds(strokes)
        case .image(_, let frame):
            return frame
        case .text(_, let frame, _, _):
            return frame
        case .shape(_, let frame, _, _, _):
            return frame
        case .connector:
            return nil
        }
    }

    /// Replaces the frame of a frame-backed item, leaving other payload fields alone.
    mutating func setFrame(_ newFrame: CGRect) {
        switch content {
        case let .image(assetName, _):
            content = .image(assetName: assetName, frame: newFrame)
        case let .text(string, _, fontSize, color):
            content = .text(string, frame: newFrame, fontSize: fontSize, color: color)
        case let .shape(kind, _, strokeColor, fillColor, lineWidth):
            content = .shape(
                kind: kind,
                frame: newFrame,
                strokeColor: strokeColor,
                fillColor: fillColor,
                lineWidth: lineWidth
            )
        case .ink, .connector:
            break
        }
    }

    private static func inkBounds(_ strokes: [StrokeRecord]) -> CGRect? {
        var result: CGRect?
        for stroke in strokes {
            let transform = stroke.transform.count == StrokeRecord.transformElementCount
                ? stroke.transform
                : StrokeRecord.identityTransform
            let padding = max(0, stroke.tool.width) / 2
            for point in stroke.points {
                let x = transform[0] * point.x + transform[2] * point.y + transform[4]
                let y = transform[1] * point.x + transform[3] * point.y + transform[5]
                let pointBounds = CGRect(
                    x: x - padding,
                    y: y - padding,
                    width: padding * 2,
                    height: padding * 2
                )
                result = result.map { $0.union(pointBounds) } ?? pointBounds
            }
        }
        return result
    }
}
