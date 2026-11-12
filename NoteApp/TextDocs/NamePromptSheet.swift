import SwiftUI

/// A small, sheet-based name prompt.
///
/// Text documents and boards both need "name this thing" flows. A sheet keeps
/// the prompt out of the alert stack, so a write error can still be shown as an
/// alert while the prompt is open.
struct NamePrompt: Identifiable {
    let id = UUID()
    var title: String
    var message: String?
    var value: String
    var actionTitle: String
}

struct NamePromptSheet: View {
    let prompt: NamePrompt
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @FocusState private var isFocused: Bool

    init(prompt: NamePrompt, onSubmit: @escaping (String) -> Void) {
        self.prompt = prompt
        self.onSubmit = onSubmit
        _value = State(initialValue: prompt.value)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(prompt.title, text: $value)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                } footer: {
                    if let message = prompt.message {
                        Text(message)
                    }
                }
            }
            .navigationTitle(prompt.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(prompt.actionTitle) { submit() }
                        .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            // Take focus after the sheet has finished presenting; focusing too
            // early is ignored by UIKit.
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                isFocused = true
            }
        }
        #if os(iOS)
        .presentationDetents([.height(210)])
        #endif
    }

    private func submit() {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onSubmit(name)
        dismiss()
    }
}
