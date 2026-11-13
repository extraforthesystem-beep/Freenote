import StudyKit
import SwiftUI

/// Edit one study set's cards, then start a Smart Learn review.
struct StudySetEditorView: View {
    @Bindable var study: StudyModel
    let setID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var cardEditor: CardEditorTarget?
    @State private var showsReview = false
    @State private var errorText: String?

    private var set: StudySet? {
        study.set(withID: setID)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(set?.title ?? "Study Set")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .safeAreaInset(edge: .bottom) {
                    studyBar
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            beginAdding()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add card")
                    }
                }
                .sheet(item: $cardEditor) { target in
                    StudyCardEditorView(
                        target: target,
                        onSave: { question, answer in
                            saveCard(id: target.cardID, question: question, answer: answer)
                        },
                        onDelete: target.cardID.map { cardID in
                            { deleteCard(id: cardID) }
                        }
                    )
                }
                .sheet(isPresented: $showsReview) {
                    StudyReviewView(study: study, setID: setID)
                }
                .alert("Study error", isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )) {
                    Button("OK", role: .cancel) { errorText = nil }
                } message: {
                    Text(errorText ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let set, !set.cards.isEmpty {
            List {
                Section {
                    ForEach(set.cards) { card in
                        Button {
                            edit(card)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.question)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(card.answer)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        var updated = set
                        updated.cards.remove(atOffsets: offsets)
                        Task { await save(updated) }
                    }

                    Button {
                        beginAdding()
                    } label: {
                        Label("Add Card", systemImage: "plus.circle.fill")
                            .frame(minHeight: 32)
                    }
                } footer: {
                    Text("Tap a card to edit it. Swipe to delete.")
                }
            }
#if os(iOS)
            .listStyle(.insetGrouped)
#endif
        } else {
            ContentUnavailableView {
                Label("No Cards", systemImage: "rectangle.stack.badge.plus")
            } description: {
                Text("Add a question and answer to start studying.")
            } actions: {
                Button("Add Card") { beginAdding() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var studyBar: some View {
        let count = set?.cards.count ?? 0
        return Button {
            showsReview = true
        } label: {
            Label(
                count == 0 ? "Study" : "Study \(count) Card\(count == 1 ? "" : "s")",
                systemImage: "play.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(count == 0)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.thinMaterial)
    }

    private func beginAdding() {
        cardEditor = CardEditorTarget(cardID: nil, question: "", answer: "")
    }

    private func edit(_ card: StudyCard) {
        cardEditor = CardEditorTarget(
            cardID: card.id,
            question: card.question,
            answer: card.answer
        )
    }

    private func saveCard(id: UUID?, question: String, answer: String) {
        guard let set else { return }
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return }

        var updated = set
        if let id, let index = updated.cards.firstIndex(where: { $0.id == id }) {
            updated.cards[index].question = trimmedQuestion
            updated.cards[index].answer = trimmedAnswer
            updated.cards[index].updatedAt = Date()
        } else {
            updated.cards.append(
                StudyCard(question: trimmedQuestion, answer: trimmedAnswer)
            )
        }
        Task { await save(updated) }
    }

    private func deleteCard(id: UUID) {
        guard let set else { return }
        var updated = set
        updated.cards.removeAll { $0.id == id }
        Task { await save(updated) }
    }

    private func save(_ updated: StudySet) async {
        if await study.save(updated) == false {
            errorText = study.lastError ?? "The study set could not be saved."
        }
    }
}

/// Which card the editor sheet is showing. A `nil` card id means a new card.
private struct CardEditorTarget: Identifiable {
    let id = UUID()
    var cardID: UUID?
    var question: String
    var answer: String
}

/// Multi-line editor for one card, presented as a sheet.
private struct StudyCardEditorView: View {
    let target: CardEditorTarget
    let onSave: (String, String) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var question: String
    @State private var answer: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case question
        case answer
    }

    init(
        target: CardEditorTarget,
        onSave: @escaping (String, String) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.target = target
        self.onSave = onSave
        self.onDelete = onDelete
        _question = State(initialValue: target.question)
        _answer = State(initialValue: target.answer)
    }

    private var isNew: Bool {
        target.cardID == nil
    }

    private var canSave: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Question", text: $question, axis: .vertical)
                        .lineLimit(3...10)
                        .focused($focusedField, equals: .question)
                }
                Section("Answer") {
                    TextField("Answer", text: $answer, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($focusedField, equals: .answer)
                }
                if let onDelete {
                    Section {
                        Button("Delete Card", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Card" : "Edit Card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(question, answer)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                focusedField = .question
            }
        }
        .presentationDetents([.medium, .large])
    }
}
