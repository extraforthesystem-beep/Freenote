import Compression
import Foundation
@testable import NoteCore

// MARK: - Deterministic randomness

/// SplitMix64: small, fast and fully deterministic, so a failure reproduces from
/// the seed alone.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// A value rounded to six decimals, which keeps generated doubles exact in JSON.
    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        let value = range.lowerBound + (range.upperBound - range.lowerBound) * unit
        return (value * 1_000_000).rounded() / 1_000_000
    }

    /// A full-precision value in `0..<1`, no rounding.
    mutating func unitDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func chance(_ probability: Double) -> Bool {
        double(in: 0...1) < probability
    }
}

// MARK: - Generators

func randomUUID(_ rng: inout SplitMix64) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    for index in bytes.indices {
        bytes[index] = UInt8(truncatingIfNeeded: rng.next() >> 33)
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(
        uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
    )
}

func randomDate(_ rng: inout SplitMix64) -> Date {
    let seconds = Double(rng.int(in: 0...2_000_000_000))
    let fraction = rng.double(in: 0...0.999_999)
    return Date(timeIntervalSince1970: seconds + fraction)
}

func randomColor(_ rng: inout SplitMix64) -> RGBAColor {
    RGBAColor(
        r: rng.double(in: 0...1),
        g: rng.double(in: 0...1),
        b: rng.double(in: 0...1),
        a: rng.double(in: 0...1)
    )
}

func randomStrokePoint(_ rng: inout SplitMix64, index: Int) -> StrokePoint {
    StrokePoint(
        x: rng.double(in: -1_000...2_000),
        y: rng.double(in: -1_000...2_000),
        timeOffset: Double(index) * rng.double(in: 0.001...0.05),
        width: rng.double(in: 0.5...40),
        height: rng.double(in: 0.5...40),
        opacity: rng.double(in: 0...1),
        force: rng.double(in: 0...1),
        azimuth: rng.double(in: -3.14...3.14),
        altitude: rng.double(in: 0...1.57),
        secondaryScale: rng.double(in: 0.25...1)
    )
}

func randomPathElement(_ rng: inout SplitMix64) -> PathElement {
    switch rng.int(in: 0...4) {
    case 0:
        return .move(x: rng.double(in: -100...100), y: rng.double(in: -100...100))
    case 1:
        return .line(x: rng.double(in: -100...100), y: rng.double(in: -100...100))
    case 2:
        return .quad(
            cx: rng.double(in: -100...100),
            cy: rng.double(in: -100...100),
            x: rng.double(in: -100...100),
            y: rng.double(in: -100...100)
        )
    case 3:
        return .cubic(
            c1x: rng.double(in: -100...100),
            c1y: rng.double(in: -100...100),
            c2x: rng.double(in: -100...100),
            c2y: rng.double(in: -100...100),
            x: rng.double(in: -100...100),
            y: rng.double(in: -100...100)
        )
    default:
        return .close
    }
}

func randomStroke(_ rng: inout SplitMix64, layerID: UUID, pointCount: Int? = nil) -> StrokeRecord {
    let count = pointCount ?? rng.int(in: 0...60)
    var points: [StrokePoint] = []
    points.reserveCapacity(count)
    for index in 0..<count {
        points.append(randomStrokePoint(&rng, index: index))
    }
    let mask: [PathElement]? = rng.chance(0.15)
        ? (0..<rng.int(in: 1...8)).map { _ in randomPathElement(&rng) }
        : nil
    return StrokeRecord(
        id: randomUUID(&rng),
        layerID: layerID,
        tool: StrokeTool(
            engine: rng.chance(0.5) ? "pencilkit" : "metal",
            inkType: ["pen", "pencil", "marker", "fountainPen"].randomElement(using: &rng) ?? "pen",
            color: randomColor(&rng),
            width: rng.double(in: 0.5...30)
        ),
        createdAt: randomDate(&rng),
        transform: rng.chance(0.7) ? StrokeRecord.identityTransform : (0..<6).map { _ in
            rng.double(in: -2...2)
        },
        randomSeed: UInt32(truncatingIfNeeded: rng.next()),
        mask: mask,
        renderGroupID: rng.chance(0.2) ? randomUUID(&rng) : nil,
        points: points
    )
}

func randomElementContent(_ rng: inout SplitMix64) -> ElementContent {
    switch rng.int(in: 0...3) {
    case 0:
        return .text(
            ["hello", "notes", "1 + 1 = 2", ""].randomElement(using: &rng) ?? "",
            fontName: "Helvetica",
            fontSize: rng.double(in: 8...72),
            color: randomColor(&rng)
        )
    case 1:
        return .image(assetName: "\(String(format: "%016llx", rng.next())).png")
    case 2:
        return .shape(
            kind: ["rectangle", "ellipse", "arrow"].randomElement(using: &rng) ?? "rectangle",
            stroke: randomColor(&rng),
            fill: rng.chance(0.5) ? randomColor(&rng) : nil,
            lineWidth: rng.double(in: 0.5...12)
        )
    default:
        return .pdfPage(assetName: "\(String(format: "%016llx", rng.next())).pdf", pageIndex: rng.int(in: 0...500))
    }
}

func randomElement(_ rng: inout SplitMix64, layerID: UUID) -> PageElement {
    PageElement(
        id: randomUUID(&rng),
        layerID: layerID,
        frame: ElementFrame(
            x: rng.double(in: 0...800),
            y: rng.double(in: 0...1_000),
            width: rng.double(in: 1...400),
            height: rng.double(in: 1...400),
            rotation: rng.double(in: -3.14...3.14)
        ),
        zIndex: rng.int(in: -20...20),
        updatedAt: randomDate(&rng),
        content: randomElementContent(&rng)
    )
}

func randomTemplate(_ rng: inout SplitMix64) -> PageTemplate {
    PageTemplate(
        kind: ["blank", "ruled", "grid", "dotted"].randomElement(using: &rng) ?? "blank",
        spacing: rng.double(in: 0...64),
        lineColor: randomColor(&rng),
        paperColor: randomColor(&rng)
    )
}

/// A page with up to `maxStrokes` strokes of up to `maxPoints` points each.
func randomPage(_ rng: inout SplitMix64, maxStrokes: Int = 300, maxPoints: Int = 60) -> Page {
    let layers = (0..<rng.int(in: 1...3)).map { _ in
        Page.Layer(
            id: randomUUID(&rng),
            name: ["Layer 1", "Ink", "Highlights"].randomElement(using: &rng) ?? "Layer",
            isVisible: rng.chance(0.8),
            isLocked: rng.chance(0.2)
        )
    }
    let layerIDs = layers.map(\.id)

    let strokes = (0..<rng.int(in: 0...maxStrokes)).map { _ in
        randomStroke(
            &rng,
            layerID: layerIDs.randomElement(using: &rng) ?? layerIDs[0],
            pointCount: rng.int(in: 0...maxPoints)
        )
    }
    let elements = (0..<rng.int(in: 0...12)).map { _ in
        randomElement(&rng, layerID: layerIDs.randomElement(using: &rng) ?? layerIDs[0])
    }
    let deleted = Set((0..<rng.int(in: 0...8)).map { _ in randomUUID(&rng) })

    return Page(
        id: randomUUID(&rng),
        width: rng.double(in: 200...2_000),
        height: rng.double(in: 200...2_000),
        template: randomTemplate(&rng),
        layers: layers,
        strokes: strokes,
        elements: elements,
        deletedStrokeIDs: deleted
    )
}

// MARK: - Temporary libraries

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("NoteCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Every regular file under `root`, keyed by path relative to `root`.
func captureDirectory(_ root: URL) throws -> [String: Data] {
    let manager = FileManager.default
    guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
        return [:]
    }
    let rootPath = root.standardizedFileURL.path
    var files: [String: Data] = [:]
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        var path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath + "/") {
            path = String(path.dropFirst(rootPath.count + 1))
        }
        files[path] = try Data(contentsOf: url)
    }
    return files
}

func pageFileIDs(in pagesDirectory: URL) throws -> Set<UUID> {
    let manager = FileManager.default
    guard manager.fileExists(atPath: pagesDirectory.path) else { return [] }
    let names = try manager.contentsOfDirectory(atPath: pagesDirectory.path)
    var ids = Set<UUID>()
    for name in names where name.hasSuffix(".page") {
        let stem = String(name.dropLast(".page".count))
        if let id = UUID(uuidString: stem) { ids.insert(id) }
    }
    return ids
}

// MARK: - Raw file helpers

/// Compresses with zlib directly, for tests that need a hand-built `.page` file.
func zlibCompress(_ input: Data) -> Data? {
    var capacity = input.count + 1_024
    while capacity <= 64 * 1_024 * 1_024 {
        var output = Data(count: capacity)
        let written: Int? = output.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return input.withUnsafeBytes { source in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return compression_encode_buffer(
                    destinationBase,
                    capacity,
                    sourceBase,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        if let written, written > 0 {
            return output.prefix(written)
        }
        capacity *= 2
    }
    return nil
}

/// True when `body` throws `NoteCoreError.corruptFile`.
func throwsCorruptFile(_ body: () throws -> Void) -> Bool {
    do {
        try body()
        return false
    } catch let error as NoteCoreError {
        if case .corruptFile = error { return true }
        return false
    } catch {
        return false
    }
}

/// True when `body` throws `NoteCoreError.unsupportedSchemaVersion` with these values.
func throwsUnsupportedSchema(_ body: () throws -> Void) -> Bool {
    do {
        try body()
        return false
    } catch let error as NoteCoreError {
        if case let .unsupportedSchemaVersion(found, supported) = error {
            return found == SchemaVersion.current + 1 && supported == SchemaVersion.current
        }
        return false
    } catch {
        return false
    }
}

// MARK: - Expected on-disk paths

func notebookDirectory(root: URL, notebookID: UUID) -> URL {
    root.appendingPathComponent("notebooks").appendingPathComponent(notebookID.uuidString.lowercased())
}

func pagesDirectory(root: URL, notebookID: UUID) -> URL {
    notebookDirectory(root: root, notebookID: notebookID).appendingPathComponent("pages")
}

func assetsDirectory(root: URL, notebookID: UUID) -> URL {
    notebookDirectory(root: root, notebookID: notebookID).appendingPathComponent("assets")
}

func pageFile(root: URL, notebookID: UUID, pageID: UUID) -> URL {
    pagesDirectory(root: root, notebookID: notebookID)
        .appendingPathComponent(pageID.uuidString.lowercased() + ".page")
}
