import BoardKit
import CoreGraphics
import Foundation
import NoteCore

// MARK: - Deterministic randomness

/// SplitMix64: small, fast and fully deterministic, so failures reproduce from a seed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
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

    mutating func chance(_ probability: Double) -> Bool {
        double(in: 0...1) < probability
    }
}

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

// MARK: - Generators

func makeStroke(_ rng: inout SplitMix64) -> StrokeRecord {
    let pointCount = rng.int(in: 1...4)
    var points: [StrokePoint] = []
    for index in 0..<pointCount {
        points.append(
            StrokePoint(
                x: rng.double(in: -400...400),
                y: rng.double(in: -400...400),
                timeOffset: Double(index) * 0.01,
                width: 2,
                height: 2,
                opacity: 1,
                force: 0.5,
                azimuth: 0,
                altitude: .pi / 2,
                secondaryScale: 1
            )
        )
    }
    return StrokeRecord(
        id: randomUUID(&rng),
        layerID: randomUUID(&rng),
        tool: StrokeTool(
            engine: "metal",
            inkType: "pen",
            color: randomColor(&rng),
            width: rng.double(in: 1...6)
        ),
        createdAt: randomDate(&rng),
        randomSeed: UInt32(truncatingIfNeeded: rng.next()),
        points: points
    )
}

func randomFrame(_ rng: inout SplitMix64) -> CGRect {
    CGRect(
        x: rng.double(in: -1_000...1_000),
        y: rng.double(in: -1_000...1_000),
        width: rng.double(in: 10...300),
        height: rng.double(in: 10...300)
    )
}

func randomItem(
    _ rng: inout SplitMix64,
    id: UUID? = nil,
    zIndex: Int? = nil
) -> BoardItem {
    let createdAt = randomDate(&rng)
    let updatedAt = createdAt.addingTimeInterval(rng.double(in: 0...100_000))
    let content: BoardItemContent
    switch rng.int(in: 0...5) {
    case 0:
        let strokeCount = rng.int(in: 0...2)
        content = .ink(strokes: (0..<strokeCount).map { _ in makeStroke(&rng) })
    case 1:
        content = .image(
            assetName: "asset-\(rng.int(in: 0...99))",
            frame: randomFrame(&rng)
        )
    case 2:
        content = .text(
            "text-\(rng.int(in: 0...99))",
            frame: randomFrame(&rng),
            fontSize: rng.double(in: 8...48),
            color: randomColor(&rng)
        )
    case 3:
        content = .shape(
            kind: BoardShapeKind.allCases.randomElement(using: &rng) ?? .rectangle,
            frame: randomFrame(&rng),
            strokeColor: randomColor(&rng),
            fillColor: rng.chance(0.5) ? randomColor(&rng) : nil,
            lineWidth: rng.double(in: 0.5...8)
        )
    case 4:
        content = .sticky(
            "note-\(rng.int(in: 0...99))",
            frame: randomFrame(&rng),
            color: randomColor(&rng)
        )
    default:
        content = .connector(
            fromItemID: randomUUID(&rng),
            toItemID: randomUUID(&rng),
            style: BoardConnectorStyle.allCases.randomElement(using: &rng) ?? .straight
        )
    }
    return BoardItem(
        id: id ?? randomUUID(&rng),
        zIndex: zIndex ?? rng.int(in: -5...20),
        isLocked: rng.chance(0.15),
        createdAt: createdAt,
        updatedAt: updatedAt,
        content: content
    )
}

/// Builds a random replica. `pool` is shared between replicas so item IDs overlap.
func randomBoard(
    _ rng: inout SplitMix64,
    boardID: UUID,
    pool: [UUID]
) -> Board {
    let count = rng.int(in: 0...min(8, pool.count))
    let chosen = Array(pool.shuffled(using: &rng).prefix(count))
    var items: [BoardItem] = []
    for id in chosen {
        items.append(randomItem(&rng, id: id))
    }

    var deleted = Set<UUID>()
    for _ in 0..<rng.int(in: 0...3) {
        if let id = pool.randomElement(using: &rng) {
            deleted.insert(id)
        }
    }

    let createdAt = randomDate(&rng)
    let updatedAt = createdAt.addingTimeInterval(rng.double(in: 0...100_000))
    return Board(
        id: boardID,
        title: "Board \(rng.int(in: 0...5))",
        items: items,
        deletedItemIDs: deleted,
        createdAt: createdAt,
        updatedAt: updatedAt,
        schemaVersion: Board.currentSchemaVersion
    )
}
