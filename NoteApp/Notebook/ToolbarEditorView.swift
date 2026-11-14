import SwiftUI

/// Edits which items sit in the editor toolbar. Changes write straight to the
/// shared `@AppStorage` string, so the toolbar behind the sheet updates live.
struct ToolbarEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ToolbarLayout.storageKey) private var storedLayout = ToolbarLayout.defaultStorage
    @State private var layout = ToolbarLayout()
    @State private var showsResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Pen", systemImage: "pencil.tip")
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Pen")
                    .accessibilityHint("Always in the toolbar and cannot be removed")
                    ForEach(layout.items) { item in
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .onMove { offsets, destination in
                        layout.move(fromOffsets: offsets, toOffset: destination)
                    }
                    .onDelete { offsets in
                        layout.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("In Toolbar")
                } footer: {
                    Text(
                        "Drag to reorder, then swipe or use the delete control to remove an item. "
                            + "The pen is always first; Undo and Redo sit at the leading edge of the bar."
                    )
                }

                Section("More Items") {
                    ForEach(layout.available) { item in
                        HStack {
                            Label(item.title, systemImage: item.systemImage)
                            Spacer()
                            Button {
                                layout.add(item)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(item.title)")
                        }
                    }
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Customise Toolbar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset to Default") {
                        showsResetConfirmation = true
                    }
                    .disabled(layout.isDefault)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Reset the toolbar?", isPresented: $showsResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { layout.reset() }
            } message: {
                Text("Puts the default tools back and removes the others.")
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        .onAppear { layout = ToolbarLayout(storage: storedLayout) }
        .onChange(of: layout) { _, newLayout in
            storedLayout = newLayout.storage
        }
    }
}
