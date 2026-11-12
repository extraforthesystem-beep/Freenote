import NoteCore
import SwiftUI

/// Add, reorder, hide, lock and delete page layers. The page stores every
/// layer; hiding one only removes its ink and elements from the live view.
struct LayersPanel: View {
    let session: NotebookSession

    @Environment(\.dismiss) private var dismiss
    @State private var renameTarget: Page.Layer?
    @State private var renameText = ""

    private var layers: [Page.Layer] {
        session.page?.layers ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if layers.isEmpty {
                    ContentUnavailableView(
                        "No Layers",
                        systemImage: "square.3.layers.3d",
                        description: Text("Open a page to see its layers.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(layers.reversed(), id: \.id) { layer in
                                row(layer)
                            }
                        } footer: {
                            Text("The top layer is listed first. New ink goes to the layer with the checkmark.")
                        }

                        Section {
                            Button("Add Layer", systemImage: "plus") {
                                Task { await session.addLayer() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Layers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename layer", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Layer name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Rename") {
                    if let target = renameTarget {
                        Task { await session.renameLayer(target.id, to: renameText) }
                    }
                    renameTarget = nil
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ layer: Page.Layer) -> some View {
        let isActive = session.activeLayerID == layer.id
        let strokeCount = session.page?.strokes.filter { $0.layerID == layer.id }.count ?? 0
        let elementCount = session.page?.elements.filter { $0.layerID == layer.id }.count ?? 0

        HStack(spacing: 12) {
            Button {
                session.setActiveLayer(layer.id)
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive ? "Active layer" : "Make active")

            VStack(alignment: .leading, spacing: 2) {
                Text(layer.name)
                    .font(.body.weight(isActive ? .semibold : .regular))
                Text("\(strokeCount) stroke\(strokeCount == 1 ? "" : "s") · \(elementCount) object\(elementCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await session.toggleLayerVisibility(layer.id) }
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.isVisible ? Color.secondary : Color.orange)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(layer.isVisible ? "Hide layer" : "Show layer")

            Button {
                Task { await session.toggleLayerLock(layer.id) }
            } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(layer.isLocked ? Color.orange : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(layer.isLocked ? "Unlock layer" : "Lock layer")

            Menu {
                Button("Rename…", systemImage: "pencil") {
                    renameText = layer.name
                    renameTarget = layer
                }
                Button("Move Up", systemImage: "arrow.up") {
                    Task { await session.moveLayer(layer.id, by: 1) }
                }
                .disabled(layers.last?.id == layer.id)
                Button("Move Down", systemImage: "arrow.down") {
                    Task { await session.moveLayer(layer.id, by: -1) }
                }
                .disabled(layers.first?.id == layer.id)
                Divider()
                Button("Delete Layer", systemImage: "trash", role: .destructive) {
                    Task { await session.deleteLayer(layer.id) }
                }
                .disabled(layers.count <= 1)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}
