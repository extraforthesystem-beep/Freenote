import NoteCore
import SwiftUI

/// Manual backup and verified restore of the whole library.
///
/// The archive lives beside the library, not inside it, and holds plain JSON and
/// the original page and asset files with a SHA-256 for each one. Restoring adds
/// notebooks; it never overwrites one that is already in the library.
struct BackupView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var backups: [BackupArchive.Summary] = []
    @State private var isWorking = false
    @State private var statusText: String?
    @State private var errorText: String?
    @State private var pendingDelete: BackupArchive.Summary?
    @State private var exportURLs: [URL] = []
    @State private var showsRestorePicker = false

    private var directory: URL {
        model.store.root
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                backupSection
                backupsSection
                restoreSection
                checkSection
                if let statusText {
                    Section {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Backup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                        .padding(28)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .task { reloadList() }
            .confirmationDialog(
                "Delete this backup?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { backup in
                Button("Delete Backup", role: .destructive) { delete(backup) }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { backup in
                Text("\(backup.url.lastPathComponent) is removed from this iPad. Copies you exported are not affected.")
            }
            .alert(
                "Backup failed",
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            #if os(iOS)
            .sheet(isPresented: $showsRestorePicker) {
                BackupFolderImporter(
                    onPick: { url in
                        showsRestorePicker = false
                        restore(from: url)
                    },
                    onCancel: { showsRestorePicker = false }
                )
            }
            .sheet(isPresented: Binding(
                get: { !exportURLs.isEmpty },
                set: { if !$0 { exportURLs = [] } }
            )) {
                BackupFolderExporter(urls: exportURLs) { exportURLs = [] }
            }
            #endif
        }
    }

    // MARK: - Sections

    private var backupSection: some View {
        Section {
            Button {
                backUp()
            } label: {
                Label("Back Up Now", systemImage: "externaldrive.badge.plus")
            }
        } header: {
            Text("Back Up")
        } footer: {
            Text("Writes every notebook, page and attachment to a .noteappbackup folder, with a SHA-256 for every file. Open it in Files or export it to iCloud Drive to keep a copy off this iPad.")
        }
    }

    private var backupsSection: some View {
        Section("Backups on this iPad") {
            if backups.isEmpty {
                Text("No backups yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(backups) { backup in
                    row(backup)
                }
                .onDelete { offsets in
                    pendingDelete = offsets.compactMap { backups.indices.contains($0) ? backups[$0] : nil }.first
                }
            }
        }
    }

    private var restoreSection: some View {
        Section {
            #if os(iOS)
            Button {
                showsRestorePicker = true
            } label: {
                Label("Restore from Backup…", systemImage: "arrow.down.doc")
            }
            #else
            Text("Restore a backup from the iPad.")
                .foregroundStyle(.secondary)
            #endif
        } header: {
            Text("Restore")
        } footer: {
            Text("Every file in the backup is checked against its recorded checksum before anything is written. Restored notebooks are added to this library; a notebook that is already here is kept and the restored one is saved beside it.")
        }
    }

    private func row(_ backup: BackupArchive.Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(backup.url.deletingPathExtension().lastPathComponent)
                .font(.body.weight(.medium))
            Text("\(backup.manifest.notebookCount) notebooks · \(backup.manifest.pageCount) pages · \(Self.byteText(backup.byteCount))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(backup.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Verify") { verifyBackup(backup) }
                    .buttonStyle(.bordered)
                    .font(.caption)
                #if os(iOS)
                Button("Export…") { exportURLs = [backup.url] }
                    .buttonStyle(.bordered)
                    .font(.caption)
                #endif
            }
        }
        .padding(.vertical, 2)
        .swipeActions {
            Button("Delete", role: .destructive) { pendingDelete = backup }
        }
    }

    private var checkSection: some View {
        Section {
            Button {
                verifyPages()
            } label: {
                Label("Verify All Pages", systemImage: "checkmark.shield")
            }
        } header: {
            Text("Check")
        } footer: {
            Text("Reads every page and compares it with the SHA-256 recorded when it was saved, so silent damage is found before it spreads to a backup.")
        }
    }

    // MARK: - Actions

    private func backUp() {
        guard !isWorking else { return }
        isWorking = true
        statusText = nil
        let url = directory.appendingPathComponent(
            "NoteApp \(Self.stampFormatter.string(from: Date())).\(BackupArchive.fileExtension)",
            isDirectory: true
        )
        Task {
            do {
                let summary = try await BackupArchive.create(from: model.store, at: url)
                statusText = "Backed up \(summary.manifest.notebookCount) notebooks and \(summary.manifest.pageCount) pages. All \(summary.fileCount) files verified."
                reloadList()
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }

    /// The picker returns a security-scoped folder; access lasts until the copy
    /// and its verification are done.
    private func restore(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        isWorking = true
        statusText = nil
        Task {
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let summary = try await BackupArchive.restore(archiveAt: url, into: model.store)
                await model.reload()
                for notebook in model.notebooks where summary.restoredNotebookIDs.contains(notebook.id) {
                    await model.search.index(notebook: notebook, store: model.store)
                }
                statusText = restoreText(summary)
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func restoreText(_ summary: BackupArchive.RestoreSummary) -> String {
        var text = "Restored \(summary.restoredNotebookIDs.count) notebooks and \(summary.pageCount) pages. Every file matched its checksum."
        if summary.renamedNotebookIDs.count > 0 {
            text += " \(summary.renamedNotebookIDs.count) already existed here and were saved as copies."
        }
        if summary.unreadableNotebookCount > 0 {
            text += " \(summary.unreadableNotebookCount) restored notebooks could not be read and need repair."
        }
        return text
    }

    private func verifyBackup(_ backup: BackupArchive.Summary) {
        guard !isWorking else { return }
        isWorking = true
        statusText = nil
        Task {
            do {
                let verified = try await BackupArchive.verify(archiveAt: backup.url)
                statusText = "\(backup.url.deletingPathExtension().lastPathComponent) is intact: all \(verified.fileCount) files verified."
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }

    /// Pages written before checksums existed get one on this pass; pages that no
    /// longer match are counted, not changed.
    private func verifyPages() {
        guard !isWorking else { return }
        isWorking = true
        statusText = nil
        Task {
            var checked = 0
            var failed = 0
            for notebook in model.notebooks {
                guard let snapshot = try? await model.store.loadNotebook(notebook.id) else {
                    // An unreadable manifest is already reported by the library.
                    continue
                }
                for pageID in snapshot.manifest.pageOrder {
                    do {
                        _ = try await model.store.verifyPageFile(pageID, in: notebook.id)
                        checked += 1
                    } catch {
                        failed += 1
                    }
                }
            }
            statusText = failed == 0
                ? "Every page is intact: \(checked) pages match their checksums."
                : "\(checked) pages are intact and \(failed) failed their checks. Open a notebook to set a damaged page aside."
            isWorking = false
        }
    }

    private func delete(_ backup: BackupArchive.Summary) {
        guard !isWorking else { return }
        pendingDelete = nil
        do {
            try FileManager.default.removeItem(at: backup.url)
            reloadList()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func reloadList() {
        backups = BackupArchive.summaries(in: directory)
    }

    private static func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()
}
