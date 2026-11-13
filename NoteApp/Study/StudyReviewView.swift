import StudyKit
import SwiftUI

/// What a review pass covers: every due card, one set, one notebook, or one page.
enum StudyScope: Hashable {
    case all
    case set(UUID)
    case notebook(UUID)
    case page(notebookID: UUID, pageID: UUID)

    /// The notebook a queue is narrowed to, if any.
    var notebookID: UUID? {
        switch self {
        case .notebook(let id): id
        case .page(let id, _): id
        case .all, .set: nil
        }
    }

    /// The page a queue is narrowed to, if any.
    var pageID: UUID? {
        switch self {
        case .page(_, let pageID): pageID
        case .all, .set, .notebook: nil
        }
    }

    /// The set a queue is narrowed to, if any.
    var setID: UUID? {
        switch self {
        case .set(let id): id
        case .all, .notebook, .page: nil
        }
    }
}

/// A recall-first review pass: question, a recall attempt, then the answer and
/// the four FSRS grades.
///
/// The pass is captured when the view appears, so "N due" and the queue agree
/// even if the clock moves. A card that reaches its fourth lapse offers a
/// rewrite instead of letting the same card keep failing.
struct StudyReviewView: View {
    @Bindable var study: StudyModel
    let scope: StudyScope
    /// The pass title; callers name the notebook or page they scoped to.
    var passTitle = "Review"
    /// Opens the ink a card was captured from. Hidden when nil, so the library
    /// pass has no dead button.
    var onOpenSource: ((UUID, UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var pass: ReviewPass?
    @State private var revealed = false
    @State private var recallDraft = ""
    @State private var leech: LeechTarget?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if let pass {
                    if let item = pass.currentItem {
                        cardView(item, pass: pass)
                    } else {
                        completionView(pass)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(passTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: startPassIfNeeded)
            .onDisappear {
                // Leaving the pass writes the grades now instead of after the
                // debounce, so a quick dismissal cannot lose the last one.
                Task { await study.flushStateWrite() }
            }
            .sheet(item: $leech) { target in
                LeechRewriteSheet(
                    study: study,
                    setID: target.setID,
                    card: target.card,
                    lapses: target.lapses,
                    onOpenSource: sourceAction(for: target.card) == nil
                        ? nil
                        : { openSource(of: target.card) }
                )
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

    // MARK: - Card

    private func cardView(_ item: StudyQueueItem, pass: ReviewPass) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                ProgressView(value: pass.progress)
                HStack {
                    Text("\(pass.reviewedCount) reviewed")
                    Spacer()
                    if showsSetName {
                        Text(item.setTitle)
                            .lineLimit(1)
                        Spacer()
                    }
                    Text("\(pass.remainingCount) left")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 22) {
                    if sourceAction(for: item.card) != nil {
                        sourceButton(for: item.card)
                    }

                    Text("QUESTION")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    Text(item.card.question)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)

                    if revealed {
                        recallAndAnswer(item)
                    } else {
                        recallPrompt
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }

            bottomBar(item, pass: pass)
        }
    }

    /// Before the answer: the effortful part. The draft is never saved; it is
    /// there so the recall is written, not just felt.
    private var recallPrompt: some View {
        VStack(spacing: 12) {
            Text("Answer from memory first. Write or say it, then reveal.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            TextField("Your recall (optional)", text: $recallDraft, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 620)
                .accessibilityLabel("Your recall")
        }
    }

    private func recallAndAnswer(_ item: StudyQueueItem) -> some View {
        VStack(spacing: 16) {
            if !trimmedDraft.isEmpty {
                VStack(spacing: 4) {
                    Text("YOUR RECALL")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    Text(recallDraft)
                        .font(.system(size: 17, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 620)
                .padding(12)
                .background(
                    Color.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            Divider().frame(maxWidth: 260)

            Text("ANSWER")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            Text(item.card.answer)
                .font(.system(size: 24, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)

            if leechNotice(item) {
                HStack(spacing: 10) {
                    Label(
                        "This card has lapsed \(leechCount(item)) times.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button("Rewrite…") {
                        leech = LeechTarget(
                            setID: item.setID,
                            card: item.card,
                            lapses: leechCount(item)
                        )
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: 620)
            }
        }
    }

    private func bottomBar(_ item: StudyQueueItem, pass: ReviewPass) -> some View {
        VStack(spacing: 8) {
            if revealed {
                Text("How well did you recall it?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    gradeButton("Again", quality: 1, color: .red, item: item, pass: pass)
                    gradeButton("Hard", quality: 3, color: .orange, item: item, pass: pass)
                    gradeButton("Good", quality: 4, color: .blue, item: item, pass: pass)
                    gradeButton("Easy", quality: 5, color: .green, item: item, pass: pass)
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { revealed = true }
                } label: {
                    Label("Reveal Answer", systemImage: "eye")
                        .font(.headline)
                        .frame(maxWidth: 520)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func gradeButton(
        _ title: String,
        quality: Int,
        color: Color,
        item: StudyQueueItem,
        pass: ReviewPass
    ) -> some View {
        let scheduler = FSRSScheduler()
        let now = Date()
        let days = scheduler.previewIntervalDays(
            state: pass.state(for: item, now: now),
            quality: quality,
            now: now
        )
        return Button {
            grade(quality)
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(intervalLabel(days))
                    .font(.caption2)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func completionView(_ pass: ReviewPass) -> some View {
        ContentUnavailableView {
            Label(
                pass.itemCount == 0 ? "Nothing Due" : "Pass Complete",
                systemImage: pass.itemCount == 0 ? "checkmark.circle" : "checkmark.seal.fill"
            )
        } description: {
            if pass.itemCount == 0 {
                Text("No cards in this scope are due right now.")
            } else {
                Text("\(pass.reviewedCount) card\(pass.reviewedCount == 1 ? "" : "s") reviewed.")
            }
        } actions: {
            if pass.itemCount > 0 {
                Button("Start Another Pass") { startPass() }
                    .buttonStyle(.borderedProminent)
            }
            Button("Done") { dismiss() }
        }
    }

    // MARK: - Actions

    /// Starts the first pass, but leaves it alone if a sheet above this view
    /// made it appear again.
    private func startPassIfNeeded() {
        guard pass == nil else { return }
        startPass()
    }

    private func startPass() {
        let now = Date()
        pass = ReviewPass(
            items: study.queue(
                now: now,
                setID: scope.setID,
                notebookID: scope.notebookID,
                pageID: scope.pageID
            ),
            states: study.allStates,
            now: now
        )
        revealed = false
        recallDraft = ""
    }

    private func grade(_ quality: Int) {
        guard var current = pass, let item = current.currentItem else { return }
        do {
            let result = try current.gradeCurrent(quality: quality, now: Date())
            pass = current
            study.record(result.state, for: result.setID)
            recallDraft = ""
            withAnimation(.easeInOut(duration: 0.18)) { revealed = false }
            if result.state.lapses == ReviewState.leechThreshold {
                leech = LeechTarget(setID: result.setID, card: item.card, lapses: result.state.lapses)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func openSource(of card: StudyCard) {
        guard let onOpenSource,
              let notebookID = card.sourceNotebookID,
              let pageID = card.sourcePageID
        else { return }
        // Close the pass first: the caller is about to reveal the ink behind it.
        dismiss()
        onOpenSource(notebookID, pageID)
    }

    private func sourceAction(for card: StudyCard) -> (() -> Void)? {
        guard onOpenSource != nil,
              let notebookID = card.sourceNotebookID,
              let pageID = card.sourcePageID
        else { return nil }
        return { onOpenSource?(notebookID, pageID) }
    }

    private func sourceButton(for card: StudyCard) -> some View {
        Button {
            openSource(of: card)
        } label: {
            Label("Open Source Page", systemImage: "arrow.up.forward.app")
                .font(.callout)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    private var showsSetName: Bool {
        if case .set = scope { return false }
        return true
    }

    private var trimmedDraft: String {
        recallDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func leechCount(_ item: StudyQueueItem) -> Int {
        pass?.states[item.setID]?[item.card.id]?.lapses ?? 0
    }

    private func leechNotice(_ item: StudyQueueItem) -> Bool {
        leechCount(item) >= ReviewState.leechThreshold
    }

    private func intervalLabel(_ days: Int) -> String {
        if days < 30 {
            return days == 1 ? "1 day" : "\(days) days"
        }
        if days < 365 {
            let months = max(1, Int((Double(days) / 30.0).rounded()))
            return "\(months) mo"
        }
        let years = max(1, Int((Double(days) / 365.0).rounded()))
        return years == 1 ? "1 yr" : "\(years) yr"
    }
}

/// The card a leech sheet is rewriting.
private struct LeechTarget: Identifiable {
    let setID: UUID
    let card: StudyCard
    let lapses: Int

    var id: UUID { card.id }
}
