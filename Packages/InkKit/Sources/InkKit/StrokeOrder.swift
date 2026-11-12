import Foundation
import NoteCore

/// The order strokes are painted in.
///
/// Layers paint bottom to top in `Page.layers` order. Within one layer,
/// highlighter strokes paint first so they sit under pen ink, the way a paper
/// highlighter does; otherwise the stored order is kept. Both sorts are stable,
/// so applying the order twice changes nothing.
public enum StrokeOrder {
    /// Orders `strokes` by `layerOrder`. A stroke whose layer is not listed
    /// goes after the listed layers, grouped by first appearance.
    public static func renderOrder(_ strokes: [StrokeRecord], layerOrder: [UUID]) -> [StrokeRecord] {
        var rank: [UUID: Int] = [:]
        for (index, layerID) in layerOrder.enumerated() where rank[layerID] == nil {
            rank[layerID] = index
        }
        var next = layerOrder.count
        for stroke in strokes where rank[stroke.layerID] == nil {
            rank[stroke.layerID] = next
            next += 1
        }
        return strokes.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.layerID] ?? 0
                let right = rank[rhs.element.layerID] ?? 0
                if left != right { return left < right }
                let leftHighlighter = lhs.element.tool.isHighlighter
                if leftHighlighter != rhs.element.tool.isHighlighter { return leftHighlighter }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Orders `strokes` with layers ranked by their first appearance. Strokes
    /// that are already in render order keep it.
    public static func renderOrder(_ strokes: [StrokeRecord]) -> [StrokeRecord] {
        renderOrder(strokes, layerOrder: [])
    }

    /// The result of folding the canvas's strokes back into a page.
    public struct Merge: Equatable, Sendable {
        /// Every stroke of the page, in render order.
        public var strokes: [StrokeRecord]
        /// Strokes that were on the page and are gone now (erased or undone).
        public var removedIDs: Set<UUID>
        /// Strokes that are on the page and were not before.
        public var addedIDs: Set<UUID>
    }

    /// Folds the strokes the canvas shows back into the page's full stroke list.
    ///
    /// The canvas only shows visible layers, so strokes on `hiddenLayerIDs` are
    /// kept as they are. A known stroke is replaced in place, so editing,
    /// hiding or showing a layer never reshuffles the stacking; new strokes are
    /// appended, and the result is put in render order.
    public static func merge(
        existing: [StrokeRecord],
        canvas: [StrokeRecord],
        hiddenLayerIDs: Set<UUID>,
        layerOrder: [UUID]
    ) -> Merge {
        var incoming: [UUID: StrokeRecord] = [:]
        incoming.reserveCapacity(canvas.count)
        for stroke in canvas where !hiddenLayerIDs.contains(stroke.layerID) {
            incoming[stroke.id] = stroke
        }

        var result: [StrokeRecord] = []
        result.reserveCapacity(existing.count + canvas.count)
        var seen = Set<UUID>()
        var removed = Set<UUID>()
        for stroke in existing {
            if hiddenLayerIDs.contains(stroke.layerID) {
                result.append(stroke)
                seen.insert(stroke.id)
            } else if let updated = incoming[stroke.id] {
                result.append(updated)
                seen.insert(stroke.id)
            } else {
                removed.insert(stroke.id)
            }
        }

        var added = Set<UUID>()
        for stroke in canvas where incoming[stroke.id] != nil && !seen.contains(stroke.id) {
            result.append(stroke)
            seen.insert(stroke.id)
            added.insert(stroke.id)
        }
        return Merge(
            strokes: renderOrder(result, layerOrder: layerOrder),
            removedIDs: removed,
            addedIDs: added
        )
    }
}

public extension Page {
    /// Strokes on visible layers, in the order they are painted. Use this for
    /// every render of the page: the canvas, thumbnails and export.
    var renderStrokes: [StrokeRecord] {
        let visible = Set(layers.filter(\.isVisible).map(\.id))
        return StrokeOrder.renderOrder(
            strokes.filter { visible.contains($0.layerID) },
            layerOrder: layers.map(\.id)
        )
    }
}
