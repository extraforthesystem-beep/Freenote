import AIKit
import SearchKit
import StudyKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// On-device AI for the current page: summary, flashcards and ask-your-notes.
/// The deterministic fallback keeps the panel usable when Apple Intelligence is
/// unavailable, and every answer is grounded in the page text we pass in.
struct NoteAIPanel: View {
    let session: NotebookSession
    let search: HandwritingSearch
    let ai: AIService
    let study: StudyModel

    @Environment(\.dismiss) private var dismiss
    @State private var pageText = ""
    @State private var didLoadText = false
    @State private var isLoadingText = true
    @State private var summary = ""
    @State private var summaryCitations: [AICitation] = []
    @State private var answer = ""
    @State private var answerCitations: [AICitation] = []
    @State private var cards: [AIFlashcard] = []
    @State private var question = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var savedCards = false
    @State private var addedBlock: String?
    /// The page the text was read from, so a citation tap can go back to it.
    @State private var sourcePageID: UUID?
    /// A title taken from the page text for a notebook still called Untitled.
    @State private var suggestedTitle: String?
    @State private var isApplyingTitle = false

    private var hasPageText: Bool {
        !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    titleSuggestion

                    if isWorking {
                        workingRow
                    }

                    if !summary.isEmpty {
                        resultBlock(
                            title: "Summary",
                            text: summary,
                            blockID: "summary",
                            citations: summaryCitations
                        )
                    }

                    if !answer.isEmpty {
                        resultBlock(
                            title: "Answer",
                            text: answer,
                            blockID: "answer",
                            citations: answerCitations
                        )
                    }

                    if !cards.isEmpty {
                        cardBlock
                    }
                }
                .padding(24)
            }
            .navigationTitle("Page AI")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                askBar
            }
            .alert("AI error", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .task {
                await loadTextIfNeeded()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(ai.availability.isAvailable ? "On-device model" : "Offline note assistant")
                    .font(.headline)
            }
            Text("Nothing leaves this device. The assistant reads only the text it can find on this page.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if isLoadingText {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading this page…")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            } else if !hasPageText {
                ContentUnavailableView {
                    Label("No Text on This Page", systemImage: "text.page.slash")
                } description: {
                    Text("Write or import text on this page first.")
                } actions: {
                    Button("Check Again") {
                        Task { await reloadText() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    Button {
                        summarize()
                    } label: {
                        Label("Summarize Page", systemImage: "text.append")
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        makeFlashcards()
                    } label: {
                        Label("Flashcards", systemImage: "rectangle.stack.badge.plus")
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(isWorking)
            }
        }
    }

    private var workingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Thinking on device…")
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var titleSuggestion: some View {
        if let suggestedTitle, isUntitled {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notebook title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(suggestedTitle)
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Use") {
                    applyTitle(suggestedTitle)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isApplyingTitle)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// True when the notebook still has the name it was created with.
    private var isUntitled: Bool {
        let title = session.manifest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title.localizedCaseInsensitiveContains("untitled")
    }

    private var cardBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Flashcards")
                    .font(.headline)
                Spacer()
                Button(savedCards ? "Saved" : "Save as Study Set") {
                    saveCards()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(savedCards || cards.isEmpty || isWorking)
            }

            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.question)
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)
                    Text(card.answer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        addToPage(cardText(card), id: "card-\(index)")
                    } label: {
                        Image(systemName: addedBlock == "card-\(index)"
                            ? "checkmark.circle.fill"
                            : "plus.rectangle.on.rectangle")
                            .font(.body)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(addedBlock == "card-\(index)" ? Color.green : Color.accentColor)
                    .accessibilityLabel(addedBlock == "card-\(index)" ? "Added to page" : "Add card to page")
                }
            }

            HStack(spacing: 10) {
                Button {
                    copy(flashcardText)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)

                Button {
                    addToPage(flashcardText, id: "cards")
                } label: {
                    Label(
                        addedBlock == "cards" ? "Added" : "Add All to Page",
                        systemImage: addedBlock == "cards" ? "checkmark" : "plus.rectangle.on.rectangle"
                    )
                    .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(addedBlock == "cards")
            }
            .controlSize(.large)
        }
    }

    private func resultBlock(
        title: String,
        text: String,
        blockID: String,
        citations: [AICitation] = []
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !citations.isEmpty {
                sourceMarks(citations)
            }

            HStack(spacing: 10) {
                Button {
                    copy(text)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)

                Button {
                    addToPage(text, id: blockID)
                } label: {
                    Label(
                        addedBlock == blockID ? "Added" : "Add to Page",
                        systemImage: addedBlock == blockID ? "checkmark" : "plus.rectangle.on.rectangle"
                    )
                    .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .disabled(addedBlock == blockID)
            }
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The note sentences the answer was built from. Tapping one closes the
    /// panel and marks those words on the page.
    private func sourceMarks(_ citations: [AICitation]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources on this page")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(citations.enumerated()), id: \.offset) { _, citation in
                        Button {
                            reveal(citation)
                        } label: {
                            Label(citationSnippet(citation), systemImage: "text.magnifyingglass")
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Show source on the page: \(citation.text)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func citationSnippet(_ citation: AICitation) -> String {
        let collapsed = citation.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 44 ? String(collapsed.prefix(44)) + "…" : collapsed
    }

    /// Closes the panel, goes back to the page the text came from, and marks
    /// the citation's words with the same overlay search uses.
    private func reveal(_ citation: AICitation) {
        guard let highlight = Self.highlight(for: citation) else { return }
        Task {
            if let sourcePageID,
               session.page?.id != sourcePageID,
               let index = session.manifest.pageOrder.firstIndex(of: sourcePageID) {
                await session.goToPage(index)
            }
            session.searchHighlight = highlight
            dismiss()
        }
    }

    /// The citation's most distinctive words as a search query; page marks find
    /// the ink, text box or PDF words the citation was taken from.
    private static func highlight(for citation: AICitation) -> SearchHighlight? {
        var words: [String] = []
        for word in citation.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let text = String(word)
            guard text.count >= 3,
                  !words.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame })
            else { continue }
            words.append(text)
        }
        // The longest words carry the meaning; short ones are mostly "the" and
        // "and", which would mark half the page.
        let chosen = words.sorted { $0.count > $1.count }.prefix(5)
        guard !chosen.isEmpty else { return nil }
        return SearchHighlight(query: chosen.joined(separator: " "))
    }

    private var askBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about this page…", text: $question, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            Button {
                ask()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(
                isWorking
                    || !hasPageText
                    || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityLabel("Ask about this page")
        }
        .padding(14)
        .background(.bar)
        .disabled(!hasPageText)
    }

    // MARK: - Page text

    private func loadTextIfNeeded() async {
        guard !didLoadText else { return }
        didLoadText = true
        isLoadingText = true
        defer { isLoadingText = false }
        guard let page = session.page else { return }
        sourcePageID = page.id
        pageText = await search.noteText(for: page)
        suggestedTitle = isUntitled ? AutoTitle.suggestion(from: pageText) : nil
    }

    private func reloadText() async {
        didLoadText = false
        isLoadingText = true
        await loadTextIfNeeded()
    }

    /// Loads the page text and reports whether there is anything to work with.
    private func readyText() async -> String? {
        if !didLoadText {
            await loadTextIfNeeded()
        }
        return hasPageText ? pageText : nil
    }

    // MARK: - Actions

    private func summarize() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            guard let text = await readyText() else { return }
            do {
                let response = try await ai.respond(
                    to: AIRequest(kind: .summarize(text: text, scope: .page))
                )
                summary = response.text
                summaryCitations = response.citations
                addedBlock = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func makeFlashcards() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            guard let text = await readyText() else { return }
            do {
                let response = try await ai.respond(
                    to: AIRequest(kind: .flashcards(text: text, maxCards: 8))
                )
                cards = response.cards
                savedCards = false
                addedBlock = nil
                if cards.isEmpty {
                    errorText = "The assistant could not find card-worthy facts on this page."
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func ask() {
        let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            guard let text = await readyText() else { return }
            do {
                let response = try await ai.respond(
                    to: AIRequest(kind: .ask(question: query, context: text))
                )
                answer = response.text
                answerCitations = response.citations
                addedBlock = nil
                if response.citations.isEmpty,
                   response.text == DeterministicProvider.notFoundText {
                    answer = "I could not find that on this page."
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func saveCards() {
        guard !cards.isEmpty, !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            let title = "AI · \(session.manifest.title) · \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            guard var set = await study.createSet(title: title) else {
                errorText = study.lastError ?? "The study set could not be created."
                return
            }
            set.cards = cards.map {
                StudyCard(question: $0.question, answer: $0.answer)
            }
            if await study.save(set) {
                savedCards = true
            } else {
                errorText = study.lastError ?? "The study set could not be saved."
                // Roll back the empty set so a failed save leaves nothing behind.
                await study.delete(set)
            }
        }
    }

    /// Renames the notebook in its manifest, the same way the library does.
    private func applyTitle(_ title: String) {
        guard !isApplyingTitle else { return }
        isApplyingTitle = true
        Task {
            defer { isApplyingTitle = false }
            do {
                try await session.store.renameNotebook(session.notebookID, title: title)
                await session.reloadManifest()
                suggestedTitle = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func addToPage(_ text: String, id: String) {
        guard !text.isEmpty else { return }
        Task {
            await session.addTextElement(text)
            addedBlock = id
        }
    }

    private func cardText(_ card: AIFlashcard) -> String {
        "\(card.question)\n\(card.answer)"
    }

    private var flashcardText: String {
        cards.map(cardText).joined(separator: "\n\n")
    }
}
