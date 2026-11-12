import NoteCore
import SwiftUI

struct TextElementComposer: View {
    let title: String
    let initialText: String
    let initialFontSize: Double
    let onSave: (String, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var fontSize: Double

    init(
        title: String = "Text Box",
        initialText: String = "",
        initialFontSize: Double = 16,
        onSave: @escaping (String, Double) -> Void
    ) {
        self.title = title
        self.initialText = initialText
        self.initialFontSize = initialFontSize
        self.onSave = onSave
        _text = State(initialValue: initialText)
        _fontSize = State(initialValue: initialFontSize)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                }
                Section("Font size") {
                    Stepper("\(Int(fontSize)) pt", value: $fontSize, in: 9...48)
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
                        onSave(text, fontSize)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct PageElementsSheet: View {
    let session: NotebookSession
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PageElement?
    @State private var editText = ""
    @State private var editFontSize = 16.0

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
                        description: Text("Add a text box, an image or a PDF from Page Actions.")
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
            .sheet(item: $editing) { element in
                TextElementComposer(
                    title: "Edit Text",
                    initialText: editText,
                    initialFontSize: editFontSize
                ) { text, size in
                    Task { await session.updateTextElement(element.id, text: text) }
                    editText = text
                    editFontSize = size
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ element: PageElement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: element.content))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(label(for: element.content))
                    .lineLimit(2)
                Text("z \(element.zIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case let .text(text, _, fontSize, _) = element.content {
                Button("Edit") {
                    editText = text
                    editFontSize = fontSize
                    editing = element
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                Task { await session.removeElement(element.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func icon(for content: ElementContent) -> String {
        switch content {
        case .text: "text.alignleft"
        case .image: "photo"
        case .shape: "square.on.circle"
        case .pdfPage: "doc.richtext"
        }
    }

    private func label(for content: ElementContent) -> String {
        switch content {
        case let .text(text, _, _, _): text
        case .image: "Image"
        case let .shape(kind, _, _, _): "Shape · \(kind)"
        case let .pdfPage(_, pageIndex): "PDF page \(pageIndex + 1)"
        }
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
