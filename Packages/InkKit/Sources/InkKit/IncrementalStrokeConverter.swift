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

    private struct State {
        var entries: [UUID: Entry]
        var lastSignatures: [StrokeSignature]
        var lastIDs: [UUID]
        var lastRecords: [StrokeRecord]
        var conversionCount: Int
    }

    private var entries: [UUID: Entry] = [:]
    private var lastSignatures: [StrokeSignature] = []
    /// The ids and records of the last result, in order, kept beside
    /// `lastSignatures` so an appended suffix can extend the result without
    /// rebuilding the whole page.
    private var lastIDs: [UUID] = []
    private var lastRecords: [StrokeRecord] = []

    /// Whether the last non-nil `changedRecords` result came from the
    /// append-only fast path.
    public private(set) var lastChangeWasAppendOnly = false
    /// How many records at the end of the last result the fast path added.
    public private(set) var lastAppendedRecordCount = 0

    /// How many strokes have been converted from scratch. For tests.
    public private(set) var conversionCount = 0

    /// Off unless the process asks for it: comparing every fast-path result
    /// with the full path is far too expensive to run by default. Read once.
    private static let verifiesFastPath =
        ProcessInfo.processInfo.environment["NOTEAPP_VERIFY_INK"] == "1"

    public init() {}

    /// Remembers `records` as the source of `strokes` (matched by id), so they
    /// are returned verbatim instead of re-encoded. Use after putting records
    /// into a canvas: the round trip through PencilKit is not bit-exact, and
    /// the stored record is the truth.
    public func seed(strokes: [PKStroke], records: [StrokeRecord]) {
        var byID: [UUID: StrokeRecord] = [:]
        for record in records { byID[record.id] = record }
        entries = [:]
        // Slack so the next few appends add entries without rehashing the page.
        entries.reserveCapacity(strokes.count + 16)
        var signatures: [StrokeSignature] = []
        var ids: [UUID] = []
        var matched: [StrokeRecord] = []
        signatures.reserveCapacity(strokes.count)
        ids.reserveCapacity(strokes.count)
        matched.reserveCapacity(strokes.count)
        for stroke in strokes {
            let signature = StrokeSignature(stroke)
            signatures.append(signature)
            ids.append(stroke.id)
            if let record = byID[stroke.id] {
                entries[stroke.id] = Entry(signature: signature, record: record)
                matched.append(record)
            }
        }
        lastSignatures = signatures
        lastIDs = ids
        // A missing record leaves `matched` shorter than `ids`, which disables
        // the fast path until a full conversion fills both in.
        lastRecords = matched
        reserveAppendCapacity()
        lastChangeWasAppendOnly = false
        lastAppendedRecordCount = 0
    }

    /// Keeps the next few appends from reallocating and copying the whole
    /// page's signatures and records. The copy is harmless on the full paths,
    /// which are already linear, but the fast path must not pay it.
    private func reserveAppendCapacity() {
        let target = lastSignatures.count + 16
        lastSignatures.reserveCapacity(target)
        lastIDs.reserveCapacity(target)
        lastRecords.reserveCapacity(target)
    }

    /// The records for `strokes`, or nil when nothing changed since the last
    /// call or seed.
    ///
    /// - Parameter layerID: the layer of a stroke. The append fast path calls
    ///   it only for the new strokes; every other path calls it for all.
    /// - Parameter appendOnly: pass true only when the change is known to have
    ///   added strokes at the end and changed nothing else: the canvas is in
    ///   ink mode, the change is not an undo or redo, and no programmatic
    ///   rewrite produced it other than the decoration that replaces just the
    ///   new strokes. The converter then converts only the new suffix. If the
    ///   ids before the suffix differ, the arrays are shorter or the same
    ///   length, or anything else does not match, it falls back to the full
    ///   path unchanged.
    public func changedRecords(
        from strokes: [PKStroke],
        layerID: (UUID) -> UUID,
        appendOnly: Bool = false
    ) -> [StrokeRecord]? {
        lastChangeWasAppendOnly = false
        lastAppendedRecordCount = 0
        if appendOnly {
            let before = Self.verifiesFastPath ? state : nil
            if let appended = appendedRecords(from: strokes, layerID: layerID) {
                if let before {
                    verify(appended, against: before, strokes: strokes, layerID: layerID)
                }
                return appended
            }
        }
        let signatures = strokes.map(StrokeSignature.init)
        guard signatures != lastSignatures else { return nil }
        lastSignatures = signatures
        let result = records(from: strokes, signatures: signatures, layerID: layerID)
        lastIDs = result.map(\.id)
        lastRecords = result
        return result
    }

    /// The records for `strokes`, converting only the ones not already known.
    public func records(from strokes: [PKStroke], layerID: (UUID) -> UUID) -> [StrokeRecord] {
        let signatures = strokes.map(StrokeSignature.init)
        let result = records(from: strokes, signatures: signatures, layerID: layerID)
        lastSignatures = signatures
        lastIDs = result.map(\.id)
        lastRecords = result
        lastChangeWasAppendOnly = false
        lastAppendedRecordCount = 0
        return result
    }

    /// Extends the last result by the strokes after its prefix, or returns nil
    /// when the caller's append-only claim does not hold.
    private func appendedRecords(
        from strokes: [PKStroke],
        layerID: (UUID) -> UUID
    ) -> [StrokeRecord]? {
        let previousCount = lastIDs.count
        guard previousCount == lastSignatures.count,
              lastRecords.count == previousCount,
              strokes.count > previousCount
        else { return nil }
        // Element-wise id equality, as the caller's contract promises: the
        // prefix is the page as it was, and only strokes after it are new.
        for index in 0..<previousCount where strokes[index].id != lastIDs[index] {
            return nil
        }
        let addedCount = strokes.count - previousCount
        for stroke in strokes[previousCount...] {
            let signature = StrokeSignature(stroke)
            lastSignatures.append(signature)
            let layer = layerID(stroke.id)
            let record: StrokeRecord
            if let entry = entries[stroke.id], entry.signature == signature {
                var reused = entry.record
                if reused.layerID != layer {
                    reused.layerID = layer
                    entries[stroke.id]?.record.layerID = layer
                }
                record = reused
            } else {
                record = StrokeCodec.record(from: stroke, layerID: layer)
                conversionCount += 1
                entries[stroke.id] = Entry(signature: signature, record: record)
            }
            lastRecords.append(record)
            lastIDs.append(stroke.id)
        }
        lastChangeWasAppendOnly = true
        lastAppendedRecordCount = addedCount
        return lastRecords
    }

    private var state: State {
        State(
            entries: entries,
            lastSignatures: lastSignatures,
            lastIDs: lastIDs,
            lastRecords: lastRecords,
            conversionCount: conversionCount
        )
    }

    /// Off by default (`NOTEAPP_VERIFY_INK=1` turns it on): recomputes the
    /// result on a scratch converter with the state from before the fast path
    /// and fails loudly when the two disagree.
    private func verify(
        _ fast: [StrokeRecord],
        against before: State,
        strokes: [PKStroke],
        layerID: (UUID) -> UUID
    ) {
        let scratch = IncrementalStrokeConverter()
        scratch.entries = before.entries
        scratch.lastSignatures = before.lastSignatures
        scratch.lastIDs = before.lastIDs
        scratch.lastRecords = before.lastRecords
        scratch.conversionCount = before.conversionCount
        let full = scratch.changedRecords(from: strokes, layerID: layerID)
        if fast != full {
            assertionFailure("IncrementalStrokeConverter append fast path differs from the full path")
        }
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
