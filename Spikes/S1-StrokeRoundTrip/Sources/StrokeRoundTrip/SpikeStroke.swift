import Foundation

// A plain, documented, PencilKit-free representation of one `PKStroke`.
//
// Everything here is a Foundation value type, so the whole thing is `Codable`
// and encodable as JSON. No PencilKit type appears in this file.

public struct SpikePoint2D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct SpikeSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

/// The six components of a `CGAffineTransform`, in PencilKit's own field order.
public struct SpikeAffineTransform: Codable, Equatable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = SpikeAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}

/// A colour stored as raw components in the colour space they were read in.
///
/// `components` are the colour space's native components plus alpha: 3+1 for an
/// RGB space, 1+1 for a grey space, 4+1 for CMYK.
public struct SpikeColor: Codable, Equatable, Sendable {
    /// The CoreGraphics name of the colour space (e.g. `kCGColorSpaceSRGB`),
    /// or `custom` when the space has no name (then `iccProfile` is set).
    public var spaceName: String
    /// Native components followed by alpha, exactly as `NSColor.getComponents` returns them.
    public var components: [Double]
    /// ICC profile bytes, only for unnamed colour spaces.
    public var iccProfile: Data?
    /// The `NSColor.type` that was originally read: `componentBased`, `catalog`, `pattern`, ...
    public var sourceType: String
    /// For catalog colours: the catalog and colour names, so the identity can be rebuilt.
    public var catalogName: String?
    public var colorName: String?
    /// RGBA resolved into sRGB, for humans and for lossy fallbacks. Not authoritative.
    public var resolvedSRGB: [Double]?

    public init(spaceName: String,
                components: [Double],
                iccProfile: Data? = nil,
                sourceType: String,
                catalogName: String? = nil,
                colorName: String? = nil,
                resolvedSRGB: [Double]? = nil) {
        self.spaceName = spaceName
        self.components = components
        self.iccProfile = iccProfile
        self.sourceType = sourceType
        self.catalogName = catalogName
        self.colorName = colorName
        self.resolvedSRGB = resolvedSRGB
    }
}

public struct SpikeInk: Codable, Equatable, Sendable {
    /// `PKInkingTool.InkType.rawValue`: pen, pencil, marker, monoline,
    /// fountainPen, watercolor, crayon, reed.
    public var inkType: String
    public var color: SpikeColor
    /// Informational: PencilKit says which content version this ink needs.
    public var requiredContentVersion: Int?

    public init(inkType: String, color: SpikeColor, requiredContentVersion: Int? = nil) {
        self.inkType = inkType
        self.color = color
        self.requiredContentVersion = requiredContentVersion
    }
}

/// Every stored property of `PKStrokePoint`.
public struct SpikePoint: Codable, Equatable, Sendable {
    public var location: SpikePoint2D
    public var timeOffset: Double
    public var size: SpikeSize
    public var opacity: Double
    public var force: Double
    public var azimuth: Double
    public var altitude: Double
    public var secondaryScale: Double
    public var threshold: Double
    public var lateralJitter: Double

    public init(location: SpikePoint2D,
                timeOffset: Double,
                size: SpikeSize,
                opacity: Double,
                force: Double,
                azimuth: Double,
                altitude: Double,
                secondaryScale: Double,
                threshold: Double,
                lateralJitter: Double) {
        self.location = location
        self.timeOffset = timeOffset
        self.size = size
        self.opacity = opacity
        self.force = force
        self.azimuth = azimuth
        self.altitude = altitude
        self.secondaryScale = secondaryScale
        self.threshold = threshold
        self.lateralJitter = lateralJitter
    }
}

public struct SpikePath: Codable, Equatable, Sendable {
    public var id: UUID
    /// `Date.timeIntervalSinceReferenceDate`.
    public var creationDate: Double
    public var controlPoints: [SpikePoint]

    public init(id: UUID, creationDate: Double, controlPoints: [SpikePoint]) {
        self.id = id
        self.creationDate = creationDate
        self.controlPoints = controlPoints
    }
}

/// One element of the stroke's mask (`NSBezierPath`).
public struct SpikePathElement: Codable, Equatable, Sendable {
    /// move | line | cubic | quadratic | close
    public var kind: String
    /// Associated points in Apple's documented order:
    /// cubic = [control1, control2, end], quadratic = [control, end], others = [end].
    public var points: [SpikePoint2D]

    public init(kind: String, points: [SpikePoint2D]) {
        self.kind = kind
        self.points = points
    }
}

public struct SpikeMask: Codable, Equatable, Sendable {
    public var elements: [SpikePathElement]
    /// `NSBezierPath.WindingRule` raw value.
    public var windingRule: Int

    public init(elements: [SpikePathElement], windingRule: Int) {
        self.elements = elements
        self.windingRule = windingRule
    }
}

/// `PKStroke.RenderState`, whose Swift surface is `Codable` but only partly documented.
public struct SpikeRenderState: Codable, Equatable, Sendable {
    public var grainOffset: SpikePoint2D?
    /// The render state's own `Codable` encoding. Apple documents the type as
    /// "some state is exposed, but other state is opaque"; this blob is how the
    /// opaque part can be carried without understanding it.
    public var codableJSON: Data?

    public init(grainOffset: SpikePoint2D? = nil, codableJSON: Data? = nil) {
        self.grainOffset = grainOffset
        self.codableJSON = codableJSON
    }
}

public struct SpikeStroke: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var strokeID: UUID
    public var ink: SpikeInk
    public var transform: SpikeAffineTransform
    public var path: SpikePath
    public var mask: SpikeMask?
    public var randomSeed: UInt32
    public var renderGroupID: UUID?
    public var renderState: SpikeRenderState?
    /// Informational: read-only on `PKStroke`, compared by check F.
    public var requiredContentVersion: Int?

    public init(formatVersion: Int = 1,
                strokeID: UUID,
                ink: SpikeInk,
                transform: SpikeAffineTransform,
                path: SpikePath,
                mask: SpikeMask?,
                randomSeed: UInt32,
                renderGroupID: UUID?,
                renderState: SpikeRenderState?,
                requiredContentVersion: Int?) {
        self.formatVersion = formatVersion
        self.strokeID = strokeID
        self.ink = ink
        self.transform = transform
        self.path = path
        self.mask = mask
        self.randomSeed = randomSeed
        self.renderGroupID = renderGroupID
        self.renderState = renderState
        self.requiredContentVersion = requiredContentVersion
    }

    public var controlPointCount: Int { path.controlPoints.count }
}

// MARK: - JSON helpers

public enum SpikeJSON {
    public static func encode(_ stroke: SpikeStroke, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(stroke)
    }

    public static func decode(_ data: Data) throws -> SpikeStroke {
        try JSONDecoder().decode(SpikeStroke.self, from: data)
    }
}
