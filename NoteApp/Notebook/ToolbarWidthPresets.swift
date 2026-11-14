#if os(iOS)
import InkKit
import NoteCore
import SwiftUI

/// The three quick widths for the active ink tool, at the top of its settings
/// popover. Tapping a dot sets that width; touching and holding it opens the
/// slot's editor in place, below the dots.
struct ToolbarWidthPresets: View {
    @Bindable var editor: EditorToolState
    /// The slot being edited, shown as an inline slider under the dots.
    @State private var editingWidth: Int?

    var body: some View {
        let presets = editor.widthPresets
        let ranks = WidthPresets.ranks(for: presets)
        let current = editor.currentWidth
        // Only when the current width is this preset: a width set with the
        // slider away from every preset selects none of them.
        let nearestWidth = presets.indices
            .min { abs(presets[$0] - current) < abs(presets[$1] - current) }
            .map { presets[$0] }
        return VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Text("Width")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Text(PenWidth.label(current))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: AppSpacing.s) {
                ForEach(presets.indices, id: \.self) { index in
                    let width = presets[index]
                    let isSelected = nearestWidth.map { abs(width - $0) < 0.0001 } == true
                        && abs(width - current) < max(0.15, current * 0.05)
                    presetButton(index: index, width: width, rank: ranks[index], isSelected: isSelected)
                }
            }
            if let slot = editingWidth {
                editingSection(slot)
            }
        }
        .disabled(!editor.tool.drawsInk)
    }

    private func presetButton(index: Int, width: Double, rank: Int, isSelected: Bool) -> some View {
        // A dot whose size follows the preset's rank, so the three read as
        // thin, medium and thick at a glance.
        let dot = CGFloat(6 + rank * 5)
        return Button {
            editor.setWidth(width)
        } label: {
            Circle()
                .fill(isSelected ? Color.white : Color.primary)
                .frame(width: dot, height: dot)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: AppRadius.m, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PenWidth.label(width)), \(["thin", "medium", "thick"][min(index, 2)]) preset")
        .accessibilityHint("Touch and hold to edit this width")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Edit…", systemImage: "slider.horizontal.3") {
                editingWidth = index
            }
            Button("Set to Current Width", systemImage: "arrow.down.to.line") {
                editor.setWidthPreset(at: index, to: editor.currentWidth)
            }
            Button("Reset Widths", systemImage: "arrow.counterclockwise") {
                editor.resetWidthPresets()
            }
        }
    }

    private func editingSection(_ slot: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Text("Preset \(slot + 1)")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Button("Done") {
                    editingWidth = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
                .accessibilityHint("Stops editing this width preset")
            }
            WidthSlider(editor: editor, presetSlot: slot, title: "Preset \(slot + 1) width")
        }
        .padding(AppSpacing.m)
        .background(
            Color.secondary.opacity(0.1),
            in: RoundedRectangle(cornerRadius: AppRadius.m, style: .continuous)
        )
    }
}
#endif
