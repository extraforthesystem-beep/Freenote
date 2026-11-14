import NoteCore
import SearchKit
import SwiftUI

/// What a page should mark for a search: the query, the sources it searched and
/// the edit-date window, so the panel can adopt the same search.
struct SearchHighlight: Hashable {
    var query: String
    var sources: Set<PageTextSource> = Set(PageTextSource.allCases)
    var dateRange: SearchDateRange = .anyTime
}

/// Source checkboxes and an edit-date choice for a search. Turning every source
/// off is not allowed, so a filter always has something to search.
struct SearchFilterMenu: View {
    @Binding var sources: Set<PageTextSource>
    @Binding var dateRange: SearchDateRange

    var body: some View {
        Menu {
            Section("Search In") {
                ForEach(PageTextSource.allCases, id: \.self) { source in
                    Toggle(source.sectionTitle, isOn: binding(for: source))
                }
            }
            Picker("Last Edited", selection: $dateRange) {
                ForEach(SearchDateRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.menu)
            Divider()
            Text("Use \"exact phrase\", OR, and -word to refine.")
        } label: {
            Label("Filter", systemImage: isFiltered
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Search filters")
    }

    private var isFiltered: Bool {
        sources.count < PageTextSource.allCases.count || dateRange != .anyTime
    }

    private func binding(for source: PageTextSource) -> Binding<Bool> {
        Binding(
            get: { sources.contains(source) },
            set: { isOn in
                if isOn {
                    sources.insert(source)
                } else if sources.count > 1 {
                    sources.remove(source)
                }
            }
        )
    }
}

#if os(iOS)
import PencilKit
import UIKit

/// A small writing pad: what is written with Apple Pencil becomes the search query.
/// Recognition is Apple's on-device `PKStrokeRecognizer`; it runs after each pause.
struct PencilSearchPad: View {
    let search: HandwritingSearch
    /// Called with the recognised text after every pause in writing.
    let onQuery: (String) -> Void

    @State private var drawing = PKDrawing()
    @State private var recognized = ""
    @State private var recognizeTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Text("Write to Search")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    drawing = PKDrawing()
                    recognized = ""
                    onQuery("")
                }
                .disabled(drawing.strokes.isEmpty)
                Button("Done") { dismiss() }
                    .bold()
            }

            SearchInkCanvas(drawing: $drawing)
                .frame(height: 140)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if drawing.strokes.isEmpty {
                        Text("Write a word with Apple Pencil")
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: AppSpacing.s) {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(recognized.isEmpty ? "Recognised text appears here" : recognized)
                    .foregroundStyle(recognized.isEmpty ? .tertiary : .primary)
                    .lineLimit(2)
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 380)
        .onChange(of: drawing) { _, value in
            scheduleRecognition(value)
        }
        .onDisappear { recognizeTask?.cancel() }
    }

    private func scheduleRecognition(_ value: PKDrawing) {
        recognizeTask?.cancel()
        guard !value.strokes.isEmpty else { return }
        recognizeTask = Task {
            // Wait for a pause so a half-written word is not searched.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let text = await search.recognizeQuery(in: value) ?? ""
            guard !Task.isCancelled else { return }
            recognized = text
            onQuery(text)
        }
    }
}

/// A plain PencilKit canvas with a pen; a finger draws too, so it works without a Pencil.
private struct SearchInkCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}

/// Opens the writing pad as a popover.
struct PencilSearchButton: View {
    let search: HandwritingSearch
    let onQuery: (String) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Write to Search", systemImage: "applepencil.and.scribble")
        }
        .popover(isPresented: $isPresented) {
            PencilSearchPad(search: search, onQuery: onQuery)
                .presentationCompactAdaptation(.popover)
        }
    }
}
#endif

/// Marks a search's matches on the page: handwriting found by Apple's ink search
/// (so a word is found even where the stored text misread it), typed text boxes,
/// and words in the page's PDF.
/// It never takes touches, so the Pencil writes straight through it.
struct SearchHighlightOverlay: View {
    let highlight: SearchHighlight
    let page: Page
    let strokes: [StrokeRecord]
    let assetsDirectory: URL?
    let search: HandwritingSearch

    @State private var marks: [PageMatchMark] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                let padded = mark.rect.insetBy(dx: -4, dy: -3)
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .fill(AppColor.searchHitFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                            .stroke(AppColor.searchHitStroke, lineWidth: 1.5)
                    )
                    .frame(width: padded.width, height: padded.height)
                    .rotationEffect(.degrees(mark.rotation))
                    .offset(x: padded.minX, y: padded.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: taskKey) {
            // Each stroke restarts this task; recognise only once writing pauses.
            if !marks.isEmpty {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
            }
            let found = await search.pageMarks(for: highlight, page: page, strokes: strokes, assetsDirectory: assetsDirectory)
            // A page flip cancels this pass; its marks belong to the old page.
            guard !Task.isCancelled else { return }
            marks = found
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var taskKey: SearchMarksKey {
        SearchMarksKey(
            highlight: highlight,
            pageID: page.id,
            strokeCount: strokes.count,
            lastStrokeID: strokes.last?.id,
            elements: page.visibleElements.map { "\($0.id)\($0.updatedAt.timeIntervalSince1970)" }
        )
    }
}

/// What the highlight overlay's task depends on. The ink is described by its
/// length and last stroke, not by every id: adding or erasing a stroke changes
/// that, while copying and hashing thousands of ids on every pass of the page's
/// body does not have to happen at all.
struct SearchMarksKey: Hashable {
    var highlight: SearchHighlight
    var pageID: UUID
    var strokeCount: Int
    var lastStrokeID: UUID?
    var elements: [String]
}
