import CoreGraphics
import Foundation

/// Alignment edges for `BoardLayout.align`.
public enum BoardAlignment: String, Codable, CaseIterable, Sendable {
    case left
    /// Horizontal centre.
    case center
    case right
    case top
    /// Vertical centre.
    case middle
    case bottom
}

/// Axis for `BoardLayout.distribute`.
public enum BoardDistributionAxis: String, Codable, CaseIterable, Sendable {
    case horizontal
    case vertical
}

/// Alignment and distribution helpers for selected board items.
public enum BoardLayout {
    /// Aligns selected frame-backed, unlocked items to the selection's bounding edge.
    public static func align(
        _ alignment: BoardAlignment,
        itemIDs: Set<UUID>,
        in board: inout Board,
        at date: Date = Date()
    ) {
        let selected = selectedItems(itemIDs, in: board)
        guard selected.count >= 2 else { return }

        var union: CGRect?
        for item in selected {
            guard let frame = item.frame else { continue }
            union = union.map { $0.union(frame) } ?? frame
        }
        guard let union else { return }

        for item in selected {
            guard let frame = item.frame else { continue }
            var origin = frame.origin
            switch alignment {
            case .left:
                origin.x = union.minX
            case .center:
                origin.x = union.midX - frame.width / 2
            case .right:
                origin.x = union.maxX - frame.width
            case .top:
                origin.y = union.minY
            case .middle:
                origin.y = union.midY - frame.height / 2
            case .bottom:
                origin.y = union.maxY - frame.height
            }
            board.setFrame(
                item.id,
                to: CGRect(origin: origin, size: frame.size),
                at: date
            )
        }
    }

    /// Distributes selected frame-backed, unlocked items with equal gaps.
    ///
    /// The first and last items in the axis stay fixed; at least three items are needed.
    public static func distribute(
        _ axis: BoardDistributionAxis,
        itemIDs: Set<UUID>,
        in board: inout Board,
        at date: Date = Date()
    ) {
        let selected = selectedItems(itemIDs, in: board)
        guard selected.count >= 3 else { return }
        switch axis {
        case .horizontal:
            distributeHorizontally(selected, in: &board, at: date)
        case .vertical:
            distributeVertically(selected, in: &board, at: date)
        }
    }

    private static func selectedItems(_ ids: Set<UUID>, in board: Board) -> [BoardItem] {
        var seen = Set<UUID>()
        return board.items.filter { item in
            guard ids.contains(item.id),
                  !item.isLocked,
                  !board.deletedItemIDs.contains(item.id),
                  item.frame != nil,
                  seen.insert(item.id).inserted
            else {
                return false
            }
            return true
        }
    }

    private static func distributeHorizontally(
        _ items: [BoardItem],
        in board: inout Board,
        at date: Date
    ) {
        let sorted = items.sorted { lhs, rhs in
            let left = lhs.frame?.minX ?? 0
            let right = rhs.frame?.minX ?? 0
            if left != right { return left < right }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let first = sorted.first?.frame,
              let last = sorted.last?.frame,
              sorted.count >= 3
        else {
            return
        }

        let totalWidth = sorted.reduce(0.0) { $0 + ($1.frame?.width ?? 0) }
        let gap = ((last.maxX - first.minX) - totalWidth) / Double(sorted.count - 1)
        var cursor = first.maxX
        for item in sorted.dropFirst().dropLast() {
            guard let frame = item.frame else { continue }
            let x = cursor + gap
            board.setFrame(
                item.id,
                to: CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height),
                at: date
            )
            cursor = x + frame.width
        }
    }

    private static func distributeVertically(
        _ items: [BoardItem],
        in board: inout Board,
        at date: Date
    ) {
        let sorted = items.sorted { lhs, rhs in
            let top = lhs.frame?.minY ?? 0
            let bottom = rhs.frame?.minY ?? 0
            if top != bottom { return top < bottom }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let first = sorted.first?.frame,
              let last = sorted.last?.frame,
              sorted.count >= 3
        else {
            return
        }

        let totalHeight = sorted.reduce(0.0) { $0 + ($1.frame?.height ?? 0) }
        let gap = ((last.maxY - first.minY) - totalHeight) / Double(sorted.count - 1)
        var cursor = first.maxY
        for item in sorted.dropFirst().dropLast() {
            guard let frame = item.frame else { continue }
            let y = cursor + gap
            board.setFrame(
                item.id,
                to: CGRect(x: frame.minX, y: y, width: frame.width, height: frame.height),
                at: date
            )
            cursor = y + frame.height
        }
    }
}
