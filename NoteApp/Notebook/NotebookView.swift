import InkKit
import NoteCore
import SwiftUI

struct NotebookView: View {
    let session: NotebookSession
    @Bindable var model: AppModel

    @State private var showsDeletePageConfirmation = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var exportDocument: PDFExportDocument?
    @State private var isExporting = false
    @State private var showExporter = false
    @State private var exportError: String?
    @State private var showsTemplatePicker = false
    @State private var tool = InkTool(.pen)
    #if os(iOS)
    @State private var canvasMode: CanvasMode = .ink
    @State private var controller = PencilCanvasController()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            #if os(iOS)
            toolBar
            Divider()
            #endif
            pageArea
            Divider()
            footer
        }
        .background(AppColor.groupedBackground)
        .alert("Delete this page?", isPresented: $showsDeletePageConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await session.deleteCurrentPage() }
            }
        }
        .alert("Rename notebook", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task {
                    let manifest = session.manifest
                    await model.rename(manifest, to: renameText)
                    await session.reloadManifest()
                }
            }
        }
        .alert(
            "Export failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsTemplatePicker) {
            PageTemplatePicker(
                current: session.page?.template,
                isApplying: session.isApplyingTemplate
            ) { item, applyToAll in
                Task { await session.applyTemplate(item.template, toAllPages: applyToAll) }
            }
        }
    }

    private var exportFilename: String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let cleaned = session.manifest.title.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Notebook" : name
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.closeNotebook()
            } label: {
                Label("Library", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.manifest.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("Page \(session.currentPageNumber) of \(max(session.pageCount, 1))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .help("Saving")
            }

            Button {
                renameText = session.manifest.title
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Button {
                showsTemplatePicker = true
            } label: {
                Label("Page Template", systemImage: "square.grid.3x3")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Page template")

            Menu {
                Button("Add Page After", systemImage: "plus") {
                    Task { await session.addPage() }
                }
                Button("Export PDF", systemImage: "square.and.arrow.up") {
                    Task {
                        isExporting = true
                        defer { isExporting = false }
                        do {
                            let data = try await NotebookExporter.pdfData(session: session)
                            exportDocument = PDFExportDocument(data: data)
                            showExporter = true
                        } catch {
                            exportError = error.localizedDescription
                        }
                    }
                }
                .disabled(session.pageCount == 0 || isExporting)
                Divider()
                Button("Duplicate Page", systemImage: "plus.square.on.square") {
                    Task { await session.duplicateCurrentPage() }
                }
                .disabled(session.page == nil)
                Button("Move Page Left", systemImage: "arrow.left") {
                    Task { await session.moveCurrentPage(by: -1) }
                }
                .disabled(session.pageIndex == 0)
                Button("Move Page Right", systemImage: "arrow.right") {
                    Task { await session.moveCurrentPage(by: 1) }
                }
                .disabled(session.pageIndex + 1 >= session.pageCount)
                Divider()
                Button("Page Template…", systemImage: "square.grid.3x3") {
                    showsTemplatePicker = true
                }
                .disabled(session.page == nil)
                Divider()
                Button("Delete Page", systemImage: "trash", role: .destructive) {
                    showsDeletePageConfirmation = true
                }
                .disabled(session.page == nil)
            } label: {
                Label("Page Actions", systemImage: "ellipsis.circle")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    #if os(iOS)
    private var isErasing: Bool {
        if case .eraser = canvasMode { return true }
        return false
    }

    private var isLasso: Bool {
        if case .lasso = canvasMode { return true }
        return false
    }

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PenStyle.allCases, id: \.self) { style in
                    Button {
                        tool.style = style
                        tool.width = style.defaultWidth
                        canvasMode = .ink
                    } label: {
                        Image(systemName: style.symbolName)
                            .font(.system(size: 16))
                            .frame(width: 34, height: 30)
                            .background(
                                canvasMode == .ink && tool.style == style
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.displayName)
                    .help(style.displayName)
                }

                Divider().frame(height: 22)

                ColorPicker(
                    "Ink colour",
                    selection: Binding(
                        get: { Color(tool.color) },
                        set: { tool.color = RGBAColor($0) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()

                Slider(
                    value: Binding(
                        get: { tool.width },
                        set: { tool.width = $0 }
                    ),
                    in: 1...40
                )
                .frame(width: 110)
                .accessibilityLabel("Ink width")

                Divider().frame(height: 22)

                Menu {
                    Button("Stroke Eraser", systemImage: "eraser") {
                        canvasMode = .eraser(.stroke, width: 12)
                    }
                    Button("Pixel Eraser", systemImage: "eraser.fill") {
                        canvasMode = .eraser(.pixel, width: 12)
                    }
                } label: {
                    Image(systemName: "eraser")
                        .font(.system(size: 16))
                        .frame(width: 34, height: 30)
                        .background(
                            isErasing ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Eraser")

                Button {
                    canvasMode = canvasMode == .lasso ? .ink : .lasso
                } label: {
                    Image(systemName: "lasso")
                        .font(.system(size: 16))
                        .frame(width: 34, height: 30)
                        .background(
                            isLasso ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lasso")

                Divider().frame(height: 22)

                Button {
                    controller.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .disabled(!controller.canUndo)
                .accessibilityLabel("Undo")

                Button {
                    controller.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.plain)
                .disabled(!controller.canRedo)
                .accessibilityLabel("Redo")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
    #endif

    private var pageArea: some View {
        GeometryReader { proxy in
            let pageWidth = session.page?.width ?? PageDefaults.width
            let pageHeight = session.page?.height ?? PageDefaults.height
            let aspect = pageWidth / pageHeight
            let availableWidth = max(proxy.size.width - 64, 200)
            let availableHeight = max(proxy.size.height - 64, 200)
            let fittedWidth = min(availableWidth, availableHeight * aspect, 820)
            let fittedHeight = fittedWidth / aspect

            pageSurface
                .frame(width: fittedWidth, height: fittedHeight)
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var pageSurface: some View {
        if let page = session.page {
            #if os(iOS)
            ZStack {
                PaperBackground(template: page.template, pageSize: CGSize(width: page.width, height: page.height))
                PencilCanvasView(
                    strokes: page.strokes,
                    pageSize: CGSize(width: page.width, height: page.height),
                    tool: tool,
                    mode: canvasMode,
                    activeLayerID: page.layers.first?.id ?? UUID(),
                    isEditable: true,
                    controller: controller,
                    onStrokesChanged: { session.strokesChanged($0) }
                )
                .id(page.id)
            }
            #else
            if let image = PageRenderer.image(
                strokes: page.strokes,
                pageSize: CGSize(width: page.width, height: page.height),
                template: page.template
            ) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                PaperBackground(template: page.template, pageSize: CGSize(width: page.width, height: page.height))
            }
            #endif
        } else if session.isLoadingPage {
            ProgressView()
        } else if session.pageCount == 0 {
            VStack(spacing: 14) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("This notebook has no pages")
                    .font(.headline)
                Button("Add the First Page") {
                    Task { await session.addPage(after: false) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
        } else {
            ContentUnavailableView {
                Label("Page unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(session.loadError ?? "The page file could not be read.")
            }
            .background(.white)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            PageThumbnailStrip(session: session) { index in
                Task { await session.goToPage(index) }
            }

            HStack(spacing: 14) {
                Button {
                    Task { await session.goToPreviousPage() }
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(session.pageIndex == 0)

                Menu {
                    ForEach(0..<max(session.pageCount, 1), id: \.self) { index in
                        Button {
                            Task { await session.goToPage(index) }
                        } label: {
                            if index == session.pageIndex {
                                Label("Page \(index + 1)", systemImage: "checkmark")
                            } else {
                                Text("Page \(index + 1)")
                            }
                        }
                    }
                } label: {
                    Text("\(session.currentPageNumber) of \(max(session.pageCount, 1))")
                        .font(.subheadline.monospacedDigit())
                        .frame(minWidth: 70)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    Task { await session.goToNextPage() }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(session.pageIndex + 1 >= session.pageCount)

                Spacer()

                if session.isSaving {
                    ProgressView()
                        .controlSize(.mini)
                }

                Button {
                    Task { await session.addPage() }
                } label: {
                    Label("Add Page", systemImage: "plus")
                }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

/// The printed part of a page, drawn by InkKit so the canvas, thumbnails and PDF agree.
struct PaperBackground: View {
    let template: PageTemplate
    var pageSize: CGSize = PageTemplateCatalog.pageSize

    var body: some View {
        if let image = TemplateImageCache.image(for: template, pageSize: pageSize) {
            Image(inkImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Color.white
        }
    }
}
