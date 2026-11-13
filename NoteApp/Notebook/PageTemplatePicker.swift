import InkKit
import NoteCore
import SwiftUI
import UniformTypeIdentifiers

struct PageTemplatePicker: View {
    let current: PageTemplate?
    let isApplying: Bool
    let onApplySize: ((PaperSize, PageOrientation, Bool) -> Void)?
    /// Imported templates, when the caller has a library to read them from.
    var customTemplates: CustomTemplateStore?
    /// The notebook's assets, where an applied custom template is copied to.
    var assetsDirectory: URL?
    let onApply: (PageTemplateItem, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var applyToAllPages = false
    @State private var paperSize: PaperSize
    @State private var orientation: PageOrientation
    @State private var showsTemplateImporter = false
    @State private var pendingImport: URL?
    @State private var pendingName = ""
    @State private var showsNamePrompt = false
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 190), spacing: 16)]

    init(
        current: PageTemplate?,
        isApplying: Bool,
        currentWidth: Double? = nil,
        currentHeight: Double? = nil,
        customTemplates: CustomTemplateStore? = nil,
        assetsDirectory: URL? = nil,
        onApplySize: ((PaperSize, PageOrientation, Bool) -> Void)? = nil,
        onApply: @escaping (PageTemplateItem, Bool) -> Void
    ) {
        self.current = current
        self.isApplying = isApplying
        self.customTemplates = customTemplates
        self.assetsDirectory = assetsDirectory
        self.onApplySize = onApplySize
        self.onApply = onApply

        let matched = currentWidth.flatMap { width in
            currentHeight.flatMap { height in
                PaperSize.match(width: width, height: height)
            }
        }
        _paperSize = State(initialValue: matched?.0 ?? .a4)
        _orientation = State(initialValue: matched?.1 ?? .portrait)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let onApplySize {
                        sizeSection(onApplySize)
                        Divider()
                            .padding(.horizontal, 20)
                    }

                    ForEach(PageTemplateItem.Category.allCases) { category in
                        if category == .custom {
                            if customTemplates != nil {
                                customSection
                            }
                        } else {
                            categorySection(category)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Page Template")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showsTemplateImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                pendingImport = url
                pendingName = url.deletingPathExtension().lastPathComponent
                showsNamePrompt = true
            }
            .alert("Name Template", isPresented: $showsNamePrompt) {
                TextField("Name", text: $pendingName)
                Button("Cancel", role: .cancel) { pendingImport = nil }
                Button("Add") { addTemplate() }
            } message: {
                Text("The template appears in the Custom section. A PDF contributes its first page.")
            }
            .alert(
                "Template Could Not Be Added",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .safeAreaInset(edge: .bottom) {
                Toggle("Apply to every page in this notebook", isOn: $applyToAllPages)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
            .overlay {
                if isApplying {
                    ProgressView("Applying…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    /// Paper size and orientation for the page. Changing them moves the
    /// content with the page edges instead of redrawing it.
    private func sizeSection(
        _ onApplySize: @escaping (PaperSize, PageOrientation, Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Size")
                .font(.headline)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Paper Size", selection: $paperSize) {
                    ForEach(PaperSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.menu)

                Picker("Orientation", selection: $orientation) {
                    ForEach(PageOrientation.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Orientation")

                HStack(spacing: 12) {
                    Text(dimensionText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Apply Size") {
                        onApplySize(paperSize, orientation, applyToAllPages)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isApplying)
                }

                Text("Content keeps its position; it is not scaled.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.horizontal, 20)
        }
    }

    private func categorySection(_ category: PageTemplateItem.Category) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.rawValue)
                .font(.headline)
                .padding(.horizontal, 20)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(PageTemplateCatalog.items(in: category)) { item in
                    templateButton(item)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Imported templates, and the way in for a new one.
    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(PageTemplateItem.Category.custom.rawValue)
                    .font(.headline)
                Spacer()
                Button("Import PDF or PNG…", systemImage: "plus") {
                    showsTemplateImporter = true
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityHint("Imports a page background from a PDF or a picture")
            }
            .padding(.horizontal, 20)

            let items = customItems
            if items.isEmpty {
                Text("A planner page, a form or a picture of your own, imported once and reused on any page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        templateButton(item)
                            .contextMenu {
                                Button("Delete Template", systemImage: "trash", role: .destructive) {
                                    guard let custom = item.custom else { return }
                                    customTemplates?.remove(custom)
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var customItems: [PageTemplateItem] {
        guard let customTemplates else { return [] }
        return PageTemplateCatalog.customItems(customTemplates.templates)
    }

    /// Reads the chosen file, then names it. The store does the reading so a
    /// long PDF does not block the sheet.
    private func addTemplate() {
        guard let url = pendingImport, let customTemplates else { return }
        let name = pendingName
        pendingImport = nil
        Task {
            do {
                _ = try await customTemplates.importTemplate(from: url, name: name)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private var dimensionText: String {
        let size = paperSize.size(orientation)
        return "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
    }

    private func templateButton(_ item: PageTemplateItem) -> some View {
        Button {
            // The page draws the picture from the notebook's own assets, so it
            // has to be there before the template is applied.
            if let custom = item.custom {
                customTemplates?.install(custom, in: assetsDirectory)
            }
            onApply(item, applyToAllPages)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    if let preview = customPreview(item) {
                        Image(inkImage: preview)
                            .resizable()
                            .scaledToFit()
                    } else if let image = TemplateImageCache.preview(for: item.template) {
                        Image(inkImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Rectangle().fill(.white)
                    }

                    if isSelected(item) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(7)
                    }
                }
                .aspectRatio(PageTemplateCatalog.pageWidth / PageTemplateCatalog.pageHeight, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected(item) ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isSelected(item) ? 2.5 : 1
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(isSelected(item) ? Color.accentColor : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }

    private func customPreview(_ item: PageTemplateItem) -> InkImage? {
        guard let custom = item.custom, let customTemplates else { return nil }
        return customTemplates.preview(for: custom)
    }

    private func isSelected(_ item: PageTemplateItem) -> Bool {
        guard let current else { return false }
        return PageTemplateCatalog.sameLayout(item.template, current)
    }
}

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#Preview("Page Template") {
    PageTemplatePicker(
        current: nil,
        isApplying: false,
        currentWidth: 595,
        currentHeight: 842,
        onApplySize: { _, _, _ in }
    ) { _, _ in }
}
