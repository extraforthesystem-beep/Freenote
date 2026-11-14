import NoteCore
import SwiftUI

/// Tape study: the floating controls for reviewing a page of taped-over ink.
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

            // Each child reads `session.page` itself. The bar's own layout no
            // longer depends on the page, so writing a stroke does not rebuild
            // it; only the status text and the actions re-evaluate.
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
        let ids = TapeStudy.tapeIDs(in: session.page)
        let revealed = ids.filter { session.revealedTapeIDs.contains($0) }.count
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("Tape Study")
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
        let ids = TapeStudy.tapeIDs(in: session.page)
        let revealed = ids.filter { session.revealedTapeIDs.contains($0) }.count
        HStack(spacing: AppSpacing.m) {
            Button("Reveal All") {
                revealAll(ids)
            }
            .disabled(ids.isEmpty || revealed == ids.count)
            Button("Hide All") {
                hideAll(ids)
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
            .accessibilityLabel("End tape study")
        }
    }

    private func revealAll(_ ids: [UUID]) {
        AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) {
            for id in ids where !session.revealedTapeIDs.contains(id) {
                session.toggleTapeRevealed(id)
            }
        }
    }

    private func hideAll(_ ids: [UUID]) {
        AppMotion.animate(AppMotion.standard, reduceMotion: reduceMotion) {
            for id in ids where session.revealedTapeIDs.contains(id) {
                session.toggleTapeRevealed(id)
            }
        }
    }
}

private enum TapeStudy {
    /// The tape pieces on `page`, in page order. Reading the page only here
    /// keeps the bar itself independent of the page's per-stroke updates.
    static func tapeIDs(in page: Page?) -> [UUID] {
        (page?.visibleElements ?? []).compactMap { element in
            if case .tape = element.content { return element.id }
            return nil
        }
    }
}
