import Foundation

/// A non-ink object on a page: a text box, an image, a shape or a PDF page.
public struct PageElement: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var layerID: UUID
    public var frame: ElementFrame
    public var zIndex: Int
    public var updatedAt: Date
    public var content: ElementContent
    /// A locked element cannot be moved, resized or rotated until it is
    /// unlocked. Locking is a view/edit rule, not a render rule.
    public var isLocked: Bool
    /// Optional so text boxes written before rich styling existed still open.
    public var textStyle: TextStyle?

    public init(
        id: UUID,
        layerID: UUID,
        frame: ElementFrame,
        zIndex: Int,
        updatedAt: Date,
        content: ElementContent,
        isLocked: Bool = false,
        textStyle: TextStyle? = nil
    ) {
        self.id = id
        self.layerID = layerID
        self.frame = frame
        self.zIndex = zIndex
        self.updatedAt = updatedAt
        self.content = content
        self.isLocked = isLocked
        self.textStyle = textStyle
    }

    private enum CodingKeys: String, CodingKey {
        case id, layerID, frame, zIndex, updatedAt, content, isLocked, textStyle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layerID = try container.decode(UUID.self, forKey: .layerID)
        frame = try container.decode(ElementFrame.self, forKey: .frame)
        zIndex = try container.decode(Int.self, forKey: .zIndex)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        content = try container.decode(ElementContent.self, forKey: .content)
        // Files written before element locking existed have no key.
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        textStyle = try container.decodeIfPresent(TextStyle.self, forKey: .textStyle)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layerID, forKey: .layerID)
        try container.encode(frame, forKey: .frame)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(content, forKey: .content)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encodeIfPresent(textStyle, forKey: .textStyle)
    }
}

/// What a `PageElement` shows. Binary payloads live in the notebook's `assets/` folder
/// and are referenced by their content-hash name.
public enum ElementContent: Sendable, Hashable, Codable {
    case text(String, fontName: String, fontSize: Double, color: RGBAColor)
    case image(assetName: String)
    case shape(kind: String, stroke: RGBAColor, fill: RGBAColor?, lineWidth: Double)
    case pdfPage(assetName: String, pageIndex: Int)
    /// A coloured note with wrapped text. `text` may be empty, which is a blank
    /// note waiting to be written on.
    case stickyNote(String, color: RGBAColor)
    /// A band that hides what is under it until it is revealed. Only its colour
    /// is stored; whether it is held up is a view state, not a page property.
    case tape(color: RGBAColor)

    private enum CodingKeys: String, CodingKey {
        case kind, text, fontName, fontSize, color, assetName, shapeKind, stroke, fill, lineWidth, pageIndex
    }

    private enum Kind: String, Codable {
        case text, image, shape, pdfPage, stickyNote, tape
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .text:
            self = .text(
                try container.decode(String.self, forKey: .text),
                fontName: try container.decode(String.self, forKey: .fontName),
                fontSize: try container.decode(Double.self, forKey: .fontSize),
                color: try container.decode(RGBAColor.self, forKey: .color)
            )
        case .image:
            self = .image(assetName: try container.decode(String.self, forKey: .assetName))
        case .shape:
            self = .shape(
                kind: try container.decode(String.self, forKey: .shapeKind),
                stroke: try container.decode(RGBAColor.self, forKey: .stroke),
                fill: try container.decodeIfPresent(RGBAColor.self, forKey: .fill),
                lineWidth: try container.decode(Double.self, forKey: .lineWidth)
            )
        case .pdfPage:
            self = .pdfPage(
                assetName: try container.decode(String.self, forKey: .assetName),
                pageIndex: try container.decode(Int.self, forKey: .pageIndex)
            )
        case .stickyNote:
            self = .stickyNote(
                try container.decode(String.self, forKey: .text),
                color: try container.decode(RGBAColor.self, forKey: .color)
            )
        case .tape:
            self = .tape(color: try container.decode(RGBAColor.self, forKey: .color))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text, fontName, fontSize, color):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encode(fontName, forKey: .fontName)
            try container.encode(fontSize, forKey: .fontSize)
            try container.encode(color, forKey: .color)
        case let .image(assetName):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(assetName, forKey: .assetName)
        case let .shape(kind, stroke, fill, lineWidth):
            try container.encode(Kind.shape, forKey: .kind)
            try container.encode(kind, forKey: .shapeKind)
            try container.encode(stroke, forKey: .stroke)
            try container.encodeIfPresent(fill, forKey: .fill)
            try container.encode(lineWidth, forKey: .lineWidth)
        case let .pdfPage(assetName, pageIndex):
            try container.encode(Kind.pdfPage, forKey: .kind)
            try container.encode(assetName, forKey: .assetName)
            try container.encode(pageIndex, forKey: .pageIndex)
        case let .stickyNote(text, color):
            try container.encode(Kind.stickyNote, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encode(color, forKey: .color)
        case let .tape(color):
            try container.encode(Kind.tape, forKey: .kind)
            try container.encode(color, forKey: .color)
        }
    }
}
