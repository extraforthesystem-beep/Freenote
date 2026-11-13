import NoteCore
import SwiftUI

struct TextElementComposer: View {
    let title: String
    let initialText: String
    let initialFontSize: Double
    let initialStyle: TextStyle
    /// `false` for a sticky note: it has no font controls, and it may be left
    /// blank, because a blank note is a note waiting to be written on.
    let showsFontControls: Bool
    let onSave: (String, Double, TextStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var fontSize: Double
    @State private var style: TextStyle

    init(
        title: String = "Text Box",
        initialText: String = "",
        initialFontSize: Double = 16,
        initialStyle: TextStyle = .regular,
        showsFontControls: Bool = true,
        onSave: @escaping (String, Double, TextStyle) -> Void
    ) {
        self.title = title
        self.initialText = initialText
        self.initialFontSize = initialFontSize
        self.initialStyle = initialStyle
        self.showsFontControls = showsFontControls
        self.onSave = onSave
        _text = State(initialValue: initialText)
        _fontSize = State(initialValue: initialFontSize)
        _style = State(initialValue: initialStyle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                }
                if showsFontControls {
                    Section("Font size") {
                        Stepper("\(Int(fontSize)) pt", value: $fontSize, in: 9...72)
                    }
                    Section("Style") {
                        HStack(spacing: 10) {
                            styleButton("Bold", symbol: "bold", isOn: $style.isBold)
                            styleButton("Italic", symbol: "italic", isOn: $style.isItalic)
                            styleButton("Underline", symbol: "underline", isOn: $style.isUnderline)
                        }
                        Picker("Alignment", selection: $style.alignment) {
                            Image(systemName: "text.alignleft").tag(TextStyle.Alignment.leading)
                            Image(systemName: "text.aligncenter").tag(TextStyle.Alignment.center)
                            Image(systemName: "text.alignright").tag(TextStyle.Alignment.trailing)
                            Image(systemName: "text.justify").tag(TextStyle.Alignment.justified)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text, fontSize, style)
                        dismiss()
                    }
                    .disabled(
                        showsFontControls
                            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }

    private func styleButton(_ label: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 32)
                .background(
                    isOn.wrappedValue ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct PageElementsSheet: View {
    let session: NotebookSession
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditingElement?

    /// The editor to show for a row. A text box and a sticky note are edited the
    /// same way, with a different set of controls.
    private enum EditingElement: Identifiable {
        case text(PageElement)
        case stickyNote(PageElement)

        var id: UUID {
            switch self {
            case let .text(element): element.id
            case let .stickyNote(element): element.id
            }
        }

        var element: PageElement {
            switch self {
            case let .text(element), let .stickyNote(element): element
            }
        }
    }

    private var elements: [PageElement] {
        (session.page?.elements ?? []).sorted { $0.zIndex < $1.zIndex }
    }

    var body: some View {
        NavigationStack {
            Group {
                if elements.isEmpty {
                    ContentUnavailableView(
                        "No Page Elements",
                        systemImage: "square.on.square.dashed",
                        description: Text("Add a text box, a sticky note, an image or a PDF from Page Actions.")
                    )
                } else {
                    List {
                        ForEach(elements) { element in
                            row(element)
                        }
                    }
                }
            }
            .navigationTitle("Page Elements")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { editor in
                switch editor {
                case let .text(element):
                    TextElementComposer(
                        title: "Edit Text",
                        initialText: Self.text(of: element),
                        initialFontSize: Self.fontSize(of: element),
                        initialStyle: element.textStyle ?? .regular
                    ) { text, _, style in
                        Task { await session.updateTextElement(element.id, text: text, textStyle: style) }
                    }
                case let .stickyNote(element):
                    TextElementComposer(
                        title: "Edit Note",
                        initialText: Self.text(of: element),
                        showsFontControls: false
                    ) { text, _, _ in
                        Task { await session.updateStickyNoteText(element.id, text: text) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ element: PageElement) -> some View {
        HStack(spacing: 12) {
            if case let .stickyNote(_, color) = element.content {
                StickyNoteElementView(text: "", color: color)
                    .frame(width: 26, height: 26)
            } else {
                Image(systemName: icon(for: element.content))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label(for: element.content))
                    .lineLimit(2)
                Text("z \(element.zIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            editButton(for: element)

            Button(role: .destructive) {
                Task { await session.removeElement(element.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func editButton(for element: PageElement) -> some View {
        switch element.content {
        case .text:
            Button("Edit") { editing = .text(element) }
                .buttonStyle(.bordered)
        case .stickyNote:
            Button("Edit") { editing = .stickyNote(element) }
                .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }

    private func icon(for content: ElementContent) -> String {
        switch content {
        case .text: "text.alignleft"
        case .image: "photo"
        case .shape: "square.on.circle"
        case .pdfPage: "doc.richtext"
        case .stickyNote: "note.text"
        case .tape: "rectangle.fill"
        }
    }

    private func label(for content: ElementContent) -> String {
        switch content {
        case let .text(text, _, _, _): text
        case .image: "Image"
        case let .shape(kind, _, _, _): "Shape · \(kind)"
        case let .pdfPage(_, pageIndex): "PDF page \(pageIndex + 1)"
        case let .stickyNote(text, _): text.isEmpty ? "Sticky Note" : text
        case .tape: "Tape"
        }
    }

    private static func text(of element: PageElement) -> String {
        switch element.content {
        case let .text(text, _, _, _): text
        case let .stickyNote(text, _): text
        default: ""
        }
    }

    private static func fontSize(of element: PageElement) -> Double {
        if case let .text(_, _, fontSize, _) = element.content { return fontSize }
        return 16
    }
}

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - Sticky notes and tape

/// A sticky note drawn sharply over the page, for the elements sheet's preview
/// and for any place a note is shown while it is being edited. On the page
/// itself the note is part of the rendered background.
struct StickyNoteElementView: View {
    let text: String
    let color: RGBAColor
    /// The board shrinks the text to fit its card; the notebook uses the
    /// standard size.
    var fontSize: CGFloat = 15

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(color))
            .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.black.opacity(0.07), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Text(text)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.black.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }
    }
}

/// A piece of tape. Opaque it hides the ink under it; revealed it is drawn at
/// 15% opacity so the ink can be read without moving it.
struct TapeElementView: View {
    let color: RGBAColor
    let isRevealed: Bool

    private static let cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            // Tape is opaque, whatever alpha its stored colour has: that is what
            // hides the ink underneath.
            .fill(Color(RGBAColor(r: color.r, g: color.g, b: color.b)))
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        let size = proxy.size
                        guard size.width > 0, size.height > 0 else { return }
                        let spacing: CGFloat = 9
                        var x = -size.height
                        while x < size.width {
                            path.move(to: CGPoint(x: x, y: size.height))
                            path.addLine(to: CGPoint(x: x + size.height, y: 0))
                            x += spacing
                        }
                    }
                    .stroke(.black.opacity(0.06), lineWidth: 3)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    )
                }
            }
            .opacity(isRevealed ? 0.15 : 1)
    }
}

/// Tape sits above the ink canvas, because a piece of tape has to hide what is
/// under it. A tap holds a piece up, or puts it back.
///
/// Which pieces are held up is session state and is never saved, so
/// `revealedTapeIDs` comes from `NotebookSession.revealedTapeIDs` and
/// `onTap` goes to `NotebookSession.toggleTapeRevealed(_:)`.
struct TapeOverlay: View {
    let page: Page
    let revealedTapeIDs: Set<UUID>
    /// Turned off while the element edit layer is up, so selecting and moving
    /// tape is not fighting a second set of gestures.
    var allowsHitTesting = true
    let onTap: (UUID) -> Void

    private var tapes: [PageElement] {
        page.visibleElements
            .filter { element in
                if case .tape = element.content { return true }
                return false
            }
            .sorted {
                $0.zIndex == $1.zIndex ? $0.id.uuidString < $1.id.uuidString : $0.zIndex < $1.zIndex
            }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(tapes) { element in
                if case let .tape(color) = element.content {
                    TapeElementView(
                        color: color,
                        isRevealed: revealedTapeIDs.contains(element.id)
                    )
                    .frame(width: max(element.frame.width, 1), height: max(element.frame.height, 1))
                    .rotationEffect(.radians(element.frame.rotation))
                    .position(
                        x: element.frame.x + element.frame.width / 2,
                        y: element.frame.y + element.frame.height / 2
                    )
                    .onTapGesture { onTap(element.id) }
                    .accessibilityLabel(revealedTapeIDs.contains(element.id) ? "Tape, revealed" : "Tape")
                    .accessibilityHint("Holds the tape up so the ink under it shows")
                }
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .allowsHitTesting(allowsHitTesting)
        .accessibilityElement(children: .contain)
    }
}
