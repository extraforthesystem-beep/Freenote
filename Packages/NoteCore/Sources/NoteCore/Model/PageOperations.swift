import Foundation

/// Whole-page edits that keep every item's identity. They return a new page
/// instead of changing the one they are given, so a caller can save the result
/// through its ordered write queue.
extension Page {
    /// Rotates the page and everything on it by `quarterTurns` × 90° clockwise.
    /// Negative turns go anticlockwise. The page size swaps for an odd number
    /// of turns; ink and items move with the paper, ids are kept.
    public func rotated(quarterTurns: Int) -> Page {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return self }

        var transform = PageTransform.identity
        var newWidth = width
        var newHeight = height
        for _ in 0..<turns {
            // Quarter turn clockwise about the origin, then back into the new
            // bounds: (x, y) becomes (height - y, x) on a page of `height`.
            transform = transform.then(
                PageTransform(a: 0, b: 1, c: -1, d: 0, tx: newHeight, ty: 0)
            )
            swap(&newWidth, &newHeight)
        }
        let angle = Double(turns) * .pi / 2

        var rotated = self
        rotated.width = newWidth
        rotated.height = newHeight
        rotated.strokes = strokes.map { stroke in
            var moved = stroke
            // The stroke transform maps its points into page space, so the page
            // turn goes after it.
            moved.transform = PageTransform(stroke.transform).then(transform).elements
            return moved
        }
        rotated.elements = elements.map { element in
            var moved = element
            moved.frame = transform.frame(element.frame, addingAngle: angle)
            return moved
        }
        return rotated
    }

    /// Drops every stroke and element of the given kinds, keeping their ids as
    /// tombstones so a later sync merge cannot bring them back. Imported PDF
    /// pages are background, not content, and always survive.
    public func removingItems(of kinds: Set<PageItemKind>) -> Page {
        guard !kinds.isEmpty else { return self }

        let droppedStrokes = strokes.filter { kinds.contains(PageItemKind.of($0)) }
        let droppedElements = elements.filter { element in
            guard let kind = PageItemKind.of(element) else { return false }
            return kinds.contains(kind)
        }
        guard !droppedStrokes.isEmpty || !droppedElements.isEmpty else { return self }

        let droppedStrokeIDs = Set(droppedStrokes.map(\.id))
        let droppedElementIDs = Set(droppedElements.map(\.id))

        var updated = self
        updated.strokes.removeAll { droppedStrokeIDs.contains($0.id) }
        updated.elements.removeAll { droppedElementIDs.contains($0.id) }
        updated.deletedStrokeIDs.formUnion(droppedStrokeIDs)
        updated.deletedElementIDs.formUnion(droppedElementIDs)
        return updated
    }

    /// Empties the page of everything "Delete Specific Items" can clear, so a
    /// page imported from a PDF keeps its background.
    public func cleared() -> Page {
        removingItems(of: Set(PageItemKind.allCases))
    }

    /// Gives the page a new size. Content stays where it is; nothing is scaled.
    public func resized(width: Double, height: Double) -> Page {
        var updated = self
        updated.width = width
        updated.height = height
        return updated
    }
}

/// The affine map `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`, in the order a
/// page file stores a stroke's transform: `a, b, c, d, tx, ty`.
private struct PageTransform {
    var a: Double
    var b: Double
    var c: Double
    var d: Double
    var tx: Double
    var ty: Double

    init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    static let identity = PageTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    /// A stroke's stored transform. All six numbers are there after decoding; a
    /// hand-built record with fewer is treated as identity rather than dropped.
    init(_ elements: [Double]) {
        guard elements.count == StrokeRecord.transformElementCount else {
            self = .identity
            return
        }
        a = elements[0]
        b = elements[1]
        c = elements[2]
        d = elements[3]
        tx = elements[4]
        ty = elements[5]
    }

    var elements: [Double] { [a, b, c, d, tx, ty] }

    /// This map followed by `next`, matching `CGAffineTransform.concatenating`.
    func then(_ next: PageTransform) -> PageTransform {
        PageTransform(
            a: a * next.a + b * next.c,
            b: a * next.b + b * next.d,
            c: c * next.a + d * next.c,
            d: c * next.b + d * next.d,
            tx: tx * next.a + ty * next.c + next.tx,
            ty: tx * next.b + ty * next.d + next.ty
        )
    }

    func point(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
    }

    /// Moves a frame's centre with this map. Its box keeps its size and turns
    /// with the page, and its rotation is about the centre, so an angle is
    /// simply added. The sum is kept in `(-π, π]`: a whole lap of turns leaves
    /// the angle where it was instead of growing without bound.
    func frame(_ frame: ElementFrame, addingAngle angle: Double) -> ElementFrame {
        let centre = point(frame.x + frame.width / 2, frame.y + frame.height / 2)
        return ElementFrame(
            x: centre.x - frame.width / 2,
            y: centre.y - frame.height / 2,
            width: frame.width,
            height: frame.height,
            rotation: (frame.rotation + angle).remainder(dividingBy: 2 * .pi)
        )
    }
}
