import InkKit
import NoteCore
import SwiftUI

struct NotebookView: View {
    let session: NotebookSession
    @Bindable var model: AppModel

    @State private var showsDeletePageConfirmation = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var tool = InkTool(.pen)
    #if os(iOS)
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

            Menu {
                Button("Add Page After", systemImage: "plus") {
                    Task { await session.addPage() }
                }
                Menu("Paper Style", systemImage: "square.grid.3x3") {
                    ForEach(["blank", "ruled", "grid", "dotted"], id: \.self) { kind in
                        Button {
                            Task { await session.setPaperKind(kind) }
                        } label: {
                            if session.page?.template.kind == kind {
                                Label(kind.capitalized, systemImage: "checkmark")
                            } else {
                                Text(kind.capitalized)
                            }
                        }
                    }
                }
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
    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PenStyle.allCases, id: \.self) { style in
                    Button {
                        tool.style = style
                        tool.width = style.defaultWidth
                    } label: {
                        Image(systemName: style.symbolName)
                            .font(.system(size: 16))
                            .frame(width: 34, height: 30)
                            .background(
                                tool.style == style
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
                PaperBackground(template: page.template)
                PencilCanvasView(
                    strokes: page.strokes,
                    pageSize: CGSize(width: page.width, height: page.height),
                    tool: tool,
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
                PaperBackground(template: page.template)
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
        HStack(spacing: 18) {
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

            Button {
                Task { await session.addPage() }
            } label: {
                Label("Add Page", systemImage: "plus")
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// The printed part of a page: blank, ruled, grid or dotted.
struct PaperBackground: View {
    let template: PageTemplate

    var body: some View {
        Canvas { context, size in
            let paper = Color(
                red: template.paperColor.r,
                green: template.paperColor.g,
                blue: template.paperColor.b
            )
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))

            let spacing = template.spacing > 0 ? template.spacing : 24
            let line = Color(
                red: template.lineColor.r,
                green: template.lineColor.g,
                blue: template.lineColor.b
            )
            var path = Path()

            switch template.kind {
            case "ruled":
                var y = spacing
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
            case "grid":
                var x = spacing
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y = spacing
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
            case "dotted":
                var x = spacing
                while x < size.width {
                    var y = spacing
                    while y < size.height {
                        path.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                        y += spacing
                    }
                    x += spacing
                }
            default:
                break
            }

            context.stroke(path, with: .color(line.opacity(0.55)), lineWidth: 0.75)
        }
    }
}
