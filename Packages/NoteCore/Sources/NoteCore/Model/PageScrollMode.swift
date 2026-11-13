import Foundation

/// How a notebook's pages scroll: stacked top to bottom in one continuous
/// scroll (seamless), or one page per screen with a horizontal swipe.
public enum PageScrollMode: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case vertical
    case horizontal

    public var id: String { rawValue }

    /// An unknown value written by a newer build reads as the default rather
    /// than failing the whole manifest.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PageScrollMode(rawValue: raw) ?? .vertical
    }
}
