import CoreGraphics
import Foundation
import NoteCore
import PencilKit

/// What can change about a live `PKStroke` without its id changing, compared
/// without walking its points. A PencilKit path is immutable, so a different
/// path always shows up as a different count or creation date; lasso moves,
/// recolours and the pixel eraser change the transform, ink or mask.
struct StrokeSignature: Equatable {
    let id: UUID
    let pointCount: Int
    let creationDate: Date
    let transform: CGAffineTransform
    let inkType: PKInkingTool.InkType
    let color: CGColor
    let mask: CGPath?
    let randomSeed: UInt32

    init(_ stroke: PKStroke) {
        id = stroke.id
        pointCount = stroke.path.count
        creationDate = stroke.path.creationDate
        transform = stroke.transform
        inkType = stroke.ink.inkType
        color = stroke.ink.color.cgColor
        mask = stroke.mask?.cgPath
        randomSeed = stroke.randomSeed
    }
}

/// A cheap stand-in for comparing two records of the same stroke. It catches
/// every edit the app makes (move, recolour, mask, layer) without comparing
/// every point.
struct RecordSignature: Equatable {
    let layerID: UUID
    let pointCount: Int
    let transform: [Double]
    let tool: StrokeTool
    let maskCount: Int?
    let randomSeed: UInt32

    init(_ record: StrokeRecord) {
        layerID = record.layerID
        pointCount = record.points.count
        transform = record.transform
        tool = record.tool
        maskCount = record.mask?.count
        randomSeed = record.randomSeed
    }
}

/// Converts a canvas's strokes to records, converting only strokes it has not
/// seen in their current form. Every other stroke reuses its earlier record,
/// so a change costs one conversion instead of one per stroke on the page.
public final class IncrementalStrokeConverter {
    private struct Entry {
        var signature: StrokeSignature
        var record: StrokeRecord
    }

    private var entries: [UUID: Entry] = [:]
    private var lastSignatures: [StrokeSignature] = []

    /// How many strokes have been converted from scratch. For tests.
    public private(set) var conversionCount = 0

    public init() {}

    /// Remembers `records` as the source of `strokes` (matched by id), so they
    /// are returned verbatim instead of re-encoded. Use after putting records
    /// into a canvas: the round trip through PencilKit is not bit-exact, and
    /// the stored record is the truth.
    public func seed(strokes: [PKStroke], records: [StrokeRecord]) {
        var byID: [UUID: StrokeRecord] = [:]
        for record in records { byID[record.id] = record }
        entries = [:]
        var signatures: [StrokeSignature] = []
        signatures.reserveCapacity(strokes.count)
        for stroke in strokes {
            let signature = StrokeSignature(stroke)
            signatures.append(signature)
            if let record = byID[stroke.id] {
                entries[stroke.id] = Entry(signature: signature, record: record)
            }
        }
        lastSignatures = signatures
    }

    /// The records for `strokes`, or nil when nothing changed since the last
    /// call or seed.
    ///
    /// - Parameter layerID: the layer of a stroke; called for every stroke.
    public func changedRecords(
        from strokes: [PKStroke],
        layerID: (UUID) -> UUID
    ) -> [StrokeRecord]? {
        let signatures = strokes.map(StrokeSignature.init)
        guard signatures != lastSignatures else { return nil }
        lastSignatures = signatures
        return records(from: strokes, signatures: signatures, layerID: layerID)
    }

    /// The records for `strokes`, converting only the ones not already known.
    public func records(from strokes: [PKStroke], layerID: (UUID) -> UUID) -> [StrokeRecord] {
        records(from: strokes, signatures: strokes.map(StrokeSignature.init), layerID: layerID)
    }

    private func records(
        from strokes: [PKStroke],
        signatures: [StrokeSignature],
        layerID: (UUID) -> UUID
    ) -> [StrokeRecord] {
        // `entries` is updated in place rather than rebuilt: a rebuild copies
        // every record into a new dictionary for each finished stroke.
        var records: [StrokeRecord] = []
        records.reserveCapacity(strokes.count)
        for (stroke, signature) in zip(strokes, signatures) {
            let layer = layerID(stroke.id)
            if let entry = entries[stroke.id], entry.signature == signature {
                var record = entry.record
                if record.layerID != layer {
                    record.layerID = layer
                    entries[stroke.id]?.record.layerID = layer
                }
                records.append(record)
            } else {
                let record = StrokeCodec.record(from: stroke, layerID: layer)
                conversionCount += 1
                entries[stroke.id] = Entry(signature: signature, record: record)
                records.append(record)
            }
        }
        // Drop strokes that are gone (erased, undone). Every live stroke has
        // an entry, so a larger dictionary means some are stale.
        if entries.count > strokes.count {
            let live = Set(strokes.map(\.id))
            entries = entries.filter { live.contains($0.key) }
        }
        return records
    }
}
