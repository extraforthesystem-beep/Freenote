import Foundation

/// Pure, replica-safe union merge for boards.
public enum BoardMerge {
    /// Merges two replicas of a board.
    ///
    /// Items are unioned by ID with the later `updatedAt` winning, tombstones are
    /// unioned, and the result is put in canonical z-order. Tombstoned item payloads
    /// are retained so the merge stays associative; use `Board.visibleItems` to draw.
    ///
    /// The operation is commutative, associative and idempotent on its own output.
    public static func merge(_ lhs: Board, _ rhs: Board) -> Board {
        let encoder = canonicalEncoder()
        var candidates: [UUID: Candidate] = [:]

        for item in lhs.items + rhs.items {
            let data = canonicalData(for: item, using: encoder)
            if let current = candidates[item.id] {
                if isPreferred(item, data, over: current.item, current.canonicalData) {
                    candidates[item.id] = Candidate(item: item, canonicalData: data)
                }
            } else {
                candidates[item.id] = Candidate(item: item, canonicalData: data)
            }
        }

        let winner = boardPreferred(lhs, rhs) ? lhs : rhs
        return Board(
            id: lhs.id.uuidString <= rhs.id.uuidString ? lhs.id : rhs.id,
            title: winner.title,
            items: candidates.values.map(\.item).sorted(by: zOrder),
            deletedItemIDs: lhs.deletedItemIDs.union(rhs.deletedItemIDs),
            createdAt: min(lhs.createdAt, rhs.createdAt),
            updatedAt: max(lhs.updatedAt, rhs.updatedAt),
            schemaVersion: max(lhs.schemaVersion, rhs.schemaVersion)
        )
    }

    private struct Candidate {
        var item: BoardItem
        var canonicalData: Data
    }

    /// Later `updatedAt` wins; an exact tie is broken by canonical bytes so the
    /// result does not depend on argument order.
    private static func isPreferred(
        _ candidate: BoardItem,
        _ candidateData: Data,
        over current: BoardItem,
        _ currentData: Data
    ) -> Bool {
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        if candidateData != currentData {
            return currentData.lexicographicallyPrecedes(candidateData)
        }
        return false
    }

    /// Board metadata follows the later board update, then the greater title.
    private static func boardPreferred(_ lhs: Board, _ rhs: Board) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.title >= rhs.title
    }

    private static func zOrder(_ lhs: BoardItem, _ rhs: BoardItem) -> Bool {
        if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }

    private static func canonicalData(for item: BoardItem, using encoder: JSONEncoder) -> Data {
        (try? encoder.encode(item)) ?? Data()
    }
}
