import Foundation

/// One element of a vector outline, in the same coordinate space as the stroke.
public enum PathElement: Sendable, Hashable, Codable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case quad(cx: Double, cy: Double, x: Double, y: Double)
    case cubic(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close

    private enum CodingKeys: String, CodingKey {
        case kind, x, y, cx, cy, c1x, c1y, c2x, c2y
    }

    private enum Kind: String, Codable {
        case move, line, quad, cubic, close
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .move:
            self = .move(
                x: try container.decode(Double.self, forKey: .x),
                y: try container.decode(Double.self, forKey: .y)
            )
        case .line:
            self = .line(
                x: try container.decode(Double.self, forKey: .x),
                y: try container.decode(Double.self, forKey: .y)
            )
        case .quad:
            self = .quad(
                cx: try container.decode(Double.self, forKey: .cx),
                cy: try container.decode(Double.self, forKey: .cy),
                x: try container.decode(Double.self, forKey: .x),
                y: try container.decode(Double.self, forKey: .y)
            )
        case .cubic:
            self = .cubic(
                c1x: try container.decode(Double.self, forKey: .c1x),
                c1y: try container.decode(Double.self, forKey: .c1y),
                c2x: try container.decode(Double.self, forKey: .c2x),
                c2y: try container.decode(Double.self, forKey: .c2y),
                x: try container.decode(Double.self, forKey: .x),
                y: try container.decode(Double.self, forKey: .y)
            )
        case .close:
            self = .close
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .move(x, y):
            try container.encode(Kind.move, forKey: .kind)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case let .line(x, y):
            try container.encode(Kind.line, forKey: .kind)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case let .quad(cx, cy, x, y):
            try container.encode(Kind.quad, forKey: .kind)
            try container.encode(cx, forKey: .cx)
            try container.encode(cy, forKey: .cy)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case let .cubic(c1x, c1y, c2x, c2y, x, y):
            try container.encode(Kind.cubic, forKey: .kind)
            try container.encode(c1x, forKey: .c1x)
            try container.encode(c1y, forKey: .c1y)
            try container.encode(c2x, forKey: .c2x)
            try container.encode(c2y, forKey: .c2y)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case .close:
            try container.encode(Kind.close, forKey: .kind)
        }
    }
}
