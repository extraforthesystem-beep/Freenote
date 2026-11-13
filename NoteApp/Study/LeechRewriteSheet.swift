import StudyKit
import SwiftUI

/// Rewriting a leech: the card has lapsed four times, so its prompt is usually
/// the problem, not the memory. The sheet edits the card in place and can split
/// it into a second, smaller card with the same source page.
struct LeechRewriteSheet: View {
    @Bindable var study: StudyModel
    let setID: UUID
    let card: StudyCard
    let lapses: Int
    /// Opens the page the card came from; `nil` when the caller cannot show it.
    var onOpenSource: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var question: String
    @State private var answer: String
    @State private var isSplitting = false
    @State private var secondQuestion = ""
    @State private var secondAnswer = ""
    @State private var errorText: String?

    init(
        study: StudyModel,
        setID: UUID,
        card: StudyCard,
        lapses: Int,
        onOpenSource: (() -> Void)? = nil
    ) {
        self.study = study
        self.setID = setID
        self.card = card
        self.lapses = lapses
        self.onOpenSource = onOpenSource
        _question = State(initialValue: card.question)
        _answer = State(initialValue: card.answer)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "This card has lapsed \(lapses) times. Make the prompt smaller, "
                            + "add a cue, or split it into two cards."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Section("Question") {
                    TextField("Question", text: $question, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Answer") {
                    TextField("Answer", text: $answer, axis: .vertical)
                        .lineLimit(2...8)
                }

                Section {
                    Toggle("Split into a second card", isOn: $isSplitting)
                    if isSplitting {
                        TextField("Second question", text: $secondQuestion, axis: .vertical)
                            .lineLimit(1...4)
                        TextField("Second answer", text: $secondAnswer, axis: .vertical)
                            .lineLimit(1...6)
                    }
                } footer: {
                    Text("A split card keeps the page this card came from.")
                }

                if let onOpenSource {
                    Section {
                        Button {
                            onOpenSource()
                            dismiss()
                        } label: {
                            Label("Open Source Page", systemImage: "arrow.up.forward.app")
                        }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Rewrite Card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedQuestion.isEmpty)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let prompt = trimmedQuestion
        guard !prompt.isEmpty else { return }
        let reply = answer
        let splitQuestion = secondQuestion
        let splitAnswer = secondAnswer

        Task {
            let updated = await study.updateCard(
                card.id,
                in: setID,
                question: prompt,
                answer: reply
            )
            guard updated else {
                errorText = study.lastError ?? "The card could not be saved."
                return
            }
            if isSplitting, !splitQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let added = await study.addCard(
                    to: setID,
                    after: card,
                    question: splitQuestion,
                    answer: splitAnswer
                )
                if !added {
                    errorText = study.lastError ?? "The second card could not be saved."
                    return
                }
            }
            // A rewrite starts the card over; that is how it leaves the leech
            // list instead of carrying four lapses into its next schedule.
            study.resetSchedule(cardID: card.id, in: setID)
            dismiss()
        }
    }
}
