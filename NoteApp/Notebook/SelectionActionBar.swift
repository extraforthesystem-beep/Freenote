#if os(iOS)
import InkKit
import NoteCore
import SwiftUI

/// The actions for the lasso's selection, in a floating bar over the page.
/// Every action is one undo step; the selection stays until it is cleared or
/// the tool changes.
struct SelectionActionBar: View {
    @Binding var selection: InkSelection
    let editor: EditorToolState
    let session: NotebookSession
    let controller: PencilCanvasController

    @State private var showsColors = false
    @State private var customColor = RGBAColor.black
    @State private var canPaste = false
    /// Set while the recogniser runs, so a text action cannot be started twice.
    @State private var isWorking = false

    private var hasInk: Bool { selection.hasInk }

    /// Ink or a selected text box/sticky note to copy as text.
    private var hasTextContent: Bool {
        guard let page = session.page else { return false }
        return hasInk || selection.elements(in: page).contains { element in
            switch element.content {
            case .text, .stickyNote: true
            case .image, .shape, .pdfPage, .tape: false
            }
        }
    }

    /// What the actions may change: ink and items on unlocked layers.
    private var editableCount: Int {
        guard let page = session.page else { return 0 }
        return selection.editableStrokes(in: page).count
            + selection.editableElements(in: page).count
    }

    var body: some View {
        HStack(spacing: 0) {
            label
            Divider().frame(height: 22)
            colourButton
            widthMenu
            Divider().frame(height: 22)
            iconButton("Duplicate", "plus.square.on.square") {
                SelectionActions.duplicate(
                    selection: selection,
                    session: session,
                    controller: controller
                )
            }
            .disabled(editableCount == 0)
            iconButton("Copy", "doc.on.doc") {
                SelectionActions.copy(selection: selection, session: session)
                canPaste = SelectionActions.hasPasteboardContent()
            }
            iconButton("Paste", "doc.on.clipboard") {
                SelectionActions.paste(session: session, controller: controller)
            }
            .disabled(!canPaste)
            textMenu
            iconButton("Delete", "trash", tint: .red) {
                SelectionActions.delete(
                    selection: selection,
                    session: session,
                    controller: controller
                )
                selection.clear()
                controller.clearSelection()
            }
            .disabled(editableCount == 0)
            // Delete is destructive: keep it clear of Paste.
            .padding(.leading, AppSpacing.xs)
            if isWorking {
                ProgressView()
                    .controlSize(.mini)
                    .padding(.trailing, 8)
                    .accessibilityLabel("Recognising text")
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .frame(minHeight: 48)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .task { canPaste = SelectionActions.hasPasteboardContent() }
    }

    private var label: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "lasso")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(selection.count)")
                .font(.subheadline.monospacedDigit().weight(.medium))
        }
        .padding(.leading, AppSpacing.s)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            selection.count == 1 ? "1 item selected" : "\(selection.count) items selected"
        )
    }

    private var colourButton: some View {
        Button {
            showsColors = true
        } label: {
            iconLabel("paintpalette")
        }
        .buttonStyle(.plain)
        .disabled(editableCount == 0)
        .accessibilityLabel("Recolour selection")
        .popover(isPresented: $showsColors) {
            colourPalette
                .presentationCompactAdaptation(.popover)
        }
    }

    private var colourPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selection Colour")
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: AppSpacing.xs)],
                spacing: AppSpacing.xs
            ) {
                ForEach(Array(editor.favoriteColors.colors.enumerated()), id: \.offset) { _, color in
                    Button {
                        SelectionActions.recolour(
                            color,
                            selection: selection,
                            session: session,
                            controller: controller
                        )
                        showsColors = false
                    } label: {
                        Circle()
                            .fill(Color(color))
                            .overlay(Circle().strokeBorder(AppColor.swatchOutline, lineWidth: 1))
                            .frame(width: 30, height: 30)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(editor.colorName(for: color))
                }
            }
            ColorPicker(
                "Custom Colour",
                selection: Binding(
                    get: { Color(customColor) },
                    set: { customColor = RGBAColor($0) }
                ),
                supportsOpacity: false
            )
            .font(.subheadline)
            // The picker reports every step of a drag, so only Apply makes the
            // change: one action, one undo step.
            Button("Apply Colour") {
                SelectionActions.recolour(
                    customColor,
                    selection: selection,
                    session: session,
                    controller: controller
                )
                showsColors = false
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(editableCount == 0)
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if let first = editor.favoriteColors.colors.first { customColor = first }
        }
    }

    private var widthMenu: some View {
        Menu {
            Button("Thinner", systemImage: "minus") {
                SelectionActions.scaleWidth(
                    by: 0.7,
                    selection: selection,
                    session: session,
                    controller: controller
                )
            }
            Button("Thicker", systemImage: "plus") {
                SelectionActions.scaleWidth(
                    by: 1.4,
                    selection: selection,
                    session: session,
                    controller: controller
                )
            }
            Divider()
            ForEach(editor.widthPresets, id: \.self) { width in
                Button(PenWidth.label(width)) {
                    SelectionActions.setWidth(
                        width,
                        selection: selection,
                        session: session,
                        controller: controller
                    )
                }
            }
        } label: {
            iconLabel("lineweight")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(editableCount == 0)
        .accessibilityLabel("Change selection width")
    }

    private var textMenu: some View {
        Menu {
            Button("Copy as Text", systemImage: "textformat.abc") {
                runTextAction { await SelectionActions.copyAsText(selection: selection, session: session) }
            }
            .disabled(!hasTextContent)
            Button("Convert to Text Box", systemImage: "character.textbox") {
                runTextAction {
                    await SelectionActions.convertToTextBox(
                        selection: selection,
                        session: session,
                        controller: controller
                    )
                }
            }
            .disabled(!hasInk)
        } label: {
            iconLabel("textformat")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled((!hasTextContent && !hasInk) || isWorking)
        .accessibilityLabel("Selection text")
    }

    private func runTextAction(_ action: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }

    private func iconButton(
        _ title: String,
        _ systemImage: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconLabel(systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func iconLabel(_ systemImage: String, tint: Color? = nil) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(tint ?? .primary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
#endif
