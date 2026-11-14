import SwiftUI

/// The laser pointer drawn over the page.
///
/// It is a pointer, not ink: it never touches the canvas, never creates a
/// stroke and never marks the page dirty. In `Dot` mode a glowing dot follows
/// the pointer; in `Line` mode the trail it leaves fades out after the pencil
/// or finger lifts.
struct LaserPointerOverlay: View {
    var mode: LaserMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points of the mark being drawn, in page points.
    @State private var livePoints: [CGPoint] = []
    /// Marks whose pointer has lifted, fading out. Only the recent few are kept.
    @State private var fadingMarks: [LaserMark] = []

    /// Marks still fading when a new one starts are dropped first.
    private static let maxFadingMarks = 12
    /// A long visit is capped so the trail cannot grow without bound.
    private static let maxLivePoints = 1_200

    private var fadeDuration: Double {
        mode == .dot ? 0.25 : 0.8
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(fadingMarks) { mark in
                LaserMarkView(mark: mark, points: mark.points, isDot: mark.isDot)
            }
            if !livePoints.isEmpty {
                LaserMarkView(mark: nil, points: livePoints, isDot: mode == .dot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if livePoints.isEmpty {
                        fadingMarks.removeAll { $0.opacity <= 0 }
                    }
                    if livePoints.count >= Self.maxLivePoints {
                        livePoints.removeFirst(livePoints.count - Self.maxLivePoints + 1)
                    }
                    livePoints.append(value.location)
                }
                .onEnded { _ in finishMark() }
        )
        .accessibilityHidden(true)
    }

    /// Hands the mark just drawn to the fading list and dissolves it.
    private func finishMark() {
        guard !livePoints.isEmpty else { return }
        let mark = LaserMark(points: livePoints, isDot: mode == .dot)
        livePoints.removeAll(keepingCapacity: true)
        // The long cool-down is the point of the trail, but with Reduce Motion
        // on nothing moves: the mark is dropped at once instead.
        guard !reduceMotion else { return }
        fadingMarks.append(mark)
        if fadingMarks.count > Self.maxFadingMarks {
            fadingMarks.removeFirst(fadingMarks.count - Self.maxFadingMarks)
        }
        // It is shown fully opaque first, so animating it to zero reads as the
        // trail cooling off after the pointer lifts.
        AppMotion.animate(.easeOut(duration: fadeDuration), reduceMotion: reduceMotion) {
            if let index = fadingMarks.firstIndex(where: { $0.id == mark.id }) {
                fadingMarks[index].opacity = 0
            }
        }
    }
}

/// One laser mark: the dot under the pointer, or the trail behind it.
private struct LaserMark: Identifiable {
    static let red = Color(red: 0.93, green: 0.12, blue: 0.16)

    let id = UUID()
    var points: [CGPoint]
    var isDot = false
    var opacity: Double = 1
}

private struct LaserMarkView: View {
    /// The mark being drawn, if any, so its opacity animates with the rest.
    let mark: LaserMark?
    let points: [CGPoint]
    var isDot = false

    var body: some View {
        Canvas { context, _ in
            if isDot || points.count == 1 {
                drawDot(in: context)
            } else {
                drawTrail(in: context)
            }
        }
        .opacity(mark?.opacity ?? 1)
        .allowsHitTesting(false)
    }

    private func drawDot(in context: GraphicsContext) {
        guard let point = points.last else { return }
        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        var glow = context
        glow.addFilter(.blur(radius: 6))
        glow.fill(circle(10), with: .color(LaserMark.red.opacity(0.8)))
        context.fill(circle(4.5), with: .color(LaserMark.red))
        context.fill(circle(1.8), with: .color(.white.opacity(0.9)))
    }

    private func drawTrail(in context: GraphicsContext) {
        let path = trailPath(points)
        var glow = context
        glow.addFilter(.blur(radius: 7))
        glow.stroke(
            path,
            with: .color(LaserMark.red.opacity(0.85)),
            style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(LaserMark.red),
            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        )
    }

    /// A smoothed polyline: midpoints joined by quadratics, which is cheap and
    /// keeps a fast stroke from looking like a chain of segments.
    private func trailPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last ?? first)
            return path
        }
        for index in 1..<(points.count - 1) {
            let point = points[index]
            let next = points[index + 1]
            let midpoint = CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2)
            path.addQuadCurve(to: midpoint, control: point)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }
}
