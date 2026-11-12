import CoreGraphics
import Foundation

/// The viewport onto a board: a world-space centre point and a zoom factor.
public struct BoardCamera: Codable, Hashable, Sendable {
    /// Smallest allowed zoom.
    public static let minimumZoom: Double = 0.1
    /// Largest allowed zoom.
    public static let maximumZoom: Double = 8.0

    /// World x coordinate shown at the centre of the view.
    public var centerX: Double {
        didSet {
            if !centerX.isFinite { centerX = 0 }
        }
    }

    /// World y coordinate shown at the centre of the view.
    public var centerY: Double {
        didSet {
            if !centerY.isFinite { centerY = 0 }
        }
    }

    /// View points per world point, clamped to `minimumZoom...maximumZoom`.
    public var zoom: Double {
        didSet {
            zoom = Self.clampZoom(zoom)
        }
    }

    /// Creates a camera. Non-finite centres become zero and zoom is clamped.
    public init(centerX: Double = 0, centerY: Double = 0, zoom: Double = 1) {
        self.centerX = centerX.isFinite ? centerX : 0
        self.centerY = centerY.isFinite ? centerY : 0
        self.zoom = Self.clampZoom(zoom)
    }

    private enum CodingKeys: String, CodingKey {
        case centerX, centerY, zoom
    }

    /// Decodes a camera, clamping its zoom into the supported range.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            centerX: try container.decode(Double.self, forKey: .centerX),
            centerY: try container.decode(Double.self, forKey: .centerY),
            zoom: try container.decode(Double.self, forKey: .zoom)
        )
    }

    /// Converts a point in view coordinates to world coordinates.
    public func worldPoint(fromViewPoint point: CGPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - viewSize.width / 2) / zoom + centerX,
            y: (point.y - viewSize.height / 2) / zoom + centerY
        )
    }

    /// Converts a point in world coordinates to view coordinates.
    public func viewPoint(fromWorldPoint point: CGPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - centerX) * zoom + viewSize.width / 2,
            y: (point.y - centerY) * zoom + viewSize.height / 2
        )
    }

    /// The world rectangle covered by a view of `viewSize`.
    public func visibleWorldRect(viewSize: CGSize) -> CGRect {
        let width = max(0, viewSize.width) / zoom
        let height = max(0, viewSize.height) / zoom
        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }

    private static func clampZoom(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, minimumZoom), maximumZoom)
    }
}
