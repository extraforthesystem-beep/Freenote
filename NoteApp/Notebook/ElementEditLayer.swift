import NoteCore
import SwiftUI

/// The direct-manipulation layer for page elements. It is only shown while
/// element editing is active, so it never steals Pencil strokes from the canvas.
struct ElementEditLayer: View {
    let page: Page
    @Binding var selectedID: UUID?

    let onFrame: (UUID, ElementFrame) -> Void
    let onLock: (UUID, Bool) -> Void
    let onDelete: (UUID) -> Void
    let onMoveZ: (UUID, Int) -> Void

    @State private var previewFrames: [UUID: ElementFrame] = [:]
    @State private var dragOrigin: (id: UUID, frame: ElementFrame)?
    @State private var resizeOrigin: (id: UUID, frame: ElementFrame)?

    private static let pageSpace = "ElementEditLayer.page"

    private var ordered: [PageElement] {
        page.elements.sorted {
            $0.zIndex == $1.zIndex ? $0.id.uuidString < $1.id.uuidString : $0.zIndex < $1.zIndex
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(ordered) { element in
                elementView(element)
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .coordinateSpace(.named(Self.pageSpace))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedID = nil
        }
    }

    @ViewBuilder
    private func elementView(_ element: PageElement) -> some View {
        let frame = previewFrames[element.id] ?? element.frame
        let isSelected = selectedID == element.id
        let handleSize: CGFloat = 22

        // Order matters: hit area, handle and gestures are attached in the
        // element's own (rotated) space, and `position` comes last so they do
        // not cover the whole page.
        ZStack {
            Rectangle()
                .fill(Color.accentColor.opacity(isSelected ? 0.08 : 0.02))
                .overlay {
                    Rectangle()
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.45),
                            style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [4, 3])
                        )
                }

            if element.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(4)
                    .background(.thinMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }
        }
        .frame(width: max(frame.width, 1), height: max(frame.height, 1))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedID = element.id
        }
        .gesture(moveGesture(for: element))
        .overlay(alignment: .bottomTrailing) {
            if isSelected, !element.isLocked {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: handleSize, height: handleSize)
                    .overlay {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    // A 44 pt touch target around the small visible handle.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    // Centres the handle on the element's corner.
                    .offset(x: 22, y: 22)
                    .gesture(resizeGesture(for: element))
                    .accessibilityLabel("Resize element")
            }
        }
        .contextMenu {
            Button("Bring Forward", systemImage: "square.2.layers.3d.top.filled") {
                onMoveZ(element.id, 1)
            }
            Button("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") {
                onMoveZ(element.id, -1)
            }
            Divider()
            Button(element.isLocked ? "Unlock" : "Lock", systemImage: element.isLocked ? "lock.open" : "lock") {
                onLock(element.id, !element.isLocked)
            }
            Button("Rotate Left", systemImage: "rotate.left") {
                onFrame(element.id, rotated(element.frame, by: -.pi / 12))
            }
            Button("Rotate Right", systemImage: "rotate.right") {
                onFrame(element.id, rotated(element.frame, by: .pi / 12))
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete(element.id)
            }
        }
        .rotationEffect(.radians(frame.rotation))
        .position(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    /// Measured in page space, so a rotated element follows the finger rather
    /// than its own rotated axes.
    private func moveGesture(for element: PageElement) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.pageSpace))
            .onChanged { value in
                guard !element.isLocked else { return }
                if dragOrigin?.id != element.id {
                    dragOrigin = (element.id, element.frame)
                }
                guard let origin = dragOrigin?.frame else { return }
                var updated = origin
                updated.x = min(max(0, origin.x + value.translation.width), max(page.width - origin.width, 0))
                updated.y = min(max(0, origin.y + value.translation.height), max(page.height - origin.height, 0))
                previewFrames[element.id] = updated
            }
            .onEnded { _ in
                guard !element.isLocked,
                      let updated = previewFrames[element.id]
                else {
                    dragOrigin = nil
                    return
                }
                previewFrames[element.id] = nil
                dragOrigin = nil
                selectedID = element.id
                onFrame(element.id, updated)
            }
    }

    private func resizeGesture(for element: PageElement) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizeOrigin?.id != element.id {
                    resizeOrigin = (element.id, element.frame)
                }
                guard let origin = resizeOrigin?.frame else { return }
                var updated = origin
                updated.width = min(max(44, origin.width + value.translation.width), page.width - origin.x)
                updated.height = min(max(32, origin.height + value.translation.height), page.height - origin.y)
                previewFrames[element.id] = updated
            }
            .onEnded { _ in
                guard let updated = previewFrames[element.id] else {
                    resizeOrigin = nil
                    return
                }
                previewFrames[element.id] = nil
                resizeOrigin = nil
                onFrame(element.id, updated)
            }
    }

    private func rotated(_ frame: ElementFrame, by radians: Double) -> ElementFrame {
        var updated = frame
        updated.rotation += radians
        return updated
    }
}
