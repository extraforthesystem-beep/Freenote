import Foundation

/// A named paper size. Sizes are in page points (72 per inch), portrait.
public enum PaperSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case a3, a4, a5, a6, a7, letter, tabloid
    /// A 3:4 page that fills an iPad screen without letterboxing. Codable
    /// stores the raw value, so pages saved before it still decode.
    case screen

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .a3: "A3"
        case .a4: "A4"
        case .a5: "A5"
        case .a6: "A6"
        case .a7: "A7"
        case .letter: "Letter"
        case .tabloid: "Tabloid"
        case .screen: "Screen (Optimised)"
        }
    }

    /// Portrait width and height in points.
    public var portraitSize: (width: Double, height: Double) {
        switch self {
        case .a3: (842, 1191)
        case .a4: (595, 842)
        case .a5: (420, 595)
        case .a6: (298, 420)
        case .a7: (210, 298)
        case .letter: (612, 792)
        case .tabloid: (792, 1224)
        // 3:4, the shape of an iPad in portrait.
        case .screen: (768, 1024)
        }
    }

    public func size(_ orientation: PageOrientation) -> (width: Double, height: Double) {
        let portrait = portraitSize
        switch orientation {
        case .portrait: return portrait
        case .landscape: return (portrait.height, portrait.width)
        }
    }

    /// The named size and orientation matching a page, if any (±1 pt).
    public static func match(width: Double, height: Double) -> (PaperSize, PageOrientation)? {
        for size in allCases {
            for orientation in PageOrientation.allCases {
                let candidate = size.size(orientation)
                if abs(candidate.width - width) <= 1, abs(candidate.height - height) <= 1 {
                    return (size, orientation)
                }
            }
        }
        return nil
    }
}

public enum PageOrientation: String, CaseIterable, Codable, Sendable, Identifiable {
    case portrait, landscape
    public var id: String { rawValue }
    public var displayName: String { self == .portrait ? "Portrait" : "Landscape" }
}

/// The kinds of content "Delete Specific Items" can clear from a page.
public enum PageItemKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case pen, pencil, highlighter, text, shapes, images, stickyNotes, tape

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pen: "Pen"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .shapes: "Shapes"
        case .images: "Images"
        case .stickyNotes: "Sticky Notes"
        case .tape: "Tape"
        }
    }

    /// The kind a stroke belongs to: highlighter first, then pencil-like inks,
    /// everything else is pen.
    public static func of(_ stroke: StrokeRecord) -> PageItemKind {
        if stroke.tool.isHighlighter { return .highlighter }
        let ink = stroke.tool.inkType.lowercased()
        if ink.contains("pencil") || ink.contains("crayon") { return .pencil }
        return .pen
    }

    /// The kind an element belongs to, or nil for content that is never
    /// cleared this way (imported PDF pages).
    public static func of(_ element: PageElement) -> PageItemKind? {
        switch element.content {
        case .text: .text
        case .image: .images
        case .shape: .shapes
        case .stickyNote: .stickyNotes
        case .tape: .tape
        case .pdfPage: nil
        }
    }
}
