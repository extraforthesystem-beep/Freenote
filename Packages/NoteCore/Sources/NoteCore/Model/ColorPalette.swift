import Foundation

/// The colour data the editor's palette, favourites and recents are built
/// from. Pure values and list operations only, so the editor state stays
/// testable and platform-neutral.
public enum InkColorDefaults {
    /// Pen favourites: black, dark grey, blue, red, green, orange, purple, brown.
    public static let pen: [RGBAColor] = [
        .black,
        RGBAColor(r: 0.32, g: 0.32, b: 0.34),
        RGBAColor(r: 0.0, g: 0.36, b: 0.86),
        RGBAColor(r: 0.85, g: 0.13, b: 0.15),
        RGBAColor(r: 0.09, g: 0.56, b: 0.27),
        RGBAColor(r: 0.96, g: 0.55, b: 0.05),
        RGBAColor(r: 0.45, g: 0.25, b: 0.70),
        RGBAColor(r: 0.47, g: 0.30, b: 0.16),
    ]

    /// Highlighter favourites, kept light so ink underneath stays readable.
    public static let highlighter: [RGBAColor] = [
        RGBAColor(r: 1.0, g: 0.91, b: 0.30),
        RGBAColor(r: 0.62, g: 0.90, b: 0.55),
        RGBAColor(r: 1.0, g: 0.65, b: 0.82),
        RGBAColor(r: 0.60, g: 0.80, b: 1.0),
        RGBAColor(r: 1.0, g: 0.73, b: 0.45),
        RGBAColor(r: 0.76, g: 0.65, b: 0.95),
        RGBAColor(r: 0.85, g: 0.85, b: 0.85),
        RGBAColor(r: 0.50, g: 0.85, b: 0.82),
    ]
}

/// The 64 presets of the palette popover: eight rows of hue families, each
/// laid out light to dark, plus a top row of greys.
public enum ColorPalette {
    public static let rowCount = 8
    public static let columnCount = 8

    /// Hue in degrees for every row below the greys.
    private static let rowHues: [Double] = [0, 30, 55, 120, 180, 215, 275]

    /// Saturation and brightness steps within a hue row, light to dark.
    private static let shades: [(saturation: Double, brightness: Double)] = [
        (0.16, 1.00),
        (0.34, 0.99),
        (0.52, 0.95),
        (0.68, 0.88),
        (0.80, 0.78),
        (0.88, 0.65),
        (0.90, 0.52),
        (0.86, 0.38),
    ]

    /// The greys row, light to dark.
    private static let greyValues: [Double] = [0.98, 0.87, 0.75, 0.61, 0.47, 0.33, 0.19, 0.05]

    /// Eight rows of eight, in grid order.
    public static let rows: [[RGBAColor]] = {
        var rows = [greyValues.map { RGBAColor(r: $0, g: $0, b: $0) }]
        for hue in rowHues {
            rows.append(shades.map { shade in
                color(hue: hue, saturation: shade.saturation, brightness: shade.brightness)
            })
        }
        return rows
    }()

    /// All 64 presets, flattened in grid order.
    public static let presets: [RGBAColor] = rows.flatMap { $0 }

    /// A rough spoken name for a colour: a hue family, "Light"/"Dark" for very
    /// light or dark shades, and the greys by brightness. Used for VoiceOver
    /// labels, so it stays short and approximate.
    public static func name(for color: RGBAColor) -> String {
        let hsb = hsb(of: color)
        if hsb.saturation < 0.10 { return greyName(hsb.brightness) }
        let base = hueName(hsb.hue)
        if base == "Orange", hsb.saturation > 0.45, hsb.brightness < 0.64 { return "Brown" }
        if hsb.brightness < 0.42 { return "Dark \(base)" }
        if hsb.brightness > 0.92, hsb.saturation < 0.45 { return "Light \(base)" }
        return base
    }

    private static func hueName(_ hue: Double) -> String {
        switch hue {
        case ..<15: "Red"
        case ..<45: "Orange"
        case ..<70: "Yellow"
        case ..<160: "Green"
        case ..<200: "Teal"
        case ..<255: "Blue"
        case ..<290: "Purple"
        case ..<345: "Pink"
        default: "Red"
        }
    }

    private static func greyName(_ brightness: Double) -> String {
        switch brightness {
        case ...0.12: "Black"
        case ...0.28: "Charcoal"
        case ...0.48: "Dark Grey"
        case ...0.72: "Grey"
        case ...0.94: "Light Grey"
        default: "White"
        }
    }

    /// Hue in degrees, saturation and brightness of a colour.
    static func hsb(of color: RGBAColor) -> (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(color.r, color.g, color.b)
        let minimum = min(color.r, color.g, color.b)
        let delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum
        guard delta > 0 else { return (0, saturation, maximum) }
        let hue: Double
        if maximum == color.r {
            hue = 60 * ((color.g - color.b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == color.g {
            hue = 60 * ((color.b - color.r) / delta + 2)
        } else {
            hue = 60 * ((color.r - color.g) / delta + 4)
        }
        return (hue < 0 ? hue + 360 : hue, saturation, maximum)
    }

    /// HSB to sRGB. PencilKit stores sRGB, so every preset is already in it.
    static func color(hue: Double, saturation: Double, brightness: Double) -> RGBAColor {
        let hue = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let sector = hue / 60
        let chroma = brightness * saturation
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma

        let rgb: (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: rgb = (chroma, second, 0)
        case 1: rgb = (second, chroma, 0)
        case 2: rgb = (0, chroma, second)
        case 3: rgb = (0, second, chroma)
        case 4: rgb = (second, 0, chroma)
        default: rgb = (chroma, 0, second)
        }
        return RGBAColor(r: rgb.0 + match, g: rgb.1 + match, b: rgb.2 + match)
    }
}

/// The eight favourite colours of one ink tool. Fewer than eight is allowed:
/// the toolbar then offers a free slot to add the current colour.
public struct ColorFavorites: Codable, Hashable, Sendable {
    public static let capacity = 8

    public private(set) var colors: [RGBAColor]

    public init(_ colors: [RGBAColor] = []) {
        var result: [RGBAColor] = []
        for color in colors {
            let opaque = Self.opaque(color)
            guard !result.contains(where: { Self.matches($0, opaque) }) else { continue }
            result.append(opaque)
        }
        self.colors = Array(result.prefix(Self.capacity))
    }

    /// Takes an older recent-colours list into the first slots, then fills the
    /// rest from the tool's defaults.
    public init(migrating old: [RGBAColor], defaults: [RGBAColor]) {
        self.init(old)
        var filled = colors
        for color in ColorFavorites(defaults).colors where filled.count < Self.capacity {
            guard !filled.contains(where: { Self.matches($0, color) }) else { continue }
            filled.append(color)
        }
        colors = filled
    }

    public var isFull: Bool { colors.count >= Self.capacity }

    public func contains(_ color: RGBAColor) -> Bool {
        let opaque = Self.opaque(color)
        return colors.contains { Self.matches($0, opaque) }
    }

    public func index(of color: RGBAColor) -> Int? {
        let opaque = Self.opaque(color)
        return colors.firstIndex { Self.matches($0, opaque) }
    }

    /// Adds to the end. Returns `false` when the list is full or the colour is
    /// already shown.
    @discardableResult
    public mutating func add(_ color: RGBAColor) -> Bool {
        guard !isFull, !contains(color) else { return false }
        colors.append(Self.opaque(color))
        return true
    }

    /// Replaces the slot in place. Returns `false` for an out-of-range index.
    @discardableResult
    public mutating func replace(at index: Int, with color: RGBAColor) -> Bool {
        guard colors.indices.contains(index) else { return false }
        colors[index] = Self.opaque(color)
        return true
    }

    /// Exchanges two slots. Returns `false` for the same slot or an
    /// out-of-range index.
    @discardableResult
    public mutating func swapAt(_ i: Int, _ j: Int) -> Bool {
        guard colors.indices.contains(i), colors.indices.contains(j), i != j else { return false }
        colors.swapAt(i, j)
        return true
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        guard colors.indices.contains(index) else { return false }
        colors.remove(at: index)
        return true
    }

    /// Moves the colour at one slot to another, shifting the colours it passes
    /// along by one. Returns `false` for the same slot or an out-of-range index.
    @discardableResult
    public mutating func move(from source: Int, to destination: Int) -> Bool {
        guard colors.indices.contains(source),
              colors.indices.contains(destination),
              source != destination
        else { return false }
        colors.insert(colors.remove(at: source), at: destination)
        return true
    }

    static func opaque(_ color: RGBAColor) -> RGBAColor {
        var opaque = color
        opaque.a = 1
        return opaque
    }

    static func matches(_ lhs: RGBAColor, _ rhs: RGBAColor) -> Bool {
        abs(lhs.r - rhs.r) < 0.01 && abs(lhs.g - rhs.g) < 0.01 && abs(lhs.b - rhs.b) < 0.01
    }
}

/// The last colours used, newest first. Shared by pen and highlighter, shown
/// as the "Recent" row of the palette popover.
public struct ColorRecents: Codable, Hashable, Sendable {
    public static let capacity = 8

    public private(set) var colors: [RGBAColor]

    public init(_ colors: [RGBAColor] = []) {
        var result: [RGBAColor] = []
        for color in colors {
            let opaque = ColorFavorites.opaque(color)
            guard !result.contains(where: { ColorFavorites.matches($0, opaque) }) else { continue }
            result.append(opaque)
        }
        self.colors = Array(result.prefix(Self.capacity))
    }

    /// Moves the colour to the front, or inserts it there.
    public mutating func record(_ color: RGBAColor) {
        let opaque = ColorFavorites.opaque(color)
        colors.removeAll { ColorFavorites.matches($0, opaque) }
        colors.insert(opaque, at: 0)
        colors = Array(colors.prefix(Self.capacity))
    }
}

/// `#RRGGBB` text, as typed into the palette popover's hex field.
public enum ColorHex {
    public static func string(from color: RGBAColor) -> String {
        func component(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", component(color.r), component(color.g), component(color.b))
    }

    /// Accepts `#RRGGBB` and `RRGGBB`, in either case. `nil` when malformed.
    public static func color(from text: String) -> RGBAColor? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else { return nil }
        return RGBAColor(
            r: Double((value >> 16) & 0xFF) / 255,
            g: Double((value >> 8) & 0xFF) / 255,
            b: Double(value & 0xFF) / 255
        )
    }
}
