// Timing benchmark for the library rescan `AppModel.reload()` runs on disk.
// Off by default so the suite stays fast; run it with:
//
//     NOTEAPP_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter LibraryScanBenchmarks
//
// The number is reported to the test log only when enabled; nothing here
// asserts on time, so a slow machine cannot fail CI.

import Foundation
import Testing
@testable import NoteCore

@Suite("Library scan benchmarks", .enabled(if: ProcessInfo.processInfo.environment["NOTEAPP_BENCH"] != nil))
struct LibraryScanBenchmarks {
    static let notebookCount = 200
    static let pagesPerNotebook = 20

    /// The library the benchmark measures: 200 notebooks of 20 pages, built
    /// through the same store calls the app makes.
    static func makeLibrary(at root: URL) async throws {
        let store = LibraryStore(root: root)
        try await store.open()
        for index in 0..<notebookCount {
            let notebook = try await store.createNotebook(title: "Notebook \(index + 1)")
            for _ in 0..<pagesPerNotebook {
                _ = try await store.addPage(
                    to: notebook.id,
                    at: Int.max,
                    width: 600,
                    height: 800,
                    template: .blank
                )
            }
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }

    @Test func rescanAfterOneEdit() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await Self.makeLibrary(at: root)

        let store = LibraryStore(root: root)
        let clock = ContinuousClock()
        // One warm pass, so the measurement is not the first page-cache fill.
        _ = try await store.scanNotebooks()
        _ = try await store.scanTrash()

        var samples: [Duration] = []
        for _ in 0..<5 {
            let start = clock.now
            _ = try await store.scanNotebooks()
            _ = try await store.scanTrash()
            samples.append(start.duration(to: clock.now))
        }

        let runs = samples.map { String(format: "%.1f ms", Self.seconds($0) * 1_000) }
        let median = samples.sorted()[samples.count / 2]
        print(
            "BENCH library rescan (\(Self.notebookCount) notebooks, "
                + "\(Self.pagesPerNotebook) pages each): median "
                + String(format: "%.1f ms", Self.seconds(median) * 1_000)
                + " of " + runs.joined(separator: ", ")
        )
    }
}
