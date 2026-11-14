import CoreGraphics
import Foundation

/// An alignment guide drawn while a dragged item snaps to another item's edge
/// or centre: a thin line through the board at one world coordinate.
public struct BoardSnapGuide: Equatable, Hashable, Identifiable, Sendable {
    /// The direction the line runs in. `vertical` is a line at one x,
    /// `horizontal` a line at one y.
    public enum Axis: String, Hashable, Sendable {
        case vertical
        case horizontal
    }

    public let axis: Axis
    /// The world coordinate of the line.
    public let position: CGFloat

    public init(axis: Axis, position: CGFloat) {
        self.axis = axis
        self.position = position
    }

    public var id: String {
        "\(axis == .vertical ? "v" : "h")-\(position)"
    }
}

/// Where a dragged frame lands after snapping, and the guides that explain it.
public struct BoardSnapResult: Equatable, Sendable {
    /// The frame after any snap was applied.
    public var frame: CGRect
    /// One guide per snapped axis: vertical first, then horizontal.
    public var guides: [BoardSnapGuide]

    public init(frame: CGRect, guides: [BoardSnapGuide]) {
        self.frame = frame
        self.guides = guides
    }
}

/// Every edge and centre a dragged frame can snap to, as three x values and
/// three y values per frame-backed item.
///
/// Build it once when a drag begins. The other items cannot move while one is
/// being dragged, so rebuilding it per frame is pure waste: at 500 items a
/// frame would test 18,000 pairs inside the 16.7 ms the drag has to finish in.
public struct BoardSnapTargets: Equatable, Sendable {
    /// Left, centre and right x of every item the drag can snap to.
    public let xEdges: [CGFloat]
    /// Top, middle and bottom y of every item the drag can snap to.
    public let yEdges: [CGFloat]

    /// Collects the targets of every frame-backed item except `itemID`, which
    /// is the item being dragged.
    public init(items: [BoardItem], ignoring itemID: UUID? = nil) {
        var x: [CGFloat] = []
        var y: [CGFloat] = []
        x.reserveCapacity(items.count * 3)
        y.reserveCapacity(items.count * 3)
        for item in items {
            guard item.id != itemID, let frame = item.frame else { continue }
            x.append(frame.minX)
            x.append(frame.midX)
            x.append(frame.maxX)
            y.append(frame.minY)
            y.append(frame.midY)
            y.append(frame.maxY)
        }
        xEdges = x
        yEdges = y
    }

    /// Creates targets from edges that were computed elsewhere.
    public init(xEdges: [CGFloat], yEdges: [CGFloat]) {
        self.xEdges = xEdges
        self.yEdges = yEdges
    }

    /// Whether there is nothing to snap to; a drag on the only item on a board.
    public var isEmpty: Bool {
        xEdges.isEmpty && yEdges.isEmpty
    }

    /// Pulls a dragged frame onto the nearest edge or centre within
    /// `tolerance` world points on each axis, and reports the guide lines to
    /// draw. The axes are decided independently, as the drag shows both at once.
    public func snap(_ frame: CGRect, tolerance: CGFloat) -> BoardSnapResult {
        guard !isEmpty else {
            return BoardSnapResult(frame: frame, guides: [])
        }

        var result = frame
        var guides: [BoardSnapGuide] = []

        if let snap = Self.nearestSnap(
            edges: [frame.minX, frame.midX, frame.maxX],
            targets: xEdges,
            tolerance: tolerance
        ) {
            result.origin.x += snap.delta
            guides.append(BoardSnapGuide(axis: .vertical, position: snap.line))
        }
        if let snap = Self.nearestSnap(
            edges: [frame.minY, frame.midY, frame.maxY],
            targets: yEdges,
            tolerance: tolerance
        ) {
            result.origin.y += snap.delta
            guides.append(BoardSnapGuide(axis: .horizontal, position: snap.line))
        }
        return BoardSnapResult(frame: result, guides: guides)
    }

    /// The smallest move that puts one of `edges` on one of `targets`.
    private static func nearestSnap(
        edges: [CGFloat],
        targets: [CGFloat],
        tolerance: CGFloat
    ) -> (delta: CGFloat, line: CGFloat)? {
        var best: (delta: CGFloat, line: CGFloat)?
        for edge in edges {
            for target in targets {
                let delta = target - edge
                guard abs(delta) <= tolerance else { continue }
                if abs(delta) < abs(best?.delta ?? .infinity) {
                    best = (delta, target)
                }
            }
        }
        return best
    }
}
