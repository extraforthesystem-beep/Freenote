import Foundation
import NoteCore
import Observation
import SwiftUI

/// Drives the PDF import sheet: read the file, unlock it when needed, let the
/// user choose pages, then import.
///
/// Both entry points — a notebook from the library and pages into an open
/// notebook — share it, so the password and range questions behave the same.
/// The file's security scope stays open until the sheet goes away.
@MainActor
@Observable
final class PDFImportFlow: Identifiable {
    enum Destination {
        case newNotebook
        case insert(NotebookSession)
    }

    enum Phase {
        case reading
        case needsPassword(message: String?)
        case choosing(PDFDocumentInfo)
        case importing(fraction: Double)
        /// The user stopped the import; nothing that was not written stays.
        case cancelled
        case failed(String)
    }

    let id = UUID()
    let destination: Destination
    private(set) var phase: Phase = .reading
    /// The sheet closes itself when this becomes true.
    private(set) var isFinished = false
    private(set) var pageCount = 0
    /// How many pages the running import is making.
    private(set) var importPageCount = 0
    /// True once Cancel was pressed, so it is not pressed twice.
    private(set) var isCancelling = false

    private let model: AppModel
    private let url: URL
    /// Held only while the sheet is open; never stored or logged.
    private var password: String?
    private var hasStarted = false
    private var isAccessingFile = false
    /// The running import. Held so Cancel can stop it, and so the file's
    /// security scope is only released once nothing is reading it.
    private var importTask: Task<Void, Never>?

    init(model: AppModel, url: URL, destination: Destination) {
        self.model = model
        self.url = url
        self.destination = destination
    }

    var isInsert: Bool {
        if case .insert = destination { return true }
        return false
    }

    var title: String {
        isInsert ? "Insert PDF Pages" : "Import PDF"
    }

    /// "Import" for a new notebook, "Insert" for pages added to one: the sheet's
    /// title, button, progress and messages all use the same verb.
    var actionWord: String {
        isInsert ? "Insert" : "Import"
    }

    var workingWord: String {
        isInsert ? "Inserting" : "Importing"
    }

    /// True while the import cannot be cancelled safely.
    var isWorking: Bool {
        switch phase {
        case .reading, .importing: true
        case .needsPassword, .choosing, .failed, .cancelled: false
        }
    }

    /// True while the file is only being read, before there is anything to
    /// choose: short enough that the sheet stays shut instead of offering
    /// Cancel. An import can always be stopped.
    var isReading: Bool {
        if case .reading = phase { return true }
        return false
    }

    /// True when the only thing left to do is close the sheet.
    var isFailed: Bool {
        switch phase {
        case .failed, .cancelled: true
        case .reading, .needsPassword, .choosing, .importing: false
        }
    }

    // MARK: - Steps

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isAccessingFile = url.startAccessingSecurityScopedResource()
        await read()
    }

    func submitPassword(_ value: String) async {
        guard !value.isEmpty else { return }
        password = value
        await read()
    }

    /// Starts the import and holds its task, so it can be stopped.
    func startImport(
        selection: PDFPageSelection,
        insertAtEnd: Bool,
        margin: PDFPageMargin
    ) {
        guard case .choosing = phase, importTask == nil else { return }
        importPageCount = selection.pdfIndices(pageCount: pageCount).count
        report(0)
        importTask = Task { [weak self] in
            await self?.performImport(
                selection: selection,
                insertAtEnd: insertAtEnd,
                margin: margin
            )
        }
    }

    private func performImport(
        selection: PDFPageSelection,
        insertAtEnd: Bool,
        margin: PDFPageMargin
    ) async {
        do {
            switch destination {
            case .newNotebook:
                try await model.importPDF(
                    from: url,
                    selection: selection,
                    margin: margin,
                    password: password
                ) { [weak self] fraction in
                    Task { @MainActor in self?.report(fraction) }
                }
            case let .insert(session):
                let result = try await PDFImporter.insertPages(
                    at: url,
                    into: session,
                    selection: selection,
                    atEnd: insertAtEnd,
                    margin: margin,
                    password: password
                ) { [weak self] fraction in
                    Task { @MainActor in self?.report(fraction) }
                }
                for (pageID, title) in result.titles {
                    model.outline.setTitle(title, notebookID: session.notebookID, pageID: pageID)
                }
            }
            isFinished = true
        } catch is CancellationError {
            // Stopped between pages: the pages not reached were never started,
            // and the ones already written stay in the notebook.
            phase = .cancelled
        } catch {
            phase = .failed(error.localizedDescription)
        }
        importTask = nil
        releaseFileIfIdle()
    }

    /// Stops a running import at the next page boundary.
    func cancel() {
        guard importTask != nil else { return }
        isCancelling = true
        importTask?.cancel()
    }

    /// Releases the file and forgets the password once nothing is reading it.
    func close() {
        importTask?.cancel()
        releaseFileIfIdle()
    }

    private func releaseFileIfIdle() {
        // A cancelled import may still be unwinding; the file has to stay
        // readable until it has stopped.
        guard importTask == nil else { return }
        if isAccessingFile {
            url.stopAccessingSecurityScopedResource()
            isAccessingFile = false
        }
        password = nil
    }

    // MARK: - Reading

    private func read() async {
        phase = .reading
        do {
            let info = try await PDFImporter.inspect(at: url, password: password)
            pageCount = info.pageCount
            phase = .choosing(info)
        } catch PDFImportError.passwordRequired {
            phase = .needsPassword(message: nil)
        } catch PDFImportError.wrongPassword {
            phase = .needsPassword(message: PDFImportError.wrongPassword.errorDescription)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Progress arrives from a background task, so it is clamped and never
    /// allowed to move backwards or overwrite a failure or a cancel.
    private func report(_ fraction: Double) {
        guard !isFinished else { return }
        if case .failed = phase { return }
        if case .cancelled = phase { return }
        if case let .importing(current) = phase, fraction < current { return }
        phase = .importing(fraction: min(max(fraction, 0), 1))
    }
}

/// The import sheet: one set of pages, whatever step the flow is on.
struct PDFImportSheet: View {
    @Bindable var flow: PDFImportFlow
    @Environment(\.dismiss) private var dismiss

    @State private var typedPassword = ""
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .navigationTitle(flow.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(flow.isFailed ? "Close" : "Cancel") {
                        if !flow.isFailed {
                            flow.cancel()
                        }
                        dismiss()
                    }
                    .disabled(flow.isReading || flow.isCancelling)
                }
            }
            .interactiveDismissDisabled(flow.isWorking)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
        .task { await flow.start() }
        .onChange(of: flow.isFinished) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear { flow.close() }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.phase {
        case .reading:
            Section {
                HStack(spacing: AppSpacing.m) {
                    ProgressView()
                    Text("Reading the PDF…")
                }
            }
        case let .needsPassword(message):
            passwordSection(message: message)
        case let .choosing(info):
            PDFPageChoiceForm(info: info, isInsert: flow.isInsert) { selection, insertAtEnd, margin in
                flow.startImport(
                    selection: selection,
                    insertAtEnd: insertAtEnd,
                    margin: margin
                )
            }
        case let .importing(fraction):
            Section {
                if flow.importPageCount > PDFImporter.progressPageThreshold {
                    ProgressView(value: fraction)
                    Text("\(flow.workingWord) \(flow.importPageCount) pages…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: AppSpacing.m) {
                        ProgressView()
                        Text("\(flow.workingWord)…")
                    }
                }
            }
        case .cancelled:
            Section {
                Label(
                    "\(flow.actionWord) cancelled",
                    systemImage: "xmark.circle"
                )
                Text("The pages not reached were not started. Any pages already inserted are kept.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case let .failed(message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
            }
        }
    }

    @ViewBuilder
    private func passwordSection(message: String?) -> some View {
        Section {
            SecureField("Password", text: $typedPassword)
                .focused($isPasswordFocused)
                .onSubmit(unlock)
                #if os(iOS)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Password Protected")
        } footer: {
            Text("The password is only used to read the file. It is not saved with the notebook.")
        }

        Section {
            Button("Unlock", action: unlock)
                .disabled(typedPassword.isEmpty)
        }
        .onAppear { isPasswordFocused = true }
    }

    private func unlock() {
        let value = typedPassword
        typedPassword = ""
        Task { await flow.submitPassword(value) }
    }
}

/// The page range question, with "all pages" one tap away.
private struct PDFPageChoiceForm: View {
    let info: PDFDocumentInfo
    let isInsert: Bool
    let onImport: (PDFPageSelection, Bool, PDFPageMargin) -> Void

    @State private var usesRange = false
    @State private var fromPage: Int
    @State private var toPage: Int
    @State private var insertAtEnd = false
    @State private var margin: PDFPageMargin = .none

    init(
        info: PDFDocumentInfo,
        isInsert: Bool,
        onImport: @escaping (PDFPageSelection, Bool, PDFPageMargin) -> Void
    ) {
        self.info = info
        self.isInsert = isInsert
        self.onImport = onImport
        _fromPage = State(initialValue: 1)
        _toPage = State(initialValue: max(info.pageCount, 1))
    }

    var body: some View {
        Section {
            Picker("Pages", selection: $usesRange) {
                Text("All Pages").tag(false)
                Text("Range").tag(true)
            }
            .pickerStyle(.segmented)

            if usesRange {
                LabeledContent("From") {
                    pageField($fromPage)
                }
                LabeledContent("To") {
                    pageField($toPage)
                }
            }

            if isInsert {
                Toggle("Insert at end of notebook", isOn: $insertAtEnd)
            }
        } header: {
            Text("Pages")
        } footer: {
            Text(
                isInsert
                    ? "The pages go after the page you are on unless you insert them at the end."
                    : "One notebook page is made for each chosen PDF page. The PDF is copied into the notebook once."
            )
        }

        Section {
            Picker("Writing Margin", selection: $margin) {
                ForEach(PDFPageMargin.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Writing Margin")
        } footer: {
            Text("Blank space beside each page to write notes in. The page grows; the PDF keeps its own size.")
        }

        Section {
            Button(actionTitle) {
                onImport(selection, isInsert && insertAtEnd, margin)
            }
        }
    }

    private var selection: PDFPageSelection {
        usesRange ? .range(from: fromPage, to: toPage) : .all
    }

    private var chosenCount: Int {
        selection.pdfIndices(pageCount: info.pageCount).count
    }

    private var actionTitle: String {
        let verb = isInsert ? "Insert" : "Import"
        return chosenCount == 1 ? "\(verb) Page" : "\(verb) \(chosenCount) Pages"
    }

    private func pageField(_ value: Binding<Int>) -> some View {
        TextField("Page", value: value, format: .number)
            .multilineTextAlignment(.trailing)
            .labelsHidden()
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
    }
}
