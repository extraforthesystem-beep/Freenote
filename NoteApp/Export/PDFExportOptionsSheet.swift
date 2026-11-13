import SwiftUI

/// Chooses what a PDF export contains before it runs: which pages, whether
/// the page template is included, how ink is written and whether bookmarks
/// become the PDF's outline.
struct PDFExportOptionsSheet: View {
    let pageCount: Int
    let onExport: (PDFExportOptions) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum PageChoice: Hashable {
        case all, current, range
    }

    @State private var pageChoice: PageChoice = .all
    @State private var rangeFrom = 1
    @State private var rangeTo = 1
    @State private var includeTemplate = true
    @State private var ink: PDFExportOptions.Ink = .flattened
    @State private var includeOutline = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Pages") {
                    Picker("Pages", selection: $pageChoice) {
                        Text("All").tag(PageChoice.all)
                        Text("Current Page").tag(PageChoice.current)
                        Text("Range").tag(PageChoice.range)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if pageChoice == .range {
                        Stepper("From page \(rangeFrom)", value: $rangeFrom, in: 1...max(pageCount, 1))
                        Stepper("To page \(rangeTo)", value: $rangeTo, in: 1...max(pageCount, 1))
                    }
                }

                Section {
                    Toggle("Include Page Template", isOn: $includeTemplate)
                } footer: {
                    Text("Off exports your notes on plain white, or over the imported PDF.")
                }

                Section {
                    Picker("Ink", selection: $ink) {
                        Text("Flattened (Vector)").tag(PDFExportOptions.Ink.flattened)
                        Text("Editable Annotations").tag(PDFExportOptions.Ink.editable)
                    }
                } header: {
                    Text("Ink")
                } footer: {
                    Text(
                        ink == .flattened
                            ? "Ink is part of the page: sharp at any zoom and looks the same everywhere."
                            : "Each stroke is a PDF annotation other apps can select, move, recolour or erase."
                    )
                }

                Section {
                    Toggle("Include Bookmarks as Outline", isOn: $includeOutline)
                } footer: {
                    Text("Bookmarked and titled pages appear as the PDF's table of contents.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export PDF")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        let options = options
                        dismiss()
                        onExport(options)
                    }
                    .disabled(pageCount == 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
        .onAppear {
            rangeFrom = 1
            rangeTo = max(pageCount, 1)
        }
    }

    private var options: PDFExportOptions {
        var options = PDFExportOptions()
        switch pageChoice {
        case .all: options.pages = .all
        case .current: options.pages = .current
        case .range: options.pages = .range(from: rangeFrom, to: rangeTo)
        }
        options.includeTemplate = includeTemplate
        options.ink = ink
        options.includeOutline = includeOutline
        return options
    }
}
