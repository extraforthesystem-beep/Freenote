import HistoryKit
import SwiftUI

/// Local page history. Snapshots never leave the device and are not part of the
/// notebook file, so restoring one cannot affect sync.
struct VersionHistoryView: View {
    let session: NotebookSession

    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [VersionSnapshot] = []
    @State private var isLoading = true
    @State private var restoringID: UUID?
    @State private var errorText: String?
    @State private var pendingRestore: VersionSnapshot?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Reading history…")
                } else if snapshots.isEmpty {
                    ContentUnavailableView {
                        Label("No History", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Versions appear here after you edit this page.")
                    }
                } else {
                    List {
                        ForEach(snapshots) { snapshot in
                            row(snapshot)
                        }
                    }
                }
            }
            .navigationTitle("Version History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                snapshots = await session.pageHistory()
                isLoading = false
            }
            .confirmationDialog(
                pendingRestore.map {
                    "Replace this page with the version from \($0.createdAt.formatted(date: .abbreviated, time: .shortened))?"
                } ?? "",
                isPresented: Binding(
                    get: { pendingRestore != nil },
                    set: { if !$0 { pendingRestore = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingRestore
            ) { snapshot in
                Button("Replace Page", role: .destructive) { restore(snapshot) }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: { _ in
                Text("The page as it is now is kept in history, so you can switch back.")
            }
            .alert("Restore failed", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private func row(_ snapshot: VersionSnapshot) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.body.weight(.medium))
                Text("\(snapshot.reason) · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.byteCount), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(restoringID == snapshot.id ? "Restoring…" : "Restore") {
                pendingRestore = snapshot
            }
            .buttonStyle(.bordered)
            .disabled(restoringID != nil)
        }
        .padding(.vertical, 3)
    }

    private func restore(_ snapshot: VersionSnapshot) {
        pendingRestore = nil
        restoringID = snapshot.id
        Task {
            let restored = await session.restore(snapshot)
            restoringID = nil
            if restored {
                // The banner would repeat what the dismissal already shows.
                dismiss()
            } else {
                errorText = session.errorMessage ?? session.loadError ?? "That version could not be restored."
                session.errorMessage = nil
            }
        }
    }
}
