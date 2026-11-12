import NoteCore
import SwiftUI

/// The app's settings sheet, grouped the way Goodnotes groups its own.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let model: AppModel

    @AppStorage(AppSettings.Key.showPageNumber) private var showPageNumber = true
    @AppStorage(AppSettings.Key.openDocumentsAsNewTabs) private var openDocumentsAsNewTabs = true
    @AppStorage(AppSettings.Key.newNotebookPaperSize) private var paperSize: PaperSize = .a4
    @AppStorage(AppSettings.Key.newNotebookOrientation) private var orientation: PageOrientation = .portrait
    @AppStorage(AppSettings.Key.newNotebookTemplateID) private var templateID = AppSettings.defaultTemplateID
    @AppStorage(AppSettings.Key.handwritingRecognitionEnabled) private var handwritingRecognition = true
    @AppStorage(AppSettings.Key.holdToDrawShapes) private var holdToDrawShapes = true

    @State private var isRebuildingSearch = false
    @State private var didRebuildSearch = false
    @State private var isRegeneratingThumbnails = false
    @State private var didRegenerateThumbnails = false

    var body: some View {
        NavigationStack {
            Form {
                documentEditing
                writing
                newNotebooks
                handwritingRecognitionSection
                troubleshooting
                about
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var documentEditing: some View {
        Section {
            Toggle("Show Page Number", isOn: $showPageNumber)
            Toggle("Open Documents as New Tabs", isOn: $openDocumentsAsNewTabs)
        } header: {
            Text("Document Editing")
        } footer: {
            Text("When off, opening a notebook replaces the current tab.")
        }
    }

    private var writing: some View {
        Section {
            Toggle("Hold to Draw Shapes", isOn: $holdToDrawShapes)
        } header: {
            Text("Writing")
        } footer: {
            Text("Pause at the end of a stroke before lifting the Pencil to turn it into a straight line, rectangle, triangle or ellipse.")
        }
    }

    private var newNotebooks: some View {
        Section {
            Picker("Paper Size", selection: $paperSize) {
                ForEach(PaperSize.allCases) { size in
                    Text(size.displayName).tag(size)
                }
            }
            Picker("Orientation", selection: $orientation) {
                ForEach(PageOrientation.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.segmented)
            Picker("Template", selection: $templateID) {
                ForEach(PageTemplateCatalog.all) { item in
                    Text(item.name).tag(item.id)
                }
            }
        } header: {
            Text("New Notebooks")
        } footer: {
            Text("Used for the first page of notebooks you create.")
        }
    }

    private var handwritingRecognitionSection: some View {
        Section {
            Toggle("Index Handwritten Notes", isOn: $handwritingRecognition)
        } header: {
            Text("Handwriting Recognition")
        } footer: {
            Text("Notebooks will be searchable when enabled. Recognition runs on this device.")
        }
    }

    private var troubleshooting: some View {
        Section("Troubleshooting") {
            maintenanceRow(
                "Rebuild Search Index",
                isRunning: isRebuildingSearch,
                isDone: didRebuildSearch
            ) {
                isRebuildingSearch = true
                didRebuildSearch = false
                Task {
                    await model.rebuildSearchIndex()
                    isRebuildingSearch = false
                    didRebuildSearch = true
                }
            }
            maintenanceRow(
                "Regenerate Thumbnails",
                isRunning: isRegeneratingThumbnails,
                isDone: didRegenerateThumbnails
            ) {
                isRegeneratingThumbnails = true
                didRegenerateThumbnails = false
                Task {
                    await model.regenerateThumbnails()
                    isRegeneratingThumbnails = false
                    didRegenerateThumbnails = true
                }
            }
        }
        .disabled(isRebuildingSearch || isRegeneratingThumbnails)
    }

    private var about: some View {
        Section("About") {
            LabeledContent("NoteApp", value: appVersion)
        }
    }

    // MARK: - Pieces

    /// A full-width row that turns its trailing edge into a spinner while the
    /// maintenance task runs and a "Done" mark once it finishes.
    private func maintenanceRow(
        _ title: String,
        isRunning: Bool,
        isDone: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isRunning {
                    ProgressView()
                } else if isDone {
                    Label("Done", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(isDone ? "\(title), done" : title)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }
}
