import Foundation

/// Where the caret should land after a structural text edit.
///
/// Offsets are UTF-16 offsets, matching `UITextView.selectedRange`, so an
/// editor can hand the value straight back to the system text view.
public struct TextCaretPosition: Hashable, Sendable {
    /// The block that now owns the caret.
    public var blockID: UUID
    /// The item inside a list or checklist block; always 0 for text blocks.
    public var itemIndex: Int
    /// The UTF-16 offset into the block's text, or into one item's text.
    public var offset: Int

    /// Creates a caret position.
    public init(blockID: UUID, itemIndex: Int = 0, offset: Int = 0) {
        self.blockID = blockID
        self.itemIndex = itemIndex
        self.offset = offset
    }
}

// MARK: - Splitting

extension TextDocument {
    /// Splits the block with `id` at the caret so the text after it moves into a
    /// new following block, and returns where the caret should go.
    ///
    /// Paragraphs, quotes and headings split into a text block followed by a
    /// paragraph. Bullet lists, numbered lists and checklists keep their kind in
    /// the new block, and an empty item ends the list: it becomes a paragraph
    /// instead. Code blocks keep their newlines and are never split. Images,
    /// dividers and unknown blocks return `nil`.
    @discardableResult
    public mutating func splitBlock(
        id: UUID,
        itemIndex: Int = 0,
        offset: Int
    ) -> TextCaretPosition? {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return nil }

        switch blocks[index].kind {
        case let .paragraph(text):
            let parts = Self.split(text, at: offset)
            blocks[index].kind = .paragraph(text: parts.head)
            return insertParagraph(parts.tail, after: index)

        case let .quote(text):
            let parts = Self.split(text, at: offset)
            blocks[index].kind = .quote(text: parts.head)
            return insertParagraph(parts.tail, after: index)

        case let .heading(level, text):
            // A heading continues as a paragraph, the usual writing flow.
            let parts = Self.split(text, at: offset)
            blocks[index].kind = .heading(level: level, text: parts.head)
            return insertParagraph(parts.tail, after: index)

        case let .bulletList(items):
            return splitList(
                blockIndex: index,
                items: items,
                itemIndex: itemIndex,
                offset: offset,
                rebuild: { .bulletList(items: $0) }
            )

        case let .numberedList(items):
            return splitList(
                blockIndex: index,
                items: items,
                itemIndex: itemIndex,
                offset: offset,
                rebuild: { .numberedList(items: $0) }
            )

        case let .checklist(items):
            return splitChecklist(
                blockIndex: index,
                items: items,
                itemIndex: itemIndex,
                offset: offset
            )

        case .code, .image, .divider:
            return nil
        }
    }

    /// Inserts a block of `kind` directly after the block with `id`.
    @discardableResult
    public mutating func insertBlock(after id: UUID, kind: TextBlockKind) -> TextCaretPosition? {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return nil }
        let block = TextBlock(kind: kind, style: blocks[index].style)
        insert(block, at: index + 1)
        return TextCaretPosition(blockID: block.id)
    }

    private mutating func insertParagraph(_ text: String, after index: Int) -> TextCaretPosition {
        let block = TextBlock(kind: .paragraph(text: text), style: blocks[index].style)
        insert(block, at: index + 1)
        return TextCaretPosition(blockID: block.id)
    }

    /// Shared list split: the current block keeps the items above the caret, the
    /// new block takes the rest.
    private mutating func splitList(
        blockIndex index: Int,
        items: [ListItem],
        itemIndex: Int,
        offset: Int,
        rebuild: ([ListItem]) -> TextBlockKind
    ) -> TextCaretPosition? {
        guard !items.isEmpty else { return endList(blockIndex: index, rebuild: rebuild) }
        let item = min(max(itemIndex, 0), items.count - 1)

        // Return on an empty item leaves the list.
        guard !items[item].text.isEmpty else {
            var remaining = items
            remaining.remove(at: item)
            if remaining.isEmpty {
                blocks[index].kind = .paragraph(text: "")
                return TextCaretPosition(blockID: blocks[index].id)
            }
            blocks[index].kind = rebuild(remaining)
            return insertParagraph("", after: index)
        }

        let parts = Self.split(items[item].text, at: offset)
        var head = Array(items.prefix(item))
        head.append(ListItem(id: items[item].id, text: parts.head))
        let tail = [ListItem(text: parts.tail)] + Array(items.dropFirst(item + 1))

        blocks[index].kind = rebuild(head)
        let block = TextBlock(kind: rebuild(tail), style: blocks[index].style)
        insert(block, at: index + 1)
        return TextCaretPosition(blockID: block.id)
    }

    private mutating func splitChecklist(
        blockIndex index: Int,
        items: [ChecklistItem],
        itemIndex: Int,
        offset: Int
    ) -> TextCaretPosition? {
        guard !items.isEmpty else {
            blocks[index].kind = .checklist(items: [ChecklistItem(text: "")])
            return TextCaretPosition(blockID: blocks[index].id)
        }
        let item = min(max(itemIndex, 0), items.count - 1)

        guard !items[item].text.isEmpty else {
            var remaining = items
            remaining.remove(at: item)
            if remaining.isEmpty {
                blocks[index].kind = .paragraph(text: "")
                return TextCaretPosition(blockID: blocks[index].id)
            }
            blocks[index].kind = .checklist(items: remaining)
            return insertParagraph("", after: index)
        }

        let parts = Self.split(items[item].text, at: offset)
        var head = Array(items.prefix(item))
        head.append(ChecklistItem(id: items[item].id, text: parts.head, isChecked: items[item].isChecked))
        let tail = [ChecklistItem(text: parts.tail)] + Array(items.dropFirst(item + 1))

        blocks[index].kind = .checklist(items: head)
        let block = TextBlock(kind: .checklist(items: tail), style: blocks[index].style)
        insert(block, at: index + 1)
        return TextCaretPosition(blockID: block.id)
    }

    private mutating func endList(
        blockIndex index: Int,
        rebuild: ([ListItem]) -> TextBlockKind
    ) -> TextCaretPosition? {
        blocks[index].kind = .paragraph(text: "")
        return TextCaretPosition(blockID: blocks[index].id)
    }
}

// MARK: - Merging

extension TextDocument {
    /// Merges the block with `id` into the block above it, or turns a list,
    /// checklist, quote or heading into a paragraph first.
    ///
    /// Returns the block and caret offset that should take focus, or `nil` when
    /// there is nothing above to merge into.
    @discardableResult
    public mutating func mergeBlockBackward(
        id: UUID,
        itemIndex: Int = 0
    ) -> TextCaretPosition? {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return nil }
        let kind = blocks[index].kind

        // Inside a list: join this item onto the one above it.
        if itemIndex > 0 {
            switch kind {
            case let .bulletList(items):
                return mergeItems(
                    blockIndex: index,
                    items: items,
                    itemIndex: itemIndex,
                    rebuild: { .bulletList(items: $0) }
                )
            case let .numberedList(items):
                return mergeItems(
                    blockIndex: index,
                    items: items,
                    itemIndex: itemIndex,
                    rebuild: { .numberedList(items: $0) }
                )
            case let .checklist(items):
                return mergeChecklistItems(blockIndex: index, items: items, itemIndex: itemIndex)
            default:
                break
            }
        }

        // At the start of a structured block: become a paragraph first.
        switch kind {
        case .heading, .quote, .bulletList, .numberedList, .checklist:
            blocks[index].kind = .paragraph(text: kind.text)
            return TextCaretPosition(blockID: id)
        case .paragraph, .code, .image, .divider:
            break
        }

        guard index > 0 else { return nil }
        let previousIndex = index - 1
        let moved = blocks[index]
        let movedText = moved.kind.text

        switch blocks[previousIndex].kind {
        case let .paragraph(text):
            blocks[previousIndex].kind = .paragraph(text: text + movedText)
            return finishMerge(at: index, into: previousIndex, offset: text.utf16.count)

        case let .heading(level, text):
            blocks[previousIndex].kind = .heading(level: level, text: text + movedText)
            return finishMerge(at: index, into: previousIndex, offset: text.utf16.count)

        case let .quote(text):
            blocks[previousIndex].kind = .quote(text: text + movedText)
            return finishMerge(at: index, into: previousIndex, offset: text.utf16.count)

        case let .code(text, language):
            let separator = text.isEmpty || movedText.isEmpty || text.hasSuffix("\n") ? "" : "\n"
            blocks[previousIndex].kind = .code(text: text + separator + movedText, language: language)
            return finishMerge(
                at: index,
                into: previousIndex,
                offset: (text + separator).utf16.count
            )

        case let .bulletList(items):
            blocks[previousIndex].kind = .bulletList(items: items + [ListItem(text: movedText)])
            return finishMerge(at: index, into: previousIndex, itemIndex: items.count)

        case let .numberedList(items):
            blocks[previousIndex].kind = .numberedList(items: items + [ListItem(text: movedText)])
            return finishMerge(at: index, into: previousIndex, itemIndex: items.count)

        case let .checklist(items):
            blocks[previousIndex].kind = .checklist(items: items + [ChecklistItem(text: movedText)])
            return finishMerge(at: index, into: previousIndex, itemIndex: items.count)

        case .image, .divider:
            return nil
        }
    }

    private mutating func mergeItems(
        blockIndex index: Int,
        items: [ListItem],
        itemIndex: Int,
        rebuild: ([ListItem]) -> TextBlockKind
    ) -> TextCaretPosition? {
        let item = min(max(itemIndex, 1), items.count - 1)
        guard items.indices.contains(item - 1), items.indices.contains(item) else { return nil }
        let caretOffset = items[item - 1].text.utf16.count

        var updated = items
        updated[item - 1].text += updated[item].text
        updated.remove(at: item)
        blocks[index].kind = rebuild(updated)
        return TextCaretPosition(blockID: blocks[index].id, itemIndex: item - 1, offset: caretOffset)
    }

    private mutating func mergeChecklistItems(
        blockIndex index: Int,
        items: [ChecklistItem],
        itemIndex: Int
    ) -> TextCaretPosition? {
        let item = min(max(itemIndex, 1), items.count - 1)
        guard items.indices.contains(item - 1), items.indices.contains(item) else { return nil }
        let caretOffset = items[item - 1].text.utf16.count

        var updated = items
        updated[item - 1].text += updated[item].text
        updated.remove(at: item)
        blocks[index].kind = .checklist(items: updated)
        return TextCaretPosition(blockID: blocks[index].id, itemIndex: item - 1, offset: caretOffset)
    }

    private mutating func finishMerge(
        at index: Int,
        into previousIndex: Int,
        itemIndex: Int = 0,
        offset: Int = 0
    ) -> TextCaretPosition {
        let blockID = blocks[previousIndex].id
        blocks.remove(at: index)
        return TextCaretPosition(blockID: blockID, itemIndex: itemIndex, offset: offset)
    }
}

// MARK: - Kind changes

extension TextDocument {
    /// Replaces the block's kind, keeping its text where the new kind can hold
    /// it. Returns `false` when the block or the target kind is not convertible.
    @discardableResult
    public mutating func convertBlock(
        id: UUID,
        to tag: TextBlockKindTag,
        headingLevel: Int = 2
    ) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return false }
        let text = blocks[index].kind.text

        switch tag {
        case .paragraph:
            blocks[index].kind = .paragraph(text: text)
        case .heading:
            blocks[index].kind = .heading(level: min(max(headingLevel, 1), 6), text: text)
        case .quote:
            blocks[index].kind = .quote(text: text)
        case .code:
            blocks[index].kind = .code(text: text, language: nil)
        case .bulletList:
            blocks[index].kind = .bulletList(items: Self.items(from: text))
        case .numberedList:
            blocks[index].kind = .numberedList(items: Self.items(from: text))
        case .checklist:
            blocks[index].kind = .checklist(items: Self.items(from: text).map { ChecklistItem(text: $0.text) })
        case .image, .divider:
            return false
        }
        return true
    }

    /// The lines of `text` as list items; empty text is one empty item.
    private static func items(from text: String) -> [ListItem] {
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        return lines.map { ListItem(text: $0) }
    }
}

// MARK: - Text helpers

extension TextDocument {
    /// Splits `text` at a UTF-16 offset, clamping the offset into range.
    static func split(_ text: String, at offset: Int) -> (head: String, tail: String) {
        let limited = min(max(offset, 0), text.utf16.count)
        let index = String.Index(utf16Offset: limited, in: text)
        return (String(text[text.startIndex..<index]), String(text[index...]))
    }
}
