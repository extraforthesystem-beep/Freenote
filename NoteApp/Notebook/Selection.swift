import Foundation
import NoteCore

/// What is selected on the page: ink strokes and page elements, by id.
///
/// Stroke ids are `StrokeRecord.id` and survive a canvas rebuild, so the
/// selection stays meaningful after an action recolours or re-widths the ink.
/// Selection is view state: it is never written to the page file.
nonisolated struct InkSelection: Equatable {
    var strokeIDs: Set<UUID> = []
    var elementIDs: Set<UUID> = []

    var isEmpty: Bool { strokeIDs.isEmpty && elementIDs.isEmpty }
    var count: Int { strokeIDs.count + elementIDs.count }
    var hasInk: Bool { !strokeIDs.isEmpty }

    mutating func clear() {
        strokeIDs.removeAll()
        elementIDs.removeAll()
    }
}

nonisolated extension InkSelection {
    /// The selected strokes in page paint order.
    func strokes(in page: Page) -> [StrokeRecord] {
        page.strokes.filter { strokeIDs.contains($0.id) }
    }

    func elements(in page: Page) -> [PageElement] {
        page.elements.filter { elementIDs.contains($0.id) }
    }

    /// The selected ink that an action may change: a stroke on a locked layer
    /// stays untouched. (A hidden layer cannot be selected, but it can be
    /// locked between selecting and acting.)
    func editableStrokes(in page: Page) -> [StrokeRecord] {
        let locked = Set(page.layers.filter(\.isLocked).map(\.id))
        return strokes(in: page).filter { !locked.contains($0.layerID) }
    }

    func editableElements(in page: Page) -> [PageElement] {
        let locked = Set(page.layers.filter(\.isLocked).map(\.id))
        return elements(in: page).filter { !locked.contains($0.layerID) }
    }
}
