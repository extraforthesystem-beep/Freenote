import Foundation
import Testing
@testable import NoteCore

@Suite("Page file codec")
struct PageCodecTests {
    /// 200 random pages, each encoded, decoded and re-encoded: equal values and
    /// byte-identical bytes.
    @Test func randomPagesRoundTripExactly() throws {
        var rng = SplitMix64(seed: 0x0C0F_FEE1)
        for index in 0..<200 {
            let page = randomPage(&rng)
            let encoded = try PageCodec.encode(page)
            let decoded = try PageCodec.decode(encoded)
            #expect(decoded == page, "page \(index) did not round-trip")
            let reencoded = try PageCodec.encode(decoded)
            #expect(reencoded == encoded, "page \(index) did not re-encode to the same bytes")
        }
    }

    /// Regression: the decompression buffer used to be returned when it filled,
    /// truncating a page whose JSON was more than eight times its compressed size.
    @Test func largeCompressedPageIsNotTruncated() throws {
        var rng = SplitMix64(seed: 0xB1_6B00)
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let strokes = (0..<10).map { _ in
            randomStroke(&rng, layerID: layer.id, pointCount: 200)
        }
        let page = Page(
            id: UUID(),
            width: 612,
            height: 792,
            template: .blank,
            layers: [layer],
            strokes: strokes
        )
        let encoded = try PageCodec.encode(page)
        let decoded = try PageCodec.decode(encoded)
        #expect(decoded == page)
        #expect(decoded.strokes.count == 10)
    }

    @Test func emptyPageRoundTrips() throws {
        let page = Page(id: UUID(), width: 612, height: 792, template: .blank)
        let decoded = try PageCodec.decode(try PageCodec.encode(page))
        #expect(decoded == page)
        #expect(decoded.layers.count == 1)
    }

    @Test func singlePointStrokeRoundTrips() throws {
        var rng = SplitMix64(seed: 0xD0_7001)
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let page = Page(
            id: UUID(),
            width: 1_024,
            height: 1_366,
            template: .blank,
            layers: [layer],
            strokes: [randomStroke(&rng, layerID: layer.id, pointCount: 1)]
        )
        #expect(page.strokes[0].points.count == 1)

        let encoded = try PageCodec.encode(page)
        let decoded = try PageCodec.decode(encoded)
        #expect(decoded == page)
        let reencoded = try PageCodec.encode(decoded)
        #expect(reencoded == encoded)
    }

    /// A `Set` iterates in no fixed order; the codec must still produce one byte
    /// sequence for one value.
    @Test func deletedStrokeSetOrderDoesNotChangeBytes() throws {
        var rng = SplitMix64(seed: 0x5E7_0001)
        let ids = (0..<20).map { _ in randomUUID(&rng) }

        let forward = Page(
            id: UUID(),
            width: 100,
            height: 100,
            template: .blank,
            layers: [Page.Layer(id: UUID(), name: "Layer 1")],
            deletedStrokeIDs: Set(ids)
        )
        let backward = Page(
            id: forward.id,
            width: 100,
            height: 100,
            template: .blank,
            layers: forward.layers,
            deletedStrokeIDs: Set(ids.reversed())
        )

        #expect(forward == backward)
        let firstBytes = try PageCodec.encode(forward)
        let secondBytes = try PageCodec.encode(backward)
        #expect(firstBytes == secondBytes)
    }

    @Test func folderTreeEncodingIsDeterministic() throws {
        var rng = SplitMix64(seed: 0xF01_DE45)
        let notebookIDs = (0..<12).map { _ in randomUUID(&rng) }
        let folderIDs = (0..<4).map { _ in randomUUID(&rng) }
        let folders = folderIDs.map { Folder(id: $0, name: "Folder \($0.uuidString.prefix(4))") }

        var pairs: [(UUID, UUID)] = []
        for notebookID in notebookIDs {
            pairs.append((notebookID, folderIDs.randomElement(using: &rng) ?? folderIDs[0]))
        }
        var tagPairs: [(UUID, [String])] = []
        for notebookID in notebookIDs.prefix(6) {
            tagPairs.append((notebookID, Array(["a", "b", "c"].prefix(rng.int(in: 0...3)))))
        }

        var tree = FolderTree()
        tree.folders = folders
        tree.notebookFolder = Dictionary(uniqueKeysWithValues: pairs)
        tree.tags = Dictionary(uniqueKeysWithValues: tagPairs)
        tree.favourites = Set(notebookIDs.prefix(5))

        // The same value, assembled in the opposite order.
        var rebuilt = FolderTree()
        rebuilt.folders = folders
        rebuilt.notebookFolder = Dictionary(uniqueKeysWithValues: pairs.reversed())
        rebuilt.tags = Dictionary(uniqueKeysWithValues: tagPairs.reversed())
        rebuilt.favourites = Set(notebookIDs.prefix(5).reversed())

        #expect(tree == rebuilt)
        let first = try FolderTreeCodec.encode(tree)
        let second = try FolderTreeCodec.encode(rebuilt)
        #expect(first == second)

        let decoded = try FolderTreeCodec.decode(first)
        #expect(decoded == tree)
    }

    @Test func timestampsRoundTripToTheNanosecond() throws {
        var rng = SplitMix64(seed: 0x71_3E_57A_9B)
        var dates: [Date] = [
            Date(),
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSinceReferenceDate: 0),
            Date(timeIntervalSince1970: 1),
        ]
        for _ in 0..<2_000 {
            dates.append(randomDate(&rng))
        }
        for _ in 0..<2_000 {
            // Full 53-bit precision, the hardest case for a text format.
            dates.append(Date(timeIntervalSinceReferenceDate: rng.unitDouble() * 2_000_000_000))
        }

        for date in dates {
            let text = ISODate.string(from: date)
            let decoded = try ISODate.date(from: text)
            #expect(decoded == date, "\(text) did not round-trip")
            #expect(ISODate.string(from: decoded) == text)
        }
    }

    @Test func futureSchemaVersionIsRejectedBeforeAnythingIsDecoded() throws {
        let future = Data("{ \"schemaVersion\": \(SchemaVersion.current + 1) }".utf8)

        // Plain JSON documents.
        #expect(throwsUnsupportedSchema { _ = try ManifestCodec.decode(future) })
        #expect(throwsUnsupportedSchema { _ = try FolderTreeCodec.decode(future) })
        #expect(throwsUnsupportedSchema { _ = try LibraryInfoCodec.decode(future) })

        // A page file, compressed the way the format stores it.
        let compressed = try #require(zlibCompress(future))
        #expect(throwsUnsupportedSchema { _ = try PageCodec.decode(compressed) })
    }

    @Test func currentSchemaVersionIsAccepted() throws {
        let page = Page(id: UUID(), width: 10, height: 10, template: .blank)
        let decoded = try PageCodec.decode(try PageCodec.encode(page))
        #expect(decoded.schemaVersion == SchemaVersion.current)
        #expect(decoded == page)
    }

    @Test func truncatedPageDataIsCorrupt() throws {
        var rng = SplitMix64(seed: 0x7_2A_11C)
        let page = randomPage(&rng, maxStrokes: 3, maxPoints: 5)
        let encoded = try PageCodec.encode(page)
        let truncated = encoded.prefix(encoded.count / 2)
        #expect(throwsCorruptFile { _ = try PageCodec.decode(truncated) })
        #expect(throwsCorruptFile { _ = try PageCodec.decode(Data()) })
        #expect(throwsCorruptFile { _ = try PageCodec.decode(encoded.prefix(0)) })
    }

    @Test func garbageDataIsCorrupt() throws {
        var rng = SplitMix64(seed: 0x9AB_1E)
        for _ in 0..<50 {
            let length = rng.int(in: 1...2_000)
            var bytes = Data(count: length)
            for index in 0..<length {
                bytes[index] = UInt8(truncatingIfNeeded: rng.next())
            }
            #expect(throwsCorruptFile { _ = try PageCodec.decode(bytes) })
        }
    }

    @Test func validCompressionOfSomethingElseIsCorrupt() throws {
        let compressed = try #require(zlibCompress(Data("this is not a page".utf8)))
        #expect(throwsCorruptFile { _ = try PageCodec.decode(compressed) })
    }

    @Test func truncatedAndGarbageDocumentsAreCorrupt() throws {
        var rng = SplitMix64(seed: 0xB0_0B1E)
        let manifest = NotebookManifest(
            id: randomUUID(&rng),
            title: "Notes",
            pageOrder: [randomUUID(&rng), randomUUID(&rng)],
            createdAt: randomDate(&rng),
            updatedAt: randomDate(&rng)
        )
        let encoded = try ManifestCodec.encode(manifest)
        #expect(throwsCorruptFile { _ = try ManifestCodec.decode(encoded.prefix(encoded.count / 2)) })
        #expect(throwsCorruptFile { _ = try ManifestCodec.decode(Data("{".utf8)) })
        #expect(throwsCorruptFile { _ = try FolderTreeCodec.decode(Data("nonsense".utf8)) })
        #expect(throwsCorruptFile { _ = try LibraryInfoCodec.decode(Data("[]".utf8)) })
    }

    @Test func manifestIsPrettyPrintedAndSorted() throws {
        var rng = SplitMix64(seed: 0x5_0F7)
        let manifest = NotebookManifest(
            id: randomUUID(&rng),
            title: "Title",
            pageOrder: [randomUUID(&rng)],
            createdAt: randomDate(&rng),
            updatedAt: randomDate(&rng)
        )
        let data = try ManifestCodec.encode(manifest)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\n"))
        #expect(text.contains("\"schemaVersion\" : \(SchemaVersion.current)"))
        let createdAtIndex = try #require(text.range(of: "\"createdAt\""))
        let titleIndex = try #require(text.range(of: "\"title\""))
        #expect(createdAtIndex.lowerBound < titleIndex.lowerBound, "keys are not sorted")
        let decoded = try ManifestCodec.decode(data)
        #expect(decoded == manifest)
    }
}
