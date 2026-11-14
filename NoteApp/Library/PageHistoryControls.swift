import SwiftUI

/// Back and forward through the pages visited in this notebook, like a browser's
/// history: jumping back keeps the forward steps until a new page is opened.
/// The arrow keys are the toolbar chevrons' hardware-keyboard pair (⌘[ and ⌘]).
struct PageHistoryControls: View {
    let session: NotebookSession

    var body: some View {
        if session.hasPageHistory {
            HStack(spacing: 0) {
                historyButton(
                    "Back",
                    systemImage: "chevron.backward",
                    isEnabled: session.canGoBack
                ) {
                    await session.goBack()
                }
                Rectangle()
                    .fill(.separator)
                    .frame(width: 0.5, height: 18)
                historyButton(
                    "Forward",
                    systemImage: "chevron.forward",
                    isEnabled: session.canGoForward
                ) {
                    await session.goForward()
                }
            }
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }

    private func historyButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .accessibilityLabel(title == "Back" ? "Back in page history" : "Forward in page history")
    }
}
