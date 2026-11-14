#if os(iOS)
import InkKit
import NoteCore
import SwiftUI
import UniformTypeIdentifiers

/// The colour well's popover: the active ink tool's favourite colours, then
/// the full palette. It replaces the old always-visible row of swatches and the
/// separate palette button, so the bar carries one colour control.
struct ToolbarColorPopover: View {
    @Bindable var editor: EditorToolState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The favourite slot the palette is replacing, when one is being edited.
    @State private var editingFavorite: Int?
    /// The favourite a dragged colour is hovering over, for the drop ring.
    @State private var dropTarget: Int?

    /// Eight fixed columns: the full set of favourites fits one row, and the
    /// grid wraps only when the add slot makes a ninth item.
    private let columns = Array(
        repeating: GridItem(.fixed(34), spacing: AppSpacing.xxs),
        count: 8
    )

    private var favorites: ColorFavorites {
        editor.favoriteColors
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                favoritesSection
                Divider()
                ColorPalettePopover(editor: editor, replacingFavorite: editingFavorite, embedded: true)
            }
            .padding(AppSpacing.l)
        }
        .frame(width: 320)
        .frame(maxHeight: 620)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            favoritesHeader
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.xxs) {
                ForEach(favorites.colors.indices, id: \.self) { index in
                    favoriteSwatch(favorites.colors[index], index: index)
                        .id(index)
                }
                if !favorites.isFull {
                    addFavoriteSlot
                }
            }
        }
    }

    private var favoritesHeader: some View {
        HStack(spacing: AppSpacing.s) {
            Text(headerTitle)
                .font(.caption)
                .foregroundStyle(editingFavorite == nil ? Color.secondary : Color.accentColor)
            Spacer(minLength: 0)
            if editingFavorite != nil {
                Button("Done") {
                    editingFavorite = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
                .accessibilityHint("Stops replacing the favourite's colour")
            }
        }
    }

    private var headerTitle: String {
        guard let index = editingFavorite else { return "Favourites" }
        return "Editing favourite \(index + 1)"
    }

    private func favoriteSwatch(_ color: RGBAColor, index: Int) -> some View {
        let isCurrent = editor.tool.drawsInk && editor.isCurrentColor(color)
        let isSelected = isCurrent || editingFavorite == index
        let isDropTarget = dropTarget == index
        return Button {
            editor.setColor(color)
        } label: {
            Circle()
                .fill(Color(color))
                .overlay(Circle().strokeBorder(AppColor.swatchOutline, lineWidth: 1))
                .frame(width: 26, height: 26)
                .overlay {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                        .frame(width: 26, height: 26)
                }
                .overlay {
                    if isDropTarget {
                        Circle()
                            .strokeBorder(
                                Color.accentColor.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, dash: [3, 2])
                            )
                            .frame(width: 26, height: 26)
                    }
                }
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit…", systemImage: "slider.horizontal.3") {
                editingFavorite = index
            }
            Button("Replace with Current Colour", systemImage: "arrow.triangle.2.circlepath") {
                editor.replaceFavoriteColor(at: index, with: editor.inkTool.color)
            }
            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                editor.removeFavoriteColor(at: index)
            }
        }
        .draggable(FavoriteColorSlot(index: index)) {
            Circle()
                .fill(Color(color))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: 34, height: 34)
        }
        .dropDestination(for: FavoriteColorSlot.self) { slots, _ in
            guard let source = slots.first?.index, source != index else { return false }
            dropTarget = nil
            AppMotion.animate(AppMotion.quick, reduceMotion: reduceMotion) {
                editor.moveFavoriteColor(from: source, to: index)
            }
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTarget = index
            } else if dropTarget == index {
                dropTarget = nil
            }
        }
        .accessibilityLabel("\(editor.colorName(for: color)), favourite \(index + 1)")
        .accessibilityHint(
            "Double-tap to use this colour. Touch and hold to edit, replace or remove it, "
                + "or drag it onto another favourite to move it."
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Move Left") {
            editor.moveFavoriteColor(from: index, to: index - 1)
        }
        .accessibilityAction(named: "Move Right") {
            editor.moveFavoriteColor(from: index, to: index + 1)
        }
    }

    /// Shown while a favourite slot is free: adds the current colour back.
    private var addFavoriteSlot: some View {
        Button {
            editor.addFavoriteColor(editor.inkTool.color)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background {
                    Circle().strokeBorder(
                        Color.secondary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                }
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(editor.colorName(for: editor.inkTool.color)) to favourites")
        .help("Add the current colour to the favourites")
    }
}

/// A favourite colour's slot in the toolbar, carried while its swatch is
/// dragged. In-app only, so the type is never handed to another app.
nonisolated private struct FavoriteColorSlot: Codable, Transferable {
    var index: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .noteAppFavoriteColorSlot)
    }
}

nonisolated private extension UTType {
    static var noteAppFavoriteColorSlot: UTType {
        UTType(exportedAs: "com.noteapp.favorite-color-slot")
    }
}
#endif
