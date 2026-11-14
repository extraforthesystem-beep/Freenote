import SwiftUI
import TextDocKit
#if os(iOS)
import UIKit
#endif

/// Edits one `TextDocument` as a stack of typed blocks.
///
/// The view owns a local copy while the user types and saves it back through
/// `TextDocModel` after a short debounce. Done, leaving the screen and the app
/// going to the background all flush the latest copy.
struct TextDocumentEditorView: View {
    /// Comfortable measure for long-form reading on iPad.
    static let readingWidth: CGFloat = 720

    let model: TextDocModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var document: TextDocument
    @State private var focusedKey: BlockKey?
    @State private var focusRequest: FocusRequest?
    @State private var scrollTarget: UUID?
    @State private var history = TextDocumentHistory()

    /// The metadata row's word count. It trails the text by `wordCountDelay`
    /// so a keystroke never re-joins the whole document.
    @State private var wordCount: Int

    @State private var pendingSave: Task<Void, Never>?
    @State private var editGeneration = 0
    @State private var hasUnsavedChanges = false
    @State private var lastSavedAt: Date?
    @State private var isSaving = false

    init(model: TextDocModel, document: TextDocument) {
        self.model = model
        _document = State(initialValue: document)
        _wordCount = State(initialValue: Self.words(in: document))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleField
                    metadata
                    Divider()
                        .padding(.bottom, 6)
                    blocks
                    addBlockButton
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
                .frame(maxWidth: Self.readingWidth, alignment: .leading)
                .background(pageFill)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColor.groupedBackground)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                // Scroll first, then let the row take focus: in the lazy list a
                // row that is off screen does not exist yet, and
                // `BlockTextEditor` retries a pending focus request when the
                // view moves into the window.
                AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) {
                    proxy.scrollTo(target, anchor: .center)
                }
                scrollTarget = nil
            }
        }
        .navigationTitle(document.title.isEmpty ? "Untitled" : document.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(alignment: .topLeading) { historyShortcuts }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { finishEditing() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!history.canUndo)
                .accessibilityLabel("Undo")
                .help("Undo")

                Button {
                    redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!history.canRedo)
                .accessibilityLabel("Redo")
                .help("Redo")

                Menu {
                    addBlockMenuItems
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add block")
            }
        }
        .onChange(of: document) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            // `.inactive` keeps foreground time for a quick write;
            // `.background` can be suspended at any moment, so it needs the
            // background assertion to finish.
            flush(holdingBackgroundTime: phase == .background)
        }
        .onDisappear { flush(holdingBackgroundTime: true) }
        .task {
            // A new document opens ready to type in its first block.
            guard focusedKey == nil else { return }
            if document.blocks.isEmpty {
                focusFirstBlock()
            } else if document.blocks.count == 1, document.blocks[0].text.isEmpty {
                requestFocus(BlockKey(blockID: document.blocks[0].id), caret: 0)
            }
        }
        // The word count is presentation only, so it waits for a pause in
        // typing instead of re-joining every block on each keystroke. `.task`
        // cancels the previous count, so a burst of keys costs one count.
        .task(id: document.blocks) {
            do {
                try await Task.sleep(for: .milliseconds(Self.wordCountDelay))
            } catch {
                return
            }
            wordCount = Self.words(in: document)
        }
        .alert("Text Document Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    // MARK: - Page

    private var pageFill: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(pageColor)
            .shadow(color: .black.opacity(0.06), radius: 14, y: 4)
    }

    private var pageColor: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }

    private var titleField: some View {
        TextField("Untitled", text: documentTitle)
            .font(.system(size: 32, weight: .bold))
            .textFieldStyle(.plain)
            .submitLabel(.next)
            .onSubmit { focusFirstBlock() }
            .accessibilityLabel("Document title")
    }

    /// The title as an undoable typing edit.
    private var documentTitle: Binding<String> {
        Binding(
            get: { document.title },
            set: { newValue in
                guard newValue != document.title else { return }
                history.recordTyping(document)
                document.title = newValue
                hasUnsavedChanges = true
            }
        )
    }

    /// The blocks as undoable typing edits. Structural edits change `document`
    /// directly and record their own snapshots.
    private var blockList: Binding<[TextBlock]> {
        Binding(
            get: { document.blocks },
            set: { newValue in
                guard newValue != document.blocks else { return }
                history.recordTyping(document)
                document.blocks = newValue
                hasUnsavedChanges = true
            }
        )
    }

    /// Puts the caret in the first block, creating one when the page is empty.
    private func focusFirstBlock() {
        if document.blocks.isEmpty {
            addBlock(.paragraph(text: ""))
            return
        }
        requestFocus(BlockKey(blockID: document.blocks[0].id), caret: 0)
    }

    private var metadata: some View {
        HStack(spacing: 14) {
            Label("\(wordCount) word\(wordCount == 1 ? "" : "s")", systemImage: "text.word.spacing")
            Label(
                updatedDate.formatted(date: .abbreviated, time: .shortened),
                systemImage: "clock"
            )
            if isSaving {
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
            } else if hasUnsavedChanges {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Saved", systemImage: "checkmark.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var blocks: some View {
        // Lazy: a long page only builds the rows near the viewport, so a
        // keystroke costs one row instead of the whole document.
        LazyVStack(alignment: .leading, spacing: 0) {
            if document.blocks.isEmpty {
                emptyBlocks
            } else {
                ForEach(blockList) { $block in
                    BlockRow(
                        block: $block,
                        focusedKey: focusedKey,
                        focusRequest: focusRequest?.key.blockID == block.id ? focusRequest : nil,
                        canMoveUp: document.blocks.first?.id != block.id,
                        canMoveDown: document.blocks.last?.id != block.id,
                        onFocus: { focusChanged($0, isFocused: true) },
                        onBlur: { focusChanged($0, isFocused: false) },
                        onReturn: handleReturn,
                        onMerge: handleMerge,
                        onConvert: { convert(block.id, to: $0) },
                        onInsertBelow: { insertBelow(block.id) },
                        onMove: { moveBlock(block.id, by: $0) },
                        onDelete: { deleteBlock(block.id) },
                        onChecklistChange: {
                            history.recordStructural(document)
                            hasUnsavedChanges = true
                        }
                    )
                    // The row's body is skipped when its block, focus and
                    // menu state are unchanged, so only the edited row's
                    // text view is updated.
                    .equatable()
                    .id(block.id)
                    .dropDestination(for: String.self) { payloads, _ in
                        guard let raw = payloads.first,
                              let sourceID = UUID(uuidString: raw)
                        else { return false }
                        return moveBlock(sourceID, before: block.id)
                    }
                }
            }
        }
    }

    private var emptyBlocks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This page is empty.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Start Writing") {
                addBlock(.paragraph(text: ""))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 28)
    }

    private var addBlockButton: some View {
        Menu {
            addBlockMenuItems
        } label: {
            Label("Add Block", systemImage: "plus.circle")
                .font(.callout)
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var addBlockMenuItems: some View {
        ForEach(BlockStyleChoice.allCases) { choice in
            Button {
                addBlock(choice.kind)
            } label: {
                Label(choice.title, systemImage: choice.symbol)
            }
        }
        Divider()
        Button("Divider", systemImage: "minus") {
            addBlock(.divider)
        }
    }

    // MARK: - Editing

    /// How long typing has to pause before the word count catches up.
    private static let wordCountDelay = 300

    private static func words(in document: TextDocument) -> Int {
        document.plainText.split(whereSeparator: { $0.isWhitespace }).count
    }

    private var updatedDate: Date {
        lastSavedAt ?? document.updatedAt
    }

    private func addBlock(_ kind: TextBlockKind) {
        let before = document
        let block = TextBlock(kind: kind)
        if let focusedKey,
           let index = document.blocks.firstIndex(where: { $0.id == focusedKey.blockID }) {
            document.insert(block, at: index + 1)
        } else {
            document.insert(block, at: document.blocks.count)
        }
        recordStructuralChange(from: before)
        requestFocus(BlockKey(blockID: block.id, itemIndex: 0), caret: 0)
    }

    private func insertBelow(_ blockID: UUID) {
        let before = document
        guard let caret = document.insertBlock(after: blockID, kind: .paragraph(text: "")) else {
            return
        }
        recordStructuralChange(from: before)
        requestFocus(BlockKey(blockID: caret.blockID, itemIndex: caret.itemIndex), caret: caret.offset)
    }

    private func moveBlock(_ id: UUID, by offset: Int) {
        let before = document
        guard let index = document.blocks.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard document.blocks.indices.contains(destination) else { return }
        document.moveBlock(from: index, to: destination)
        recordStructuralChange(from: before)
        focusedKey = BlockKey(blockID: id, itemIndex: focusedKey?.itemIndex ?? 0)
    }

    /// Moves a dragged block in front of the block it was dropped on.
    @discardableResult
    private func moveBlock(_ sourceID: UUID, before targetID: UUID) -> Bool {
        let before = document
        guard document.moveBlock(sourceID, before: targetID) else { return false }
        recordStructuralChange(from: before)
        focusedKey = BlockKey(blockID: sourceID, itemIndex: 0)
        return true
    }

    private func deleteBlock(_ id: UUID) {
        let before = document
        guard document.removeBlock(id: id) != nil else { return }
        if focusedKey?.blockID == id { focusedKey = nil }
        recordStructuralChange(from: before)
    }

    private func convert(_ blockID: UUID, to choice: BlockStyleChoice) {
        let before = document
        guard document.convertBlock(id: blockID, to: choice.tag, headingLevel: choice.headingLevel)
        else { return }
        recordStructuralChange(from: before)
        requestFocus(BlockKey(blockID: blockID, itemIndex: 0), caret: 0)
    }

    private func handleReturn(_ key: BlockKey, offset: Int) {
        let before = document
        guard let caret = document.splitBlock(
            id: key.blockID,
            itemIndex: key.itemIndex,
            offset: offset
        ) else { return }
        recordStructuralChange(from: before)
        requestFocus(
            BlockKey(blockID: caret.blockID, itemIndex: caret.itemIndex),
            caret: caret.offset
        )
    }

    private func handleMerge(_ key: BlockKey) {
        let before = document
        guard let caret = document.mergeBlockBackward(id: key.blockID, itemIndex: key.itemIndex)
        else { return }
        recordStructuralChange(from: before)
        requestFocus(
            BlockKey(blockID: caret.blockID, itemIndex: caret.itemIndex),
            caret: caret.offset
        )
    }

    /// Pushes one undo step for a structural edit that has already been applied
    /// to `document`.
    private func recordStructuralChange(from before: TextDocument) {
        guard document != before else { return }
        history.recordStructural(before)
        // Mark dirty now: a background transition in this same run loop must
        // flush the new structure even before `onChange` schedules its save.
        hasUnsavedChanges = true
    }

    private func requestFocus(_ key: BlockKey, caret: Int) {
        focusedKey = key
        focusRequest = FocusRequest(key: key, caretOffset: caret, token: UUID())
        scrollTarget = key.blockID
    }

    private func focusChanged(_ key: BlockKey, isFocused: Bool) {
        // Moving between blocks ends a typing run, so the next keystroke is a
        // separate undo step even when the user types again immediately.
        history.endTypingRun()
        if isFocused {
            focusedKey = key
            if focusRequest?.key == key { focusRequest = nil }
        } else if focusedKey == key {
            focusedKey = nil
        }
    }

    // MARK: - Undo

    /// Invisible buttons so ⌘Z / ⇧⌘Z work even when the toolbar collapses the
    /// real buttons into an overflow menu.
    private var historyShortcuts: some View {
        Group {
            Button("Undo") { undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!history.canUndo)
            Button("Redo") { redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!history.canRedo)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func undo() {
        guard let snapshot = history.undo(current: document) else { return }
        restore(snapshot)
    }

    private func redo() {
        guard let snapshot = history.redo(current: document) else { return }
        restore(snapshot)
    }

    /// Shows `snapshot`; the normal `onChange` path saves it and updates the
    /// status line, so backgrounding afterwards still flushes this version.
    private func restore(_ snapshot: TextDocument) {
        if let focusedKey, !snapshot.blocks.contains(where: { $0.id == focusedKey.blockID }) {
            self.focusedKey = nil
        }
        focusRequest = nil
        hasUnsavedChanges = true
        document = snapshot
    }

    // MARK: - Saving

    private func scheduleSave() {
        editGeneration += 1
        hasUnsavedChanges = true
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await saveNow()
        }
    }

    private func finishEditing() {
        pendingSave?.cancel()
        pendingSave = nil
        let snapshotGeneration = editGeneration
        Task {
            await saveNow()
            // Stay open when persistence failed so the alert is visible.
            if model.lastError == nil, snapshotGeneration == editGeneration {
                dismiss()
            }
        }
    }

    private func saveNow() async {
        let generation = editGeneration
        let snapshot = document
        isSaving = true
        await model.save(snapshot)
        isSaving = false
        // A newer edit arrived while the write was in flight; leave the pending
        // debounce task to persist that copy.
        guard generation == editGeneration else { return }
        if model.lastError != nil {
            hasUnsavedChanges = true
        } else {
            hasUnsavedChanges = false
            lastSavedAt = Date()
        }
    }

    /// Saves the document as it is now: leaving the screen or the app going to
    /// the background must persist the latest edit, including an undo, redo or
    /// structural change. The snapshot is taken before the async write.
    ///
    /// The write is awaited inside a background assertion, as the board and
    /// `RootView` do: a bare `Task` gets no execution time once iOS suspends.
    private func flush(holdingBackgroundTime: Bool) {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasUnsavedChanges else { return }
        let snapshot = document
        #if os(iOS)
        let assertion = holdingBackgroundTime
            ? UIApplication.shared.beginBackgroundTask(withName: "Save text document")
            : .invalid
        #endif
        Task {
            await model.save(snapshot)
            #if os(iOS)
            if assertion != .invalid {
                UIApplication.shared.endBackgroundTask(assertion)
            }
            #endif
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.clearError() } }
        )
    }
}

// MARK: - Focus

/// One editable spot in the document: a block, and an item inside list blocks.
struct BlockKey: Hashable {
    var blockID: UUID
    var itemIndex: Int = 0

    /// The scroll view identity for the row that owns this key.
    var rowID: UUID { blockID }
}

/// A request from the document to one block editor: take focus, put the caret
/// at `caretOffset`, and scroll the row into view.
struct FocusRequest: Equatable {
    var key: BlockKey
    var caretOffset: Int
    var token: UUID
}

// MARK: - Block styles

/// The kinds a block can be turned into from its menu.
enum BlockStyleChoice: String, CaseIterable, Identifiable, Hashable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case checklist
    case quote
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paragraph: "Paragraph"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulletList: "Bulleted List"
        case .numberedList: "Numbered List"
        case .checklist: "Checklist"
        case .quote: "Quote"
        case .code: "Code"
        }
    }

    var symbol: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat.size.smaller"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .checklist: "checklist"
        case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }

    var tag: TextBlockKindTag {
        switch self {
        case .paragraph: .paragraph
        case .heading1, .heading2, .heading3: .heading
        case .bulletList: .bulletList
        case .numberedList: .numberedList
        case .checklist: .checklist
        case .quote: .quote
        case .code: .code
        }
    }

    var headingLevel: Int {
        switch self {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        default: 2
        }
    }

    var kind: TextBlockKind {
        switch self {
        case .paragraph: .paragraph(text: "")
        case .heading1: .heading(level: 1, text: "")
        case .heading2: .heading(level: 2, text: "")
        case .heading3: .heading(level: 3, text: "")
        case .bulletList: .bulletList(items: [""])
        case .numberedList: .numberedList(items: [""])
        case .checklist: .checklist(items: [ChecklistItem(text: "")])
        case .quote: .quote(text: "")
        case .code: .code(text: "", language: nil)
        }
    }

    /// The choice that matches a block, for the menu's checkmark.
    static func matching(_ kind: TextBlockKind) -> BlockStyleChoice {
        switch kind {
        case let .heading(level, _):
            switch level {
            case ...1: .heading1
            case 2: .heading2
            default: .heading3
            }
        case .paragraph: .paragraph
        case .bulletList: .bulletList
        case .numberedList: .numberedList
        case .checklist: .checklist
        case .quote: .quote
        case .code: .code
        case .image, .divider: .paragraph
        }
    }
}

// MARK: - Block row

/// One block on the page: a gutter with the block's own controls, and the
/// editable content. The gutter only appears while the block has focus.
private struct BlockRow: View {
    @Binding var block: TextBlock

    let focusedKey: BlockKey?
    let focusRequest: FocusRequest?
    let canMoveUp: Bool
    let canMoveDown: Bool

    let onFocus: (BlockKey) -> Void
    let onBlur: (BlockKey) -> Void
    let onReturn: (BlockKey, Int) -> Void
    let onMerge: (BlockKey) -> Void
    let onConvert: (BlockStyleChoice) -> Void
    let onInsertBelow: () -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void
    /// Called before a checkbox toggle, which is a discrete undo step rather
    /// than part of the current typing run.
    let onChecklistChange: () -> Void

    private var isFocused: Bool { focusedKey?.blockID == block.id }

    private var choice: BlockStyleChoice { .matching(block.kind) }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            gutter
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    // MARK: Gutter

    private var gutter: some View {
        VStack(spacing: 2) {
            if isFocused {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 16)
                    .contentShape(Rectangle())
                    .draggable(block.id.uuidString)
                    .accessibilityLabel("Drag to reorder")

                Menu {
                    menuItems
                } label: {
                    VStack(spacing: 0) {
                        Text(typeGlyph)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 36)
                    .background(
                        Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                }
                .accessibilityLabel("\(choice.title) options")
            }
        }
        .frame(width: 33)
        .padding(.top, 1)
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    private var typeGlyph: String {
        switch block.kind {
        case let .heading(level, _): "H\(min(max(level, 1), 3))"
        case .paragraph: "¶"
        case .bulletList: "•"
        case .numberedList: "1."
        case .checklist: "☑"
        case .quote: "❝"
        case .code: "{}"
        case .image: "◫"
        case .divider: "—"
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Text(choice.title)
        Picker("Style", selection: Binding(get: { choice }, set: { onConvert($0) })) {
            ForEach(BlockStyleChoice.allCases) { option in
                Label(option.title, systemImage: option.symbol).tag(option)
            }
        }
        Divider()
        Button("Add Block Below", systemImage: "plus.square.on.square") { onInsertBelow() }
        Button("Move Up", systemImage: "arrow.up") { onMove(-1) }
            .disabled(!canMoveUp)
        Button("Move Down", systemImage: "arrow.down") { onMove(1) }
            .disabled(!canMoveDown)
        Divider()
        Button("Delete Block", systemImage: "trash", role: .destructive) { onDelete() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case let .heading(level, _):
            editor(
                key: 0,
                text: headingText(level),
                font: BlockTypography.heading(level),
                placeholder: "Heading \(level)"
            )

        case .paragraph:
            editor(
                key: 0,
                text: paragraphText,
                font: BlockTypography.body,
                placeholder: "Write something…"
            )

        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 3)
                editor(
                    key: 0,
                    text: quoteText,
                    font: BlockTypography.quote,
                    color: .secondary,
                    placeholder: "Quote"
                )
            }

        case let .code(_, language):
            VStack(alignment: .leading, spacing: 4) {
                editor(
                    key: 0,
                    text: codeText,
                    font: BlockTypography.code,
                    placeholder: "Code",
                    splitsOnReturn: false
                )
                .padding(10)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
            }

        case .bulletList:
            listContent(bulleted: true)

        case .numberedList:
            listContent(bulleted: false)

        case .checklist:
            checklistContent

        case let .image(assetName, width):
            HStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(assetName.isEmpty ? "Untitled image" : assetName)
                        .font(.body)
                    Text("Image · \(Int(width.rounded())) pt wide")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

        case .divider:
            HStack(spacing: 12) {
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete divider")
            }
            .padding(.vertical, 8)
        }
    }

    private func editor(
        key itemIndex: Int,
        text: Binding<String>,
        font: BlockFont,
        color: Color = .primary,
        placeholder: String,
        splitsOnReturn: Bool = true
    ) -> some View {
        let key = BlockKey(blockID: block.id, itemIndex: itemIndex)
        let request = focusRequest.flatMap {
            $0.key == key ? CaretRequest(token: $0.token, offset: $0.caretOffset) : nil
        }
        return BlockTextEditor(
            text: text,
            font: font,
            textColor: color,
            placeholder: placeholder,
            splitsOnReturn: splitsOnReturn,
            isFocused: focusedKey == key,
            focusRequest: request,
            onReturn: { onReturn(key, $0) },
            onBackspaceAtStart: { onMerge(key) },
            onFocus: { onFocus(key) },
            onBlur: { onBlur(key) }
        )
        .frame(minHeight: 26)
    }

    // MARK: Lists

    private func listContent(bulleted: Bool) -> some View {
        let items = listItems
        // A row per item identity, so splitting or merging above an item
        // moves that row instead of pushing another item's text into it.
        let rows = items.isEmpty ? [ListItem(id: block.id, text: "")] : items
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(bulleted ? "•" : "\(index + 1).")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                        .padding(.top, 3)
                    editor(
                        key: index,
                        text: listItemText(item.id, bulleted: bulleted),
                        font: BlockTypography.body,
                        placeholder: "List item"
                    )
                }
            }
        }
    }

    private var checklistContent: some View {
        let items = checklistItems
        let rows = items.isEmpty ? [ChecklistItem(id: block.id, text: "")] : items
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    Button {
                        setChecked(item.id, !item.isChecked)
                    } label: {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.text.isEmpty ? "Checklist item" : item.text)

                    editor(
                        key: index,
                        text: checklistItemText(item.id),
                        font: BlockTypography.body,
                        color: item.isChecked ? .secondary : .primary,
                        placeholder: "To-do"
                    )
                }
            }
        }
    }

    // MARK: Bindings

    private var paragraphText: Binding<String> {
        Binding(
            get: {
                if case let .paragraph(text) = block.kind { return text }
                return ""
            },
            set: { block.kind = .paragraph(text: $0) }
        )
    }

    private var quoteText: Binding<String> {
        Binding(
            get: {
                if case let .quote(text) = block.kind { return text }
                return ""
            },
            set: { block.kind = .quote(text: $0) }
        )
    }

    private var codeText: Binding<String> {
        Binding(
            get: {
                if case let .code(text, _) = block.kind { return text }
                return ""
            },
            set: { block.kind = .code(text: $0, language: codeLanguage) }
        )
    }

    private var codeLanguage: String? {
        if case let .code(_, language) = block.kind { return language }
        return nil
    }

    private func headingText(_ level: Int) -> Binding<String> {
        Binding(
            get: {
                if case let .heading(_, text) = block.kind { return text }
                return ""
            },
            set: { block.kind = .heading(level: level, text: $0) }
        )
    }

    private var listItems: [ListItem] {
        switch block.kind {
        case let .bulletList(items), let .numberedList(items): items
        default: []
        }
    }

    private func listItemText(_ itemID: UUID, bulleted: Bool) -> Binding<String> {
        Binding(
            get: { listItems.first { $0.id == itemID }?.text ?? "" },
            set: { newValue in
                var items = listItems
                if let index = items.firstIndex(where: { $0.id == itemID }) {
                    items[index].text = newValue
                } else {
                    items = [ListItem(id: itemID, text: newValue)]
                }
                block.kind = bulleted ? .bulletList(items: items) : .numberedList(items: items)
            }
        )
    }

    private var checklistItems: [ChecklistItem] {
        if case let .checklist(items) = block.kind { return items }
        return []
    }

    private func checklistItemText(_ itemID: UUID) -> Binding<String> {
        Binding(
            get: { checklistItems.first { $0.id == itemID }?.text ?? "" },
            set: { newValue in
                var items = checklistItems
                if let index = items.firstIndex(where: { $0.id == itemID }) {
                    items[index].text = newValue
                } else {
                    items = [ChecklistItem(id: itemID, text: newValue)]
                }
                block.kind = .checklist(items: items)
            }
        )
    }

    private func setChecked(_ itemID: UUID, _ value: Bool) {
        var items = checklistItems
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].isChecked = value
        } else {
            items = [ChecklistItem(id: itemID, text: "", isChecked: value)]
        }
        onChecklistChange()
        block.kind = .checklist(items: items)
    }
}

extension BlockRow: Equatable {
    /// Equality on the values the row draws, so a parent update that changed
    /// another block does not re-run this row's body. The action closures are
    /// deliberately ignored: they close over the block's stable id and read the
    /// editor's `@State` when called, so a stale closure still does the right
    /// thing.
    static func == (lhs: BlockRow, rhs: BlockRow) -> Bool {
        lhs.block == rhs.block
            && lhs.focusedKey == rhs.focusedKey
            && lhs.focusRequest == rhs.focusRequest
            && lhs.canMoveUp == rhs.canMoveUp
            && lhs.canMoveDown == rhs.canMoveDown
    }
}

// MARK: - Typography

private enum BlockTypography {
    static let body = BlockFont(size: 17, textStyle: .body)
    static let quote = BlockFont(size: 17, textStyle: .body, isItalic: true)
    static let code = BlockFont(size: 15, textStyle: .callout, isMonospaced: true)

    static func heading(_ level: Int) -> BlockFont {
        switch level {
        case ...1: BlockFont(size: 30, textStyle: .title, weight: .bold)
        case 2: BlockFont(size: 24, textStyle: .title2, weight: .semibold)
        default: BlockFont(size: 20, textStyle: .title3, weight: .semibold)
        }
    }
}

// MARK: - Previews

private func previewDocument() -> TextDocument {
    TextDocument(
        title: "Reading Notes",
        blocks: [
            TextBlock(kind: .heading(level: 1, text: "Reading Notes")),
            TextBlock(kind: .paragraph(text: "A quiet place to collect the ideas worth keeping.")),
            TextBlock(kind: .heading(level: 2, text: "Key ideas")),
            TextBlock(kind: .bulletList(items: ["Notes should stay editable.", "Blocks keep structure intact."])),
            TextBlock(kind: .quote(text: "The best notebook is the one you actually open.")),
            TextBlock(kind: .checklist(items: [
                ChecklistItem(text: "Write a summary", isChecked: true),
                ChecklistItem(text: "Link the source"),
            ])),
            TextBlock(kind: .divider),
            TextBlock(kind: .code(text: "let document = TextDocument(title: \"Notes\")", language: "swift")),
        ]
    )
}

#Preview("Document Editor") {
    let document = previewDocument()
    let model = TextDocModel(
        root: FileManager.default.temporaryDirectory
            .appendingPathComponent("TextDocsEditorPreview-\(UUID().uuidString)", isDirectory: true)
    )
    NavigationStack {
        TextDocumentEditorView(model: model, document: document)
    }
}
