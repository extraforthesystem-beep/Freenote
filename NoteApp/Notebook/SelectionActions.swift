#if os(iOS)
import Foundation
import InkKit
import NoteCore
import PencilKit
import UIKit

/// The actions a lasso selection offers. Each action is one page edit and one
/// undo step on the canvas's stack, next to the ink changes.
@MainActor
enum SelectionActions {
    /// The pasteboard type a copied selection travels under. It is the app's
    /// own type, so a copy in another app never replaces it.
    static let pasteboardType = "local.noteapp.ink-selection"

    // MARK: - Ink and items

    static func recolour(
        _ color: RGBAColor,
        selection: InkSelection,
        session: NotebookSession,
        controller: PencilCanvasController
    ) {
        perform(
            selection: selection,
            name: "Recolour",
            failure: "The selection could not be recoloured.",
            session: session,
            controller: controller
        ) { SelectionEdit.recolour(selection, in: $0, to: color) }
    }

    static func scaleWidth(
        by factor: Double,
        selection: InkSelection,
        session: NotebookSession,
        controller: PencilCanvasController
    ) {
        perform(
            selection: selection,
            name: "Change Width",
            failure: "The selection's width could not be changed.",
            session: session,
            controller: controller
        ) { SelectionEdit.scaleWidth(selection, in: $0, by: factor) }
    }

    static func setWidth(
        _ width: Double,
        selection: InkSelection,
        session: NotebookSession,
        controller: PencilCanvasController
    ) {
        perform(
            selection: selection,
            name: "Change Width",
            failure: "The selection's width could not be changed.",
            session: session,
            controller: controller
        ) { SelectionEdit.setWidth(selection, in: $0, to: width) }
    }

    static func duplicate(
        selection: InkSelection,
        session: NotebookSession,
        controller: PencilCanvasController
    ) {
        perform(
            selection: selection,
            name: "Duplicate",
            failure: "The selection could not be duplicated.",
            session: session,
            controller: controller
        ) { SelectionEdit.duplicate(selection, in: $0) }
    }

    static func delete(
        selection: InkSelection,
        session: NotebookSession,
        controller: PencilCanvasController
    ) {
        perform(
            selection: selection,
            name: "Delete",
            failure: "The selection could not be deleted.",
            session: session,
            controller: controller
        ) { SelectionEdit.delete(selection, from: $0) }
    }

    // MARK: - Copy and paste

    static func copy(selection: InkSelection, session: NotebookSession) {
        guard let page = session.page else { return }
        let payload = SelectionEdit.copied(selection, from: page)
        guard !payload.isEmpty, let data = try? JSONEncoder().encode(payload) else { return }
        UIPasteboard.general.setData(data, forPasteboardType: pasteboardType)
    }

    static func hasPasteboardContent() -> Bool {
        UIPasteboard.general.data(forPasteboardType: pasteboardType) != nil
    }

    /// Pastes into the page on screen, so a copy taken in one notebook lands in
    /// another. The layer is the active one.
    static func paste(
        session: NotebookSession,
        controller: PencilCanvasController
    ) {
        guard let data = UIPasteboard.general.data(forPasteboardType: pasteboardType),
              let payload = try? JSONDecoder().decode(SelectionPayload.self, from: data),
              let page = session.page
        else { return }
        let layerID = session.activeLayerID ?? page.layers.first?.id ?? UUID()
        let updated = SelectionEdit.paste(payload, into: page, layerID: layerID)
        apply(
            before: page,
            after: updated,
            name: "Paste",
            failure: "The selection could not be pasted.",
            session: session,
            controller: controller
        )
    }

    // MARK: - Text

    /// The recognised text of the selected ink, or of a selected text box or
    /// sticky note. Uses Apple's recogniser on the selected strokes only.
    static func recognizedText(for selection: InkSelection, in page: Page) async -> String? {
        var parts: [String] = []
        if let ink = await recognizedInk(selection, in: page) {
            parts.append(ink)
        }
        for element in selection.elements(in: page) {
            switch element.content {
            case let .text(text, _, _, _), let .stickyNote(text, _):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
            case .image, .shape, .pdfPage, .tape:
                continue
            }
        }
        let joined = parts.joined(separator: "\n\n")
        return joined.isEmpty ? nil : joined
    }

    static func copyAsText(selection: InkSelection, session: NotebookSession) async {
        guard let page = session.page,
              let text = await recognizedText(for: selection, in: page)
        else { return }
        UIPasteboard.general.string = text
    }

    static func convertToTextBox(
        selection: InkSelection,
        session: NotebookSession,
        controller: PencilCanvasController
    ) async {
        guard let page = session.page,
              let text = await recognizedText(for: selection, in: page)
        else { return }
        let layerID = session.activeLayerID ?? page.layers.first?.id ?? UUID()
        guard let updated = SelectionEdit.textBox(
            for: text,
            selection: selection,
            in: page,
            layerID: layerID
        ) else { return }
        apply(
            before: page,
            after: updated,
            name: "Convert to Text",
            failure: "The text box could not be added.",
            session: session,
            controller: controller
        )
    }

    private static func recognizedInk(_ selection: InkSelection, in page: Page) async -> String? {
        let records = selection.strokes(in: page)
        guard !records.isEmpty else { return nil }
        let drawing = PKDrawing(strokes: records.compactMap { try? StrokeCodec.stroke(from: $0) })
        guard !drawing.strokes.isEmpty else { return nil }

        let recognizer = PKStrokeRecognizer(preferredLanguages: nil)
        await recognizer.updateDrawing(drawing)
        let text = await recognizer.recognizedText(strokeIDs: Set(drawing.strokes.map(\.id)))
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    // MARK: - One edit, one undo step

    private static func perform(
        selection: InkSelection,
        name: String,
        failure: String,
        session: NotebookSession,
        controller: PencilCanvasController,
        change: (Page) -> Page
    ) {
        guard let page = session.page else { return }
        apply(
            before: page,
            after: change(page),
            name: name,
            failure: failure,
            session: session,
            controller: controller
        )
    }

    private static func apply(
        before: Page,
        after: Page,
        name: String,
        failure: String,
        session: NotebookSession,
        controller: PencilCanvasController
    ) {
        guard before != after else { return }
        // Undo puts the whole page's ink and items back, so it also covers a
        // delete or a paste that added several things at once.
        controller.registerUndo(name: name) { [weak session] in
            guard let session, session.page?.id == before.id else { return }
            Task {
                await session.applySelectionEdit(
                    strokes: before.strokes,
                    elements: before.elements,
                    failure: "The last change could not be undone."
                )
            }
        }
        Task {
            await session.applySelectionEdit(
                strokes: after.strokes,
                elements: after.elements,
                failure: failure
            )
        }
    }
}
#endif
