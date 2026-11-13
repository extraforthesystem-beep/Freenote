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

    private var tapeIDs: [UUID] {
        (session.page?.visibleElements ?? []).compactMap { element in
            if case .tape = element.content { return element.id }
            return nil
        }
    }

    private var revealedCount: Int {
        tapeIDs.filter { session.revealedTapeIDs.contains($0) }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bandage")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tape Study")
                    .font(.caption.weight(.semibold))
                Text(countText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 24)

            Button("Reveal All") { revealAll() }
                .disabled(tapeIDs.isEmpty || revealedCount == tapeIDs.count)
            Button("Hide All") { hideAll() }
                .disabled(revealedCount == 0)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("End tape study")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }

    private var countText: String {
        if tapeIDs.isEmpty {
            return "No tape on this page"
        }
        return "\(revealedCount) of \(tapeIDs.count) revealed"
    }

    private func revealAll() {
        for id in tapeIDs where !session.revealedTapeIDs.contains(id) {
            session.toggleTapeRevealed(id)
        }
    }

    private func hideAll() {
        for id in tapeIDs where session.revealedTapeIDs.contains(id) {
            session.toggleTapeRevealed(id)
        }
    }
}
