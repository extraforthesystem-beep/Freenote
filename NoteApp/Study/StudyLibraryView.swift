import StudyKit
import SwiftUI
import UniformTypeIdentifiers

/// The study-set library: create, import and open sets, and start a review.
struct StudyLibraryView: View {
    @Bindable var study: StudyModel
    /// False when the view is embedded in the library's detail column instead of a sheet.
    var showsDoneButton = true

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSet: StudySet?
    @State private var showsNewSet = false
    @State private var newSetTitle = ""
    @State private var showsImporter = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = study.lastError {
                    errorBanner(message)
                }
                content
            }
            .navigationTitle("Study")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Study Set", systemImage: "plus") { showsNewSet = true }
                        Button("Import CSV", systemImage: "square.and.arrow.down") { showsImporter = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add study set")
                }
            }
            .alert("New study set", isPresented: $showsNewSet) {
                TextField("Title", text: $newSetTitle)
                Button("Cancel", role: .cancel) { newSetTitle = "" }
                Button("Create") {
                    let title = newSetTitle
                    newSetTitle = ""
                    Task {
                        if let set = await study.createSet(title: title) {
                            selectedSet = set
                        } else {
                            errorText = study.lastError
                        }
                    }
                }
            }
            .sheet(item: $selectedSet) { set in
                StudySetEditorView(study: study, setID: set.id)
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        if let set = await study.importCSV(from: url) {
                            selectedSet = set
                        } else {
                            errorText = study.lastError
                        }
                    }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
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

    @ViewBuilder
    private var content: some View {
        if study.isLoading && study.sets.isEmpty {
            ProgressView("Loading study sets…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if study.sets.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    ForEach(study.sets) { set in
                        row(set)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Tap a set to edit its cards or start a review.")
                }
            }
#if os(iOS)
            .listStyle(.insetGrouped)
#endif
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                study.lastError == nil ? "No Study Sets" : "Nothing Could Be Loaded",
                systemImage: study.lastError == nil
                    ? "rectangle.stack.badge.plus"
                    : "exclamationmark.triangle"
            )
        } description: {
            Text(
                study.lastError == nil
                    ? "Create a set, or import a CSV with question and answer columns."
                    : "The study folder could not be read. Retry, or check the files on disk."
            )
        } actions: {
            if study.lastError != nil {
                Button("Retry") {
                    Task { await study.reload() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("New Study Set") { showsNewSet = true }
                    .buttonStyle(.borderedProminent)
                Button("Import CSV") { showsImporter = true }
            }
        }
    }

    private func row(_ set: StudySet) -> some View {
        let due = study.dueCount(for: set)
        return Button {
            selectedSet = set
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color(for: set.colorTag))
                    .frame(width: 42, height: 52)
                    .overlay {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(set.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(set.cards.count) card\(set.cards.count == 1 ? "" : "s") · \(due) due")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the cards in \(set.title)")
    }

    private func delete(_ offsets: IndexSet) {
        // Snapshot the sets first: each delete shrinks `study.sets`, so reading
        // by index while deleting would run out of bounds.
        let targets = offsets.compactMap { index in
            study.sets.indices.contains(index) ? study.sets[index] : nil
        }
        guard !targets.isEmpty else { return }
        Task {
            for set in targets {
                await study.delete(set)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") {
                Task { await study.reload() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                study.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func color(for tag: String) -> Color {
        switch tag.lowercased() {
        case "red": .red
        case "orange": .orange
        case "green": .green
        case "teal": .teal
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        default: .indigo
        }
    }
}
