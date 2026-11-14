#if os(iOS)
import NoteCore
import SwiftUI

/// The colour palette: 64 presets, the last colours used, a hex field and the
/// system picker for anything else. Picking a colour applies it to the active
/// ink tool and closes the popover. The colour well embeds it below the
/// favourite colours; opened from a favourite's Edit… command it replaces that
/// favourite slot instead.
struct ColorPalettePopover: View {
    @Bindable var editor: EditorToolState
    /// The favourite slot this palette replaces, when one is being edited.
    var replacingFavorite: Int? = nil
    /// True when the palette is a section of another popover, which owns the
    /// padding and the width.
    var embedded = false

    @Environment(\.dismiss) private var dismiss

    @State private var hexText = ""
    /// The text the field itself last put there. Anything else is the user's
    /// own typing, which is the only value closing the popover applies.
    @State private var hexBaseline = ""
    @State private var hexIsInvalid = false
    @FocusState private var isHexFocused: Bool

    private let swatchSize: CGFloat = 34
    /// Tight enough that eight preset columns still fit the 320 pt popover.
    private let swatchSpacing: CGFloat = AppSpacing.xxs
    /// Optical inset of the hex field's border: it hugs the text, not the row.
    private static let hexBorderInset = EdgeInsets(top: -5, leading: -6, bottom: -5, trailing: -6)

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(swatchSize), spacing: swatchSpacing),
            count: ColorPalette.columnCount
        )
    }

    private var toolName: String {
        editor.activeInkTool == .highlighter ? "Highlighter" : "Pen"
    }

    /// The slot being edited, or nil when the palette sets the ink colour.
    private var favoriteIndex: Int? {
        guard let index = replacingFavorite,
              editor.favoriteColors.colors.indices.contains(index)
        else { return nil }
        return index
    }

    /// The colour the header shows and the grid rings: the favourite being
    /// edited, otherwise the ink colour.
    private var shownColor: RGBAColor {
        guard let index = favoriteIndex else { return editor.inkTool.color }
        return editor.favoriteColors.colors[index]
    }

    private func isShown(_ color: RGBAColor) -> Bool {
        guard favoriteIndex != nil else {
            return editor.tool.drawsInk && editor.isCurrentColor(color)
        }
        let shown = shownColor
        return abs(shown.r - color.r) < 0.01
            && abs(shown.g - color.g) < 0.01
            && abs(shown.b - color.b) < 0.01
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !editor.recentColors.colors.isEmpty {
                recentRow
            }
            presetGrid
            hexRow
            systemPicker
        }
        .padding(embedded ? 0 : AppSpacing.l)
        .frame(width: embedded ? nil : 320)
        .onAppear {
            showHex(of: shownColor)
        }
        .onDisappear {
            // Closed without submitting: a value the user typed still counts.
            applyTypedHexOnClose()
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(favoriteIndex == nil ? "Colour" : "Edit Favourite")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(Color(shownColor))
                .overlay(Circle().strokeBorder(AppColor.swatchOutline, lineWidth: 1))
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        }
    }

    private var subtitle: String {
        guard let index = favoriteIndex else {
            return "\(toolName), \(editor.colorName(for: shownColor))"
        }
        return "\(toolName) favourite \(index + 1), \(editor.colorName(for: shownColor))"
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: AppSpacing.xs) {
                ForEach(Array(editor.recentColors.colors.enumerated()), id: \.offset) { index, color in
                    Button {
                        apply(color)
                    } label: {
                        Circle()
                            .fill(Color(color))
                            .overlay(Circle().strokeBorder(AppColor.swatchOutline, lineWidth: 1))
                            .frame(width: 26, height: 26)
                            .frame(width: 30, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recent \(editor.colorName(for: color)), \(index + 1)")
                    .accessibilityAddTraits(isShown(color) ? .isSelected : [])
                }
            }
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: columns, spacing: swatchSpacing) {
            ForEach(ColorPalette.presets, id: \.self) { color in
                let isSelected = isShown(color)
                Button {
                    apply(color)
                } label: {
                    Circle()
                        .fill(Color(color))
                        .overlay(Circle().strokeBorder(AppColor.swatchOutline, lineWidth: 1))
                        .overlay {
                            Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                        }
                        .frame(width: swatchSize, height: swatchSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(editor.colorName(for: color))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var hexRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Hex")
                    .font(.subheadline)
                TextField("#RRGGBB", text: $hexText)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isHexFocused)
                    .submitLabel(.done)
                    .onChange(of: hexText) { _, newValue in
                        // Only the marker follows the typing: applying every
                        // intermediate value would record half-typed junk.
                        updateHexValidity(newValue)
                    }
                    .onSubmit {
                        applyTypedHex()
                        isHexFocused = false
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.s, style: .continuous)
                            .strokeBorder(hexIsInvalid ? Color.red : Color.secondary.opacity(0.3), lineWidth: 1)
                            .padding(Self.hexBorderInset)
                    }
                    .accessibilityLabel("Hex colour, hash R R G B B")
            }
            if hexIsInvalid {
                Text("Use #RRGGBB, for example #1E90FF.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// The system picker covers everything the grid cannot: exact matches to
    /// an imported style, eyedropper, and so on.
    private var systemPicker: some View {
        ColorPicker(
            "Custom Colour",
            selection: Binding(
                get: { Color(shownColor) },
                set: { color in
                    let updated = RGBAColor(color)
                    select(updated)
                    showHex(of: updated)
                }
            ),
            supportsOpacity: false
        )
        .font(.subheadline)
    }

    private func apply(_ color: RGBAColor) {
        select(color)
        dismissPopover()
    }

    /// Puts a colour in the field as its own baseline, so closing the popover
    /// does not read it back as something the user typed.
    private func showHex(of color: RGBAColor) {
        hexText = ColorHex.string(from: color)
        hexBaseline = hexText
        hexIsInvalid = false
    }

    /// A favourite slot is replaced in place; otherwise the ink colour changes.
    private func select(_ color: RGBAColor) {
        if let index = favoriteIndex {
            editor.replaceFavoriteColor(at: index, with: color)
        } else {
            editor.setColor(color)
        }
    }

    /// Applies the typed value: once when the field is submitted, and once when
    /// the popover closes on a value that was never submitted.
    private func applyTypedHex() {
        guard let color = ColorHex.color(from: hexText) else {
            updateHexValidity(hexText)
            return
        }
        showHex(of: color)
        if !isShown(color) {
            select(color)
        }
    }

    /// A value typed but never submitted, applied as the popover closes.
    private func applyTypedHexOnClose() {
        guard hexText != hexBaseline, let color = ColorHex.color(from: hexText) else { return }
        select(color)
    }

    /// Keeps the invalid marker live while typing. Nothing else changes until
    /// the value is submitted or the popover closes.
    private func updateHexValidity(_ text: String) {
        guard ColorHex.color(from: text) == nil else {
            hexIsInvalid = false
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        hexIsInvalid = !trimmed.isEmpty && (trimmed.count > 6 || !trimmed.allSatisfy(\.isHexDigit))
    }

    private func dismissPopover() {
        isHexFocused = false
        dismiss()
    }
}
#endif
