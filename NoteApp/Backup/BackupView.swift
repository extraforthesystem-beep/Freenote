import NoteCore
import Observation
import SwiftUI

/// Carries a running operation's progress and label from the archive's
/// background task to the sheet. The view value itself cannot cross that
/// boundary; this small main-actor object can.
@MainActor
@Observable
final class BackupRunState {
    /// The latest progress of the running operation, when it reports any.
    var progress: BackupArchive.Progress?
    /// What the overlay says before the first progress arrives.
    var title = ""

    /// The handler to hand to `BackupArchive`.
    nonisolated var handler: BackupArchive.ProgressHandler {
        { [weak self] progress in
            Task { @MainActor in self?.progress = progress }
        }
    }
}

/// Manual backup and verified restore of the whole library.
///
/// The archive lives beside the library, not inside it, and holds plain JSON and
/// the original page and asset files with a SHA-256 for each one. Restoring adds
/// notebooks; it never overwrites one that is already in the library.
struct BackupView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var backups: [BackupArchive.Summary] = []
    /// True while the backup list is being read and measured off the main actor.
    @State private var isLoadingList = true
    @State private var isWorking = false
    @State private var run = BackupRunState()
    @State private var statusText: String?
    @State private var errorText: String?
    /// The alert's title, named after the operation that failed.
    @State private var errorTitle = "Backup failed"
    /// The backups a confirmation is about: a swipe or edit select can pick one
    /// or several, and every one of them is deleted.
    @State private var pendingDelete: [BackupArchive.Summary] = []
    @State private var exportURLs: [URL] = []
    @State private var showsRestorePicker = false
    /// Verify and Verify All Pages can be stopped; a backup or a restore
    /// half-way is not safe, so those two do not offer it.
    @State private var canCancelWork = false

    @State private var listTask: Task<Void, Never>?
    @State private var verifyTask: Task<Void, Never>?

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
                    busyOverlay
                }
            }
            .task { reloadList() }
            .onDisappear {
                // A list that is still being read is worthless once the sheet is
                // gone. A backup or a restore is deliberately left running.
                listTask?.cancel()
                verifyTask?.cancel()
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(
                    get: { !pendingDelete.isEmpty },
                    set: { if !$0 { pendingDelete = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button(deleteActionTitle, role: .destructive) { delete(pendingDelete) }
                Button("Cancel", role: .cancel) { pendingDelete = [] }
            } message: {
                Text(deleteMessage)
            }
            .alert(
                errorTitle,
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
            if isLoadingList && backups.isEmpty {
                HStack(spacing: AppSpacing.s) {
                    ProgressView()
                    Text("Reading backups…")
                        .foregroundStyle(.secondary)
                }
            } else if backups.isEmpty {
                Text("No backups yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(backups) { backup in
                    row(backup)
                }
                .onDelete { offsets in
                    // Every selected row is deleted, not just the first.
                    pendingDelete = offsets.compactMap {
                        backups.indices.contains($0) ? backups[$0] : nil
                    }
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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
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
                    .controlSize(.regular)
                    .font(.caption)
                    .hitTarget()
                #if os(iOS)
                Button("Export…") { exportURLs = [backup.url] }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .font(.caption)
                    .hitTarget()
                #endif
            }
        }
        .padding(.vertical, AppSpacing.xxs)
        .swipeActions {
            Button("Delete", role: .destructive) { pendingDelete = [backup] }
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

    /// The modal block over the form: a determinate bar and a count when the
    /// operation knows them, the operation's name either way, and Cancel for the
    /// two checks that can stop safely.
    private var busyOverlay: some View {
        VStack(spacing: AppSpacing.m) {
            if let progress = run.progress, progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
            } else {
                ProgressView()
            }
            Text(overlayText)
                .font(.callout)
                .multilineTextAlignment(.center)
            if canCancelWork {
                Button("Cancel") { cancelWork() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(AppSpacing.xxl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.xl))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(overlayText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var overlayText: String {
        guard let progress = run.progress else { return run.title }
        switch progress.step {
        case .copyingNotebooks:
            return "Backing up notebook \(progress.done) of \(progress.total)…"
        case .checkingFiles:
            return "Checking file \(progress.done) of \(progress.total)…"
        case .checkingPages:
            return "Verifying page \(progress.done) of \(progress.total)…"
        case .restoringNotebooks:
            return "Restoring notebook \(progress.done) of \(progress.total)…"
        }
    }

    // MARK: - Actions

    private func beginWork(title: String, cancellable: Bool) {
        isWorking = true
        run.title = title
        run.progress = nil
        canCancelWork = cancellable
        statusText = nil
    }

    private func endWork() {
        isWorking = false
        canCancelWork = false
        run.progress = nil
        run.title = ""
    }

    private func cancelWork() {
        verifyTask?.cancel()
    }

    private func backUp() {
        guard !isWorking else { return }
        beginWork(title: "Backing up…", cancellable: false)
        let url = directory.appendingPathComponent(
            "NoteApp \(Self.stampFormatter.string(from: Date())).\(BackupArchive.fileExtension)",
            isDirectory: true
        )
        let run = run
        Task {
            do {
                let summary = try await BackupArchive.create(
                    from: model.store,
                    at: url,
                    progress: run.handler
                )
                statusText = "Backed up \(summary.manifest.notebookCount) notebooks and \(summary.manifest.pageCount) pages. All \(summary.fileCount) files verified."
                reloadList()
            } catch {
                errorTitle = "Backup failed"
                errorText = error.localizedDescription
            }
            endWork()
        }
    }

    /// The picker returns a security-scoped folder; access lasts until the copy
    /// and its verification are done.
    private func restore(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        beginWork(title: "Restoring…", cancellable: false)
        let run = run
        Task {
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let summary = try await BackupArchive.restore(
                    archiveAt: url,
                    into: model.store,
                    progress: run.handler
                )
                await model.reload()
                for notebook in model.notebooks where summary.restoredNotebookIDs.contains(notebook.id) {
                    await model.search.index(notebook: notebook, store: model.store)
                }
                statusText = restoreText(summary)
            } catch {
                errorTitle = "Restore failed"
                errorText = error.localizedDescription
            }
            endWork()
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
        let name = backup.url.deletingPathExtension().lastPathComponent
        beginWork(title: "Verifying \(name)…", cancellable: true)
        let run = run
        let url = backup.url
        verifyTask = Task {
            do {
                let verified = try await BackupArchive.verify(archiveAt: url, progress: run.handler)
                statusText = "\(name) is intact: all \(verified.fileCount) files verified."
            } catch is CancellationError {
                statusText = "Verification of \(name) stopped."
            } catch {
                errorTitle = "Verification failed"
                errorText = error.localizedDescription
            }
            endWork()
        }
    }

    /// Pages written before checksums existed get one on this pass; pages that no
    /// longer match are counted, not changed.
    private func verifyPages() {
        guard !isWorking else { return }
        beginWork(title: "Verifying pages…", cancellable: true)
        let total = model.notebooks.reduce(0) { $0 + $1.pageOrder.count }
        let run = run
        verifyTask = Task {
            var done = 0
            var checked = 0
            var failed = 0
            do {
                for notebook in model.notebooks {
                    guard let snapshot = try? await model.store.loadNotebook(notebook.id) else {
                        // An unreadable manifest is already reported by the library.
                        continue
                    }
                    for pageID in snapshot.manifest.pageOrder {
                        try Task.checkCancellation()
                        do {
                            _ = try await model.store.verifyPageFile(pageID, in: notebook.id)
                            checked += 1
                        } catch {
                            failed += 1
                        }
                        done += 1
                        run.progress = BackupArchive.Progress(
                            step: .checkingPages,
                            done: done,
                            total: total
                        )
                    }
                }
                statusText = failed == 0
                    ? "Every page is intact: \(checked) pages match their checksums."
                    : "\(checked) pages are intact and \(failed) failed their checks. Open a notebook to set a damaged page aside."
            } catch is CancellationError {
                statusText = failed == 0
                    ? "Verification stopped after \(done) of \(total) pages."
                    : "Verification stopped after \(done) of \(total) pages: \(checked) intact, \(failed) failed their checks."
            } catch {
                errorTitle = "Verification failed"
                errorText = error.localizedDescription
            }
            endWork()
        }
    }

    private func delete(_ selected: [BackupArchive.Summary]) {
        guard !isWorking, !selected.isEmpty else { return }
        pendingDelete = []
        beginWork(
            title: selected.count == 1 ? "Deleting the backup…" : "Deleting \(selected.count) backups…",
            cancellable: false
        )
        let urls = selected.map(\.url)
        Task {
            // A backup folder holds thousands of files: remove it off the main
            // actor so the sheet keeps drawing.
            let failure = await Task.detached(priority: .userInitiated) { () -> String? in
                for url in urls {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        return error.localizedDescription
                    }
                }
                return nil
            }.value
            if let failure {
                errorTitle = "Delete failed"
                errorText = failure
            }
            endWork()
            reloadList()
        }
    }

    /// Reads and measures every backup off the main actor. `BackupArchive`
    /// stats every file of every archive, which is far too much for the sheet's
    /// own thread.
    private func reloadList() {
        listTask?.cancel()
        isLoadingList = true
        let directory = directory
        listTask = Task {
            let summaries = await Task.detached(priority: .userInitiated) {
                BackupArchive.summaries(in: directory)
            }.value
            guard !Task.isCancelled else { return }
            backups = summaries
            isLoadingList = false
        }
    }

    // MARK: - Delete confirmation copy

    private var deleteTitle: String {
        pendingDelete.count == 1
            ? "Delete this backup?"
            : "Delete \(pendingDelete.count) backups?"
    }

    private var deleteActionTitle: String {
        pendingDelete.count == 1
            ? "Delete Backup"
            : "Delete \(pendingDelete.count) Backups"
    }

    private var deleteMessage: String {
        let names = pendingDelete
            .map { $0.url.deletingPathExtension().lastPathComponent }
            .joined(separator: ", ")
        return pendingDelete.count == 1
            ? "\(names) is removed from this iPad. Copies you exported are not affected."
            : "\(names) are removed from this iPad. Copies you exported are not affected."
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
