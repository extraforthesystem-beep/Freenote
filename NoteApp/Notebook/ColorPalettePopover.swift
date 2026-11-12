#if os(iOS)
import NoteCore
import SwiftUI

/// The colour palette: 64 presets, the last colours used, a hex field and the
/// system picker for anything else. Picking a colour applies it to the active
/// ink tool and closes the popover.
struct ColorPalettePopover: View {
    @Bindable var editor: EditorToolState
    @Environment(\.dismiss) private var dismiss

    @State private var hexText = ""
    @State private var hexIsInvalid = false
    @FocusState private var isHexFocused: Bool

    private let swatchSize: CGFloat = 34
    private let swatchSpacing: CGFloat = 4

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(swatchSize), spacing: swatchSpacing),
            count: ColorPalette.columnCount
        )
    }

    private var toolName: String {
        editor.activeInkTool == .highlighter ? "Highlighter" : "Pen"
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
        .padding(16)
        .frame(width: 340)
        .onAppear {
            hexText = ColorHex.string(from: editor.inkTool.color)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Colour")
                    .font(.headline)
                Text("\(toolName), \(editor.colorName(for: editor.inkTool.color))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(Color(editor.inkTool.color))
                .overlay(Circle().strokeBorder(AppColor.swatchOutline, lineWidth: 1))
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        }
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
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
                    .accessibilityAddTraits(editor.isCurrentColor(color) && editor.tool.drawsInk ? .isSelected : [])
                }
            }
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: columns, spacing: swatchSpacing) {
            ForEach(ColorPalette.presets, id: \.self) { color in
                let isSelected = editor.tool.drawsInk && editor.isCurrentColor(color)
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
                        applyHex(newValue)
                    }
                    .onSubmit {
                        if ColorHex.color(from: hexText) == nil {
                            hexText = ColorHex.string(from: editor.inkTool.color)
                            hexIsInvalid = false
                        }
                        isHexFocused = false
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(hexIsInvalid ? Color.red : Color.secondary.opacity(0.3), lineWidth: 1)
                            .padding(.horizontal, -6)
                            .padding(.vertical, -5)
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
                get: { Color(editor.inkTool.color) },
                set: { color in
                    editor.setColor(RGBAColor(color))
                    hexText = ColorHex.string(from: editor.inkTool.color)
                    hexIsInvalid = false
                }
            ),
            supportsOpacity: false
        )
        .font(.subheadline)
    }

    private func apply(_ color: RGBAColor) {
        editor.setColor(color)
        dismissPopover()
    }

    private func applyHex(_ text: String) {
        guard let color = ColorHex.color(from: text) else {
            // Still typing: only flag text that cannot become a colour.
            let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
            hexIsInvalid = !trimmed.isEmpty && (trimmed.count > 6 || !trimmed.allSatisfy(\.isHexDigit))
            return
        }
        hexIsInvalid = false
        editor.setColor(color)
    }

    private func dismissPopover() {
        isHexFocused = false
        dismiss()
    }
}
#endif
