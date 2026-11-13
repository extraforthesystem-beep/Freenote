import StudyKit
import SwiftUI

/// A Smart Learn pass: question, reveal, grade, next due card.
struct StudyReviewView: View {
    @Bindable var study: StudyModel
    let setID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var session: SmartLearnSession?
    @State private var revealed = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    if session.isFinished {
                        completionView
                    } else if let card = session.currentCard {
                        cardView(card, session: session)
                    } else {
                        completionView
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Smart Learn")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: startSession)
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

    private func cardView(_ card: StudyCard, session: SmartLearnSession) -> some View {
        VStack(spacing: 0) {
            ProgressView(value: session.progress)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            HStack {
                Text("\(session.reviewedCount) reviewed")
                Spacer()
                Text("\(session.remainingCount) left")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.top, 6)

            Spacer()

            ScrollView {
                VStack(spacing: 24) {
                    Text("QUESTION")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    Text(card.question)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)

                    if revealed {
                        Divider().frame(maxWidth: 260)
                        Text("ANSWER")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                        Text(card.answer)
                            .font(.system(size: 24, weight: .regular, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 620)
                    }
                }
                .padding(32)
            }

            Spacer()

            if revealed {
                gradeButtons
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { revealed = true }
                } label: {
                    Text("Show Answer")
                        .font(.headline)
                        .frame(maxWidth: 520)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var gradeButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                gradeButton("Again", quality: 1, color: .red)
                gradeButton("Hard", quality: 3, color: .orange)
                gradeButton("Good", quality: 4, color: .blue)
                gradeButton("Easy", quality: 5, color: .green)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func gradeButton(_ title: String, quality: Int, color: Color) -> some View {
        Button {
            grade(quality)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private var completionView: some View {
        ContentUnavailableView {
            Label("Session Complete", systemImage: "checkmark.seal.fill")
        } description: {
            Text("Every due card in this pass has been reviewed.")
        } actions: {
            Button("Start Another Pass") {
                startSession()
            }
            .buttonStyle(.borderedProminent)
            Button("Done") { dismiss() }
        }
    }

    private func startSession() {
        guard let set = study.set(withID: setID) else { return }
        session = SmartLearnSession(
            set: set,
            states: study.states(for: setID),
            now: Date()
        )
        revealed = false
    }

    private func grade(_ quality: Int) {
        guard var current = session else { return }
        do {
            let state = try current.gradeCurrent(quality: quality, now: Date())
            session = current
            study.record(state, for: setID)
            withAnimation(.easeInOut(duration: 0.18)) { revealed = false }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
