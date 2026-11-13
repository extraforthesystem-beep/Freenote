import StudyKit
import SwiftUI

/// Which source the notebook entry is reviewing.
enum NotebookStudyScope: String, Identifiable {
    case notebook
    case page

    var id: String { rawValue }
}

/// The notebook-side study entry: what is due from this notebook or page, the
/// cards captured from it, and a way to add a card from the page on screen.
///
/// Cards created here carry `sourceNotebookID`/`sourcePageID`, so a review can
/// jump back to the ink they came from.
struct NotebookStudySheet: View {
    @Bindable var study: StudyModel
    let session: NotebookSession
    let scope: NotebookStudyScope

    @Environment(\.dismiss) private var dismiss
    @State private var showsReview = false
    @State private var question = ""
    @State private var answer = ""
    @State private var errorText: String?

    private var pageID: UUID? {
        scope == .page ? session.currentPageID : nil
    }

    private var titleText: String {
        scope == .page ? "Page \(session.pageIndex + 1)" : session.manifest.title
    }

    private var dueCount: Int {
        study.dueCount(notebookID: session.notebookID, pageID: pageID)
    }

    private var cards: [StudyQueueItem] {
        study.cards(notebookID: session.notebookID, pageID: pageID)
    }

    var body: some View {
        NavigationStack {
            List {
                dueSection
                cardsSection
                addSection
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Study · \(titleText)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsReview) {
                reviewSheet
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

    private var dueSection: some View {
        Section {
            if dueCount == 0 {
                Label("Nothing due", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    showsReview = true
                } label: {
                    Label(
                        "Review \(dueCount) Due Card\(dueCount == 1 ? "" : "s")",
                        systemImage: "play.circle.fill"
                    )
                    .font(.headline)
                    .frame(minHeight: 44)
                }
            }
        } header: {
            Text(scope == .page ? "This Page" : "This Notebook")
        } footer: {
            Text("Every review asks you to recall the answer before it is shown.")
        }
    }

    @ViewBuilder
    private var cardsSection: some View {
        Section {
            if cards.isEmpty {
                Text("No cards captured yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cards) { item in
                    Button {
                        open(card: item.card)
                    } label: {
                        cardRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Cards (\(cards.count))")
        } footer: {
            if !cards.isEmpty {
                Text("Tap a card to open the page it came from.")
            }
        }
    }

    private func cardRow(_ item: StudyQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.card.question)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(item.card.answer)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(dueText(item))
                    .font(.caption2)
                    .foregroundStyle(item.dueDate <= Date() ? .orange : .secondary)
                if item.card.sourcePageID != nil {
                    Label("Page", systemImage: "arrow.up.forward.app")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var addSection: some View {
        Section {
            TextField("Question", text: $question, axis: .vertical)
                .lineLimit(2...5)
            TextField("Answer", text: $answer, axis: .vertical)
                .lineLimit(2...6)
            Button {
                addCard()
            } label: {
                Label("Add Card from This Page", systemImage: "plus.circle.fill")
                    .frame(minHeight: 32)
            }
            .disabled(
                question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || session.currentPageID == nil
            )
        } header: {
            Text("New Card")
        } footer: {
            Text("The card keeps a link back to page \(session.pageIndex + 1).")
        }
    }

    @ViewBuilder
    private var reviewSheet: some View {
        if let pageID {
            StudyReviewView(
                study: study,
                scope: .page(notebookID: session.notebookID, pageID: pageID),
                passTitle: titleText,
                onOpenSource: openFromReview
            )
        } else {
            StudyReviewView(
                study: study,
                scope: .notebook(session.notebookID),
                passTitle: titleText,
                onOpenSource: openFromReview
            )
        }
    }

    private func addCard() {
        guard let pageID = session.currentPageID else { return }
        let prompt = question
        let reply = answer
        question = ""
        answer = ""
        Task {
            let added = await study.addCard(
                question: prompt,
                answer: reply,
                notebookID: session.notebookID,
                pageID: pageID,
                notebookTitle: session.manifest.title
            )
            if !added {
                errorText = study.lastError ?? "The card could not be saved."
            }
        }
    }

    private func open(card: StudyCard) {
        guard let pageID = card.sourcePageID else { return }
        dismiss()
        open(notebookID: session.notebookID, pageID: pageID)
    }

    /// A review's source link closes the review and this sheet, so the ink the
    /// card came from is visible.
    private func openFromReview(notebookID: UUID, pageID: UUID) {
        showsReview = false
        dismiss()
        open(notebookID: notebookID, pageID: pageID)
    }

    private func open(notebookID: UUID, pageID: UUID) {
        guard notebookID == session.notebookID,
              let index = session.manifest.pageOrder.firstIndex(of: pageID)
        else { return }
        Task { await session.goToPage(index) }
    }

    private func dueText(_ item: StudyQueueItem) -> String {
        let days = item.dueDate.timeIntervalSinceNow / 86_400
        if days <= 0 { return "Due now" }
        if days < 1 { return "Due today" }
        return "Due in \(max(1, Int(days.rounded(.up)))) day\(days < 2 ? "" : "s")"
    }
}
