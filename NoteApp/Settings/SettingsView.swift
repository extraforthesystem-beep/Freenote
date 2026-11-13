import NoteCore
import SwiftUI

/// The app's settings sheet, grouped the way Goodnotes groups its own.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let model: AppModel

    @AppStorage(AppSettings.Key.theme) private var theme: AppTheme = .system
    @AppStorage(AppSettings.Key.darkPaper) private var darkPaper = false
    @AppStorage(AppSettings.Key.showPageNumber) private var showPageNumber = true
    @AppStorage(AppSettings.Key.openDocumentsAsNewTabs) private var openDocumentsAsNewTabs = true
    @AppStorage(AppSettings.Key.newNotebookPaperSize) private var paperSize: PaperSize = .a4
    @AppStorage(AppSettings.Key.newNotebookOrientation) private var orientation: PageOrientation = .portrait
    @AppStorage(AppSettings.Key.newNotebookTemplateID) private var templateID = AppSettings.defaultTemplateID
    @AppStorage(AppSettings.Key.handwritingRecognitionEnabled) private var handwritingRecognition = true
    @AppStorage(AppSettings.Key.holdToDrawShapes) private var holdToDrawShapes = true
    @AppStorage(AppSettings.Key.drawWithFinger) private var drawWithFinger = false
    @AppStorage(AppSettings.Key.twoFingerDoubleTapUndo) private var twoFingerDoubleTapUndo = true
    @AppStorage(AppSettings.Key.threeFingerDoubleTapRedo) private var threeFingerDoubleTapRedo = true
    @AppStorage(AppSettings.Key.pencilDoubleTapAction) private var pencilDoubleTapAction: PencilDoubleTapAction = .system
    @AppStorage(AppSettings.Key.pageScrollMode) private var pageScrollMode: PageScrollMode = .vertical
    @AppStorage(AppSettings.Key.rememberLastTool) private var rememberLastTool = true
    @AppStorage(AppSettings.Key.hideStatusBar) private var hideStatusBar = false
    @AppStorage(AppSettings.Key.zoomAutoAdvance) private var zoomAutoAdvance = true
    @AppStorage(AppSettings.Key.zoomMagnification) private var zoomMagnification = 2.5
    @AppStorage(AppSettings.Key.pagesPanelOnLeft) private var pagesPanelOnLeft = false

    @State private var isRebuildingSearch = false
    @State private var didRebuildSearch = false
    @State private var isRegeneratingThumbnails = false
    @State private var didRegenerateThumbnails = false
    @State private var showsToolbarEditor = false

    var body: some View {
        NavigationStack {
            Form {
                appearance
                documentEditing
                writing
                #if os(iOS)
                zoomView
                applePencil
                #endif
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
            .sheet(isPresented: $showsToolbarEditor) {
                ToolbarEditorView()
            }
        }
    }

    // MARK: - Sections

    private var appearance: some View {
        Section {
            Picker("Theme", selection: $theme) {
                ForEach(AppTheme.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Dark Paper in Dark Mode", isOn: $darkPaper)
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows the device's Light or Dark appearance. Notebooks keep white paper whatever the appearance; Dark Paper shows pages in dark grey, with template lines and Pencil ink adapted for reading. PDF and PNG exports always use white paper and true ink colours.")
        }
    }

    private var documentEditing: some View {
        Section {
            Toggle("Show Page Number", isOn: $showPageNumber)
            Toggle("Open Documents as New Tabs", isOn: $openDocumentsAsNewTabs)
            Picker("Page Scrolling", selection: $pageScrollMode) {
                Text("Vertical (Seamless)").tag(PageScrollMode.vertical)
                Text("Horizontal (Single Page)").tag(PageScrollMode.horizontal)
            }
        } header: {
            Text("Document Editing")
        } footer: {
            Text("When off, opening a notebook replaces the current tab. A notebook can choose its own scrolling from its More menu.")
        }
    }

    private var writing: some View {
        Section {
            Toggle("Remember Last Tool", isOn: $rememberLastTool)
            #if os(iOS)
            Toggle("Draw with Finger", isOn: $drawWithFinger)
            Toggle("Hold to Draw Shapes", isOn: $holdToDrawShapes)
            Toggle("Two-Finger Double-Tap to Undo", isOn: $twoFingerDoubleTapUndo)
            Toggle("Three-Finger Double-Tap to Redo", isOn: $threeFingerDoubleTapRedo)
            Toggle("Hide Status Bar in Notebooks", isOn: $hideStatusBar)
            Toggle("Pages Panel on Left", isOn: $pagesPanelOnLeft)
            Button("Customize Toolbar…", systemImage: "slider.horizontal.3") {
                showsToolbarEditor = true
            }
            #endif
        } header: {
            Text("Writing")
        } footer: {
            #if os(iOS)
            Text("Remember Last Tool: a notebook opens with the tool, pen or highlighter you used last. With Draw with Finger off, one finger scrolls the page and only Apple Pencil draws. Hold to Draw Shapes: pause at the end of a stroke before lifting to turn it into a straight line, rectangle, triangle or ellipse. The status bar stays visible in the library.")
            #else
            Text("Remember Last Tool: a notebook opens with the tool, pen or highlighter you used last.")
            #endif
        }
    }

    #if os(iOS)
    private var zoomView: some View {
        Section {
            ZoomViewSettingsRows(autoAdvance: $zoomAutoAdvance, magnification: $zoomMagnification)
        } header: {
            Text("Zoom View")
        } footer: {
            Text("Zoom View magnifies a band of the page to write in. With Auto-Advance on, lifting the Pencil in the shaded right part of the panel moves the band along the line, and at the end of the line to the next one. Drag the frame's corner on the page to change the magnification.")
        }
    }

    private var applePencil: some View {
        Section {
            Picker("Double-Tap Action", selection: $pencilDoubleTapAction) {
                ForEach(PencilDoubleTapAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }
        } header: {
            Text("Apple Pencil")
        } footer: {
            Text("Double-tap works on Apple Pencil (2nd generation) and Apple Pencil Pro.")
        }
    }
    #endif

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
