import Foundation
import InkKit
import NoteCore
import Observation
#if os(iOS)
import SwiftUI
#endif

/// One saved pen: style, colour and width, recalled in a single tap.
struct FavoritePen: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var style: PenStyle
    var color: RGBAColor
    var width: Double

    init(id: UUID = UUID(), style: PenStyle, color: RGBAColor, width: Double) {
        self.id = id
        self.style = style
        self.color = color
        self.width = width
    }

    /// Same pen, whatever the saved id.
    func matches(_ other: FavoritePen) -> Bool {
        style == other.style
            && abs(color.r - other.color.r) < 0.01
            && abs(color.g - other.color.g) < 0.01
            && abs(color.b - other.color.b) < 0.01
            && abs(width - other.width) < 0.5
    }
}

/// The saved pens, newest first, capped at six and stored as JSON.
@MainActor
@Observable
final class FavoritePens {
    static let capacity = 6
    static let defaultsKey = "noteapp.editor.favoritePens.v1"

    private(set) var pens: [FavoritePen]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([FavoritePen].self, from: data) {
            pens = Array(stored.prefix(Self.capacity))
        } else {
            pens = []
        }
    }

    var isFull: Bool { pens.count >= Self.capacity }

    func contains(_ pen: FavoritePen) -> Bool {
        pens.contains { $0.matches(pen) }
    }

    /// Adds to the front. A saved pen that matches moves to the front instead
    /// of being stored twice; a full list rejects the new pen.
    @discardableResult
    func add(_ pen: FavoritePen) -> Bool {
        if contains(pen) {
            pens.removeAll { $0.matches(pen) }
            pens.insert(pen, at: 0)
            save()
            return false
        }
        guard !isFull else { return false }
        pens.insert(pen, at: 0)
        save()
        return true
    }

    func remove(id: UUID) {
        pens.removeAll { $0.id == id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        pens.remove(atOffsets: offsets)
        save()
    }

    /// Writes to `UserDefaults` at once: the list only changes on a tap.
    func save() {
        guard let data = try? JSONEncoder().encode(pens) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

extension EditorToolState {
    /// The pen as it stands now, for saving as a favourite.
    var currentPen: FavoritePen {
        FavoritePen(style: penStyle, color: penTool.color, width: penTool.width)
    }

    var isCurrentPenSaved: Bool {
        favoritePens.contains(currentPen)
    }

    /// Saves the current pen; does nothing when the list is full.
    @discardableResult
    func saveCurrentPen() -> Bool {
        favoritePens.add(currentPen)
    }

    /// Recalls a saved pen: style, colour, width, and back to the pen tool.
    func recallPen(_ pen: FavoritePen) {
        selectPenStyle(pen.style)
        setColor(pen.color)
        setWidth(pen.width)
    }
}

#if os(iOS)
/// The saved-pen list: tap to recall, swipe or touch and hold to delete.
struct FavoritePensPopover: View {
    @Bindable var editor: EditorToolState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Favourite Pens")
                .font(.headline)
            if editor.favoritePens.pens.isEmpty {
                emptyState
            } else {
                penList
            }
            Divider()
            Button {
                editor.saveCurrentPen()
            } label: {
                Label("Add Current Pen", systemImage: "plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(editor.favoritePens.isFull || editor.isCurrentPenSaved)
            .accessibilityHint("Saves the current pen style, colour and width")
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No saved pens yet.")
                .font(.subheadline)
            Text("Pick a pen colour and width, then add it here for one-tap recall.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var penList: some View {
        let rowHeight: CGFloat = 52
        return List {
            ForEach(editor.favoritePens.pens) { pen in
                Button {
                    editor.recallPen(pen)
                    dismiss()
                } label: {
                    row(pen)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        editor.favoritePens.remove(id: pen.id)
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        editor.favoritePens.remove(id: pen.id)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(editor.favoritePens.pens.count) * rowHeight + 8)
    }

    private func row(_ pen: FavoritePen) -> some View {
        let isCurrent = editor.currentPen.matches(pen)
        return HStack(spacing: 10) {
            Image(systemName: pen.style.symbolName)
                .font(.system(size: 16))
                .frame(width: 22)
            Circle()
                .fill(Color(pen.color))
                .overlay(Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5))
                .frame(width: dotSize(pen.width), height: dotSize(pen.width))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(pen.style.displayName)
                    .font(.subheadline)
                Text(String(format: "%.1f pt", pen.width))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(pen.style.displayName), \(editor.colorName(for: pen.color)), \(String(format: "%.1f points", pen.width))"
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var footer: String {
        let current = editor.currentPen
        if editor.favoritePens.isFull {
            return "Six pens saved. Delete one to save another."
        }
        if editor.isCurrentPenSaved {
            return "This pen is already saved."
        }
        return "Saves \(editor.penStyle.displayName.lowercased()), \(editor.colorName(for: current.color)), "
            + String(format: "%.1f pt.", current.width)
    }

    private func dotSize(_ width: Double) -> CGFloat {
        CGFloat(10 + min(max((width - 1) / 39, 0), 1) * 10)
    }
}
#endif

