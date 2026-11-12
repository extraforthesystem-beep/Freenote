import Foundation

/// A platform-neutral page layout plan for a ``TextDocument``.
///
/// The layout is greedy and top-to-bottom: blocks are measured, placed in order,
/// and a block that would overflow the current page starts a new one. Blocks are
/// never split, so a block taller than a whole page is placed alone at its full
/// measured height and may overflow; a renderer can clip or scale that frame.
public enum PDFTextLayout: Sendable {
    /// A page size in points.
    public struct PageSize: Codable, Hashable, Sendable {
        /// Page width in points.
        public var width: Double
        /// Page height in points.
        public var height: Double

        /// Creates a page size in points.
        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        /// US Letter, 612 x 792 points.
        public static let letter = PageSize(width: 612, height: 792)
        /// ISO A4, 595.28 x 841.89 points.
        public static let a4 = PageSize(width: 595.28, height: 841.89)
    }

    /// Page margins in points.
    public struct Insets: Codable, Hashable, Sendable {
        /// Top margin in points.
        public var top: Double
        /// Leading (left) margin in points.
        public var leading: Double
        /// Bottom margin in points.
        public var bottom: Double
        /// Trailing (right) margin in points.
        public var trailing: Double

        /// Creates margins; every side defaults to zero.
        public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
            self.top = top
            self.leading = leading
            self.bottom = bottom
            self.trailing = trailing
        }
    }

    /// Layout measurements and page geometry.
    public struct Options: Codable, Hashable, Sendable {
        /// The page size.
        public var pageSize: PageSize
        /// The page margins.
        public var margins: Insets
        /// Vertical space between blocks, in points.
        public var blockSpacing: Double
        /// Width reserved for a list marker or checkbox, in points.
        public var listIndent: Double
        /// Vertical space between list items, in points.
        public var listItemSpacing: Double
        /// Height of a divider rule, in points.
        public var dividerHeight: Double

        /// Creates options with US Letter geometry and 54-point margins.
        public init(
            pageSize: PageSize = .letter,
            margins: Insets = Insets(top: 54, leading: 54, bottom: 54, trailing: 54),
            blockSpacing: Double = 12,
            listIndent: Double = 24,
            listItemSpacing: Double = 0,
            dividerHeight: Double = 1
        ) {
            self.pageSize = pageSize
            self.margins = margins
            self.blockSpacing = blockSpacing
            self.listIndent = listIndent
            self.listItemSpacing = listItemSpacing
            self.dividerHeight = dividerHeight
        }

        /// US Letter with the default margins.
        public static let letter = Options()
        /// ISO A4 with the default margins.
        public static let a4 = Options(pageSize: .a4)
    }

    /// A rectangle in page coordinates, with the origin at the top-left.
    public struct Rect: Codable, Hashable, Sendable {
        /// Left edge in points.
        public var x: Double
        /// Top edge in points.
        public var y: Double
        /// Width in points.
        public var width: Double
        /// Height in points.
        public var height: Double

        /// Creates a rectangle in points.
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// The right edge.
        public var maxX: Double { x + width }
        /// The bottom edge.
        public var maxY: Double { y + height }
    }

    /// Where one block is drawn.
    public struct Frame: Codable, Hashable, Identifiable, Sendable {
        /// The block this frame belongs to.
        public var blockID: UUID
        /// Zero-based page index.
        public var pageIndex: Int
        /// The frame in page coordinates.
        public var rect: Rect
        /// The block kind, so a renderer can draw without looking it up.
        public var kind: TextBlockKindTag

        /// `blockID`, satisfying `Identifiable`.
        public var id: UUID { blockID }

        /// Creates a frame.
        public init(blockID: UUID, pageIndex: Int, rect: Rect, kind: TextBlockKindTag) {
            self.blockID = blockID
            self.pageIndex = pageIndex
            self.rect = rect
            self.kind = kind
        }
    }

    /// The complete layout: page count, page size and one frame per block.
    public struct Plan: Codable, Hashable, Sendable {
        /// The page size the frames are laid out in.
        public var pageSize: PageSize
        /// Number of pages; at least one, even for an empty document.
        public var pageCount: Int
        /// One frame per block, in reading order.
        public var frames: [Frame]

        /// Creates a plan.
        public init(pageSize: PageSize, pageCount: Int, frames: [Frame]) {
            self.pageSize = pageSize
            self.pageCount = pageCount
            self.frames = frames
        }

        /// The frames on a zero-based page, in reading order.
        public func frames(onPage index: Int) -> [Frame] {
            frames.filter { $0.pageIndex == index }
        }
    }

    /// Lays out `document` greedily, one block at a time.
    ///
    /// `measureText` is called for headings, paragraphs, quotes and code with the
    /// block, its text and the available content width, and once per list or
    /// checklist item with the item text and the width left after `listIndent`.
    /// It returns a height in points. `imageHeight` supplies the height of an
    /// image block; the block's `width` is not used by this layout.
    public static func plan(
        for document: TextDocument,
        options: Options = .letter,
        measureText: (TextBlock, String, Double) -> Double,
        imageHeight: (TextBlock) -> Double
    ) -> Plan {
        let pageSize = options.pageSize
        let contentWidth = max(0, pageSize.width - options.margins.leading - options.margins.trailing)
        let contentHeight = max(0, pageSize.height - options.margins.top - options.margins.bottom)
        let contentX = options.margins.leading
        let contentTop = options.margins.top
        let contentBottom = contentTop + contentHeight
        let blockSpacing = max(0, options.blockSpacing)

        var frames: [Frame] = []
        var pageIndex = 0
        var y = contentTop
        var pageHasFrames = false

        for block in document.blocks {
            let height = max(
                0,
                blockHeight(
                    block,
                    contentWidth: contentWidth,
                    options: options,
                    measureText: measureText,
                    imageHeight: imageHeight
                )
            )

            if pageHasFrames, y + height > contentBottom {
                pageIndex += 1
                y = contentTop
                pageHasFrames = false
            }

            let rect = Rect(x: contentX, y: y, width: contentWidth, height: height)
            frames.append(
                Frame(blockID: block.id, pageIndex: pageIndex, rect: rect, kind: block.tag)
            )
            pageHasFrames = true
            y += height + blockSpacing
        }

        return Plan(pageSize: pageSize, pageCount: max(1, pageIndex + 1), frames: frames)
    }

    // MARK: - Measurement

    private static func blockHeight(
        _ block: TextBlock,
        contentWidth: Double,
        options: Options,
        measureText: (TextBlock, String, Double) -> Double,
        imageHeight: (TextBlock) -> Double
    ) -> Double {
        switch block.kind {
        case let .heading(_, text), let .paragraph(text), let .quote(text):
            measureText(block, text, contentWidth)
        case let .code(text, _):
            measureText(block, text, contentWidth)
        case let .bulletList(items), let .numberedList(items):
            listHeight(
                items: items,
                block: block,
                contentWidth: contentWidth,
                options: options,
                measureText: measureText
            )
        case let .checklist(items):
            listHeight(
                items: items.map(\.text),
                block: block,
                contentWidth: contentWidth,
                options: options,
                measureText: measureText
            )
        case .image:
            imageHeight(block)
        case .divider:
            options.dividerHeight
        }
    }

    /// Lists are measured item by item, with the marker indent removed from the width.
    private static func listHeight(
        items: [String],
        block: TextBlock,
        contentWidth: Double,
        options: Options,
        measureText: (TextBlock, String, Double) -> Double
    ) -> Double {
        let itemWidth = max(0, contentWidth - options.listIndent)
        let itemSpacing = max(0, options.listItemSpacing)
        var total = 0.0
        for (index, item) in items.enumerated() {
            if index > 0 { total += itemSpacing }
            total += max(0, measureText(block, item, itemWidth))
        }
        return total
    }
}
