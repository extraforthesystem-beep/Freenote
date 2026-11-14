import NoteCore
import SwiftUI

/// Quiz with Tape: the floating controls for reviewing a page of taped-over ink.
///
/// The tape itself is already tappable on the page. This bar adds the two
/// things a study pass needs — a count of how many pieces have been lifted and
/// a way to lift or replace all of them at once.
struct TapeStudyControls: View {
    let session: NotebookSession
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: "bandage")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            // Each child reads `session.tapeIDs` itself. Neither the bar nor its
            // children read `session.page`, which changes with every stroke, so
            // writing ink does not rebuild this chrome.
            TapeStudyStatus(session: session)

            Divider()
                .frame(height: 24)

            TapeStudyActions(session: session, onClose: onClose)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, AppSpacing.m)
        .padding(.vertical, AppSpacing.m)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }
}

/// The "N of M revealed" caption.
private struct TapeStudyStatus: View {
    let session: NotebookSession

    var body: some View {
        let ids = session.tapeIDs
        let revealed = ids.filter { session.revealedTapeIDs.contains($0) }.count
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("Quiz with Tape")
                .font(.caption.weight(.semibold))
            Text(
                ids.isEmpty
                    ? "No tape on this page"
                    : "\(revealed) of \(ids.count) revealed"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// Reveal All, Hide All and the close button.
private struct TapeStudyActions: View {
    let session: NotebookSession
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ids = session.tapeIDs
        let revealed = ids.filter { session.revealedTapeIDs.contains($0) }.count
        HStack(spacing: AppSpacing.m) {
            Button("Reveal All") {
                revealAll(ids)
            }
            .disabled(ids.isEmpty || revealed == ids.count)
            Button("Hide All") {
                hideAll()
            }
            .disabled(revealed == 0)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("End quiz with tape")
        }
    }

    private func revealAll(_ ids: [UUID]) {
        AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) {
            session.setRevealedTape(Set(ids))
        }
    }

    private func hideAll() {
        AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) {
            session.setRevealedTape([])
        }
    }
}
