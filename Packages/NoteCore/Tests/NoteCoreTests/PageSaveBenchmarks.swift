// Timing benchmark for `LibraryStore.savePage` on a realistic large page.
// Off by default so the suite stays fast; run it with:
//
//     NOTEAPP_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter PageSaveBenchmarks
//
// Every number is the median of five runs and is reported to the test log only;
// nothing here asserts on time, so a slow machine cannot fail CI.

import CryptoKit
import Darwin
import Foundation
import Testing
@testable import NoteCore

@Suite("Page save benchmarks", .enabled(if: ProcessInfo.processInfo.environment["NOTEAPP_BENCH"] != nil))
struct PageSaveBenchmarks {
    static let strokeCount = 2_000
    static let pointsPerStroke = 100

    // MARK: - The page

    /// 2,000 strokes of 100 points, every `StrokePoint` field filled and the
    /// optional stroke fields used the way a PencilKit page uses them.
    static func makePage() -> Page {
        var rng = SplitMix64(seed: 0x2_000_57_0C_45)
        let layer = Page.Layer(id: randomUUID(&rng), name: "Ink")
        var strokes: [StrokeRecord] = []
        strokes.reserveCapacity(strokeCount)

        for index in 0..<strokeCount {
            var points: [StrokePoint] = []
            points.reserveCapacity(pointsPerStroke)
            for point in 0..<pointsPerStroke {
                points.append(
                    StrokePoint(
                        x: rng.double(in: 0...1_024),
                        y: rng.double(in: 0...1_366),
                        timeOffset: Double(point) / 240,
                        width: rng.double(in: 1...12),
                        height: rng.double(in: 1...12),
                        opacity: rng.double(in: 0.2...1),
                        force: rng.double(in: 0...1),
                        azimuth: rng.double(in: -3...3),
                        altitude: rng.double(in: 0...1.57),
                        secondaryScale: rng.double(in: 0.5...1),
                        threshold: rng.double(in: 0...0.5),
                        lateralJitter: rng.double(in: -1...1)
                    )
                )
            }

            strokes.append(
                StrokeRecord(
                    id: randomUUID(&rng),
                    layerID: layer.id,
                    tool: StrokeTool(
                        engine: "pencilkit",
                        inkType: index.isMultiple(of: 3) ? "pencil" : "pen",
                        color: randomColor(&rng),
                        width: rng.double(in: 0.5...20)
                    ),
                    createdAt: randomDate(&rng),
                    transform: StrokeRecord.identityTransform,
                    randomSeed: UInt32(truncatingIfNeeded: rng.next()),
                    mask: index.isMultiple(of: 4) ? [.move(x: 1, y: 2), .line(x: 3, y: 4)] : nil,
                    renderGroupID: index.isMultiple(of: 5) ? randomUUID(&rng) : nil,
                    pathID: randomUUID(&rng),
                    grainOffset: index.isMultiple(of: 7)
                        ? .init(x: rng.double(in: 0...4), y: rng.double(in: 0...4))
                        : nil,
                    points: points
                )
            )
        }

        return Page(
            id: UUID(uuidString: "5EAF0000-0000-4000-8000-00000000BEEF")!,
            width: 1_024,
            height: 1_366,
            template: .blank,
            layers: [layer],
            strokes: strokes
        )
    }

    // MARK: - Timing

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
    }

    private static let clock = ContinuousClock()

    static func report(_ name: String, _ samples: [Duration]) {
        reportMilliseconds(name, samples.map(milliseconds))
    }

    static func reportMilliseconds(_ name: String, _ values: [Double]) {
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let runs = values.map { String(format: "%.2f", $0) }.joined(separator: ", ")
        print("BENCH \(name): median \(String(format: "%.2f ms", median)) of [\(runs)] ms")
    }

    static func measure(_ name: String, warm: Int = 1, _ body: () throws -> Void) rethrows {
        for _ in 0..<warm { try body() }
        var samples: [Duration] = []
        for _ in 0..<5 {
            let start = clock.now
            try body()
            samples.append(start.duration(to: clock.now))
        }
        report(name, samples)
    }

    /// Repeats a cheap operation, so a cost smaller than one save is still
    /// visible: reports the median cost of one iteration.
    static func measureBatch(_ name: String, count: Int, _ body: () throws -> Void) rethrows {
        try body()
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = clock.now
            for _ in 0..<count { try body() }
            samples.append(milliseconds(start.duration(to: clock.now)) / Double(count))
        }
        reportMilliseconds(name, samples)
    }

    static func measureAsync(_ name: String, _ body: () async throws -> Void) async rethrows {
        try await body()
        var samples: [Duration] = []
        for _ in 0..<5 {
            let start = clock.now
            try await body()
            samples.append(start.duration(to: clock.now))
        }
        report(name, samples)
    }

    /// Repeats a cheap operation, so a cost smaller than one save is still
    /// visible: reports the median cost of one iteration.
    static func measureBatchAsync(
        _ name: String,
        count: Int,
        _ body: () async throws -> Void
    ) async rethrows {
        try await body()
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = clock.now
            for _ in 0..<count { try await body() }
            samples.append(milliseconds(start.duration(to: clock.now)) / Double(count))
        }
        reportMilliseconds(name, samples)
    }

    // MARK: - A copy of the store's durable write, for the breakdown
    //
    // `LibraryStore.writeAtomically` is private, so the breakdown of the page
    // write measures the same syscalls (data write, fsync the file, rename, then
    // fsync the directory) in the same directory rather than the store's code.

    static func writeDurably(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: [])
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            throw NoteCoreError.ioFailure("rename failed")
        }
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw NoteCoreError.ioFailure("open directory failed") }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NoteCoreError.ioFailure("fsync directory failed")
        }
    }

    // MARK: - The benchmark

    @Test func savePageWithTwoThousandStrokes() async throws {
        let page = Self.makePage()
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.open()
        let notebook = try await store.createNotebook(title: "Bench")
        // A realistic manifest: the page plus 49 other pages.
        for index in 0..<50 {
            let added = try await store.addPage(
                to: notebook.id, at: index, width: 1_024, height: 1_366, template: .blank
            )
            if index == 0 {
                var first = try await store.loadPage(added.id, in: notebook.id)
                first.id = page.id
                first.layers = page.layers
                first.strokes = page.strokes
                try await store.savePage(first, in: notebook.id)
                try await store.deletePage(added.id, in: notebook.id)
            }
        }

        let pageFile = root.appendingPathComponent("notebooks")
            .appendingPathComponent(notebook.id.diskName)
            .appendingPathComponent("pages")
            .appendingPathComponent(page.id.diskName + ".page")
        let manifestFile = root.appendingPathComponent("notebooks")
            .appendingPathComponent(notebook.id.diskName)
            .appendingPathComponent("notebook.json")

        // Encode once, so the parts can be measured on the same bytes the store writes.
        let sortedJSON = try NoteCoreJSON.encoder().encode(page)
        var unsorted = JSONEncoder()
        unsorted.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISODate.string(from: date))
        }
        let unsortedJSON = try unsorted.encode(page)
        #expect(
            try NoteCoreJSON.decoder().decode(Page.self, from: unsortedJSON) == page,
            "an unsorted encode must still decode to the same page"
        )
        // Without `.sortedKeys` the key order follows Foundation's hashing, so the
        // same page does not encode to the same bytes twice. That is why the page
        // codec keeps the sort; this line records the evidence for it.
        print(
            "BENCH unsorted encode is byte-stable: "
                + "\((try unsorted.encode(page)) == unsortedJSON)"
        )
        let compressed = try Zlib.compress(sortedJSON, path: "bench")
        let manifestData = try Data(contentsOf: manifestFile)

        // Sizes, so the timings can be read in context.
        print(
            "BENCH page size: \(sortedJSON.count / 1_024) KiB JSON, "
                + "\(compressed.count / 1_024) KiB zlib "
                + "(\(compressed.count * 100 / sortedJSON.count)%), "
                + "manifest \(manifestData.count) bytes"
        )

        // The store as a whole, in the steady state (page id already listed).
        try await Self.measureAsync("savePage total") {
            try await store.savePage(page, in: notebook.id)
        }

        // 1. Encoding.
        try Self.measure("page JSON encode (.sortedKeys)") {
            _ = try NoteCoreJSON.encoder().encode(page)
        }
        try Self.measure("page JSON encode (unsorted)") {
            _ = try unsorted.encode(page)
        }
        try Self.measure("zlib compress") {
            _ = try Zlib.compress(sortedJSON, path: "bench")
        }
        try Self.measure("PageCodec.encode (JSON + zlib)") {
            _ = try PageCodec.encode(page)
        }
        Self.measure("Data(count:) the zlib output buffer") {
            _ = Data(count: sortedJSON.count + sortedJSON.count / 64 + 1_024)
        }

        // 2. The page file write: temp file, fsync, rename, directory fsync.
        try Self.measure("page file write + fsync + rename + dir fsync") {
            try Self.writeDurably(compressed, to: pageFile)
        }

        // 3. What `savePage` also does after the write: read it back, decode it,
        //    compare it with the page and record the checksum.
        try Self.measure("page verify (read back + decode + compare + checksum write)") {
            let stored = try Data(contentsOf: pageFile)
            let decoded = try PageCodec.decode(stored, path: pageFile.path)
            #expect(decoded == page)
            let hash = SHA256.hash(data: stored).map { String(format: "%02x", $0) }.joined()
            try Self.writeDurably(
                Data((hash + "\n").utf8),
                to: pageFile.deletingPathExtension().appendingPathExtension("sha256")
            )
        }

        // 4. The manifest read the save does before it writes.
        try Self.measure("manifest read + decode") {
            _ = try ManifestCodec.decode(try Data(contentsOf: manifestFile), path: manifestFile.path)
        }

        // 5. The manifest write.
        var manifest = try ManifestCodec.decode(manifestData, path: manifestFile.path)
        manifest.updatedAt = Date()
        let encodedManifest = try ManifestCodec.encode(manifest)
        try Self.measure("manifest encode + write + fsyncs") {
            try Self.writeDurably(encodedManifest, to: manifestFile)
        }
        try Self.measure("manifest encode only") {
            _ = try ManifestCodec.encode(manifest)
        }

        // The same save on an ordinary page, where the manifest work is a much
        // larger share of the total.
        let smallNotebook = try await store.createNotebook(title: "Small")
        let smallPage = try await store.addPage(
            to: smallNotebook.id, at: 0, width: 1_024, height: 1_366, template: .blank
        )
        var small = try await store.loadPage(smallPage.id, in: smallNotebook.id)
        var smallRNG = SplitMix64(seed: 0x5_A11)
        small.strokes = (0..<20).map { _ in
            randomStroke(&smallRNG, layerID: small.layers[0].id, pointCount: 30)
        }
        try await store.savePage(small, in: smallNotebook.id)
        let smallManifestFile = root.appendingPathComponent("notebooks")
            .appendingPathComponent(smallNotebook.id.diskName)
            .appendingPathComponent("notebook.json")
        try await Self.measureAsync("savePage total (20 strokes, 30 points each)") {
            try await store.savePage(small, in: smallNotebook.id)
        }
        try Self.measure("manifest read + decode (20-stroke notebook)") {
            _ = try ManifestCodec.decode(
                try Data(contentsOf: smallManifestFile),
                path: smallManifestFile.path
            )
        }
        // One save is too short for this to show up in; 200 show the cost the
        // save pays for the manifest it does not need to decode again.
        try await Self.measureBatchAsync("200 saves, per save (20 strokes)", count: 200) {
            try await store.savePage(small, in: smallNotebook.id)
        }
        // The read the cache replaces, measured beside the cached read in the
        // same run so machine speed cancels out.
        try Self.measureBatch("200 manifest reads from disk, per read", count: 200) {
            _ = try ManifestCodec.decode(
                try Data(contentsOf: smallManifestFile),
                path: smallManifestFile.path
            )
        }
        try await Self.measureBatchAsync("200 cached loadManifest calls, per call", count: 200) {
            _ = try await store.loadManifest(smallNotebook.id)
        }
    }
}
