import NoteCore
import XCTest
@testable import NoteApp

/// The library grid derives its lists once per input change. These compare that
/// one-pass work with a fresh, naive computation over seeded random libraries.
final class LibraryVisibilityTests: XCTestCase {
    /// A seeded generator, so a failure is reproducible from its seed.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func notebook(using generator: inout SeededGenerator) -> NotebookManifest {
        NotebookManifest(
            id: UUID(),
            title: "Notebook \(Int.random(in: 0 ... 999, using: &generator))",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private let vocabulary = ["work", "uni", "Home", "ideas", "2019", "reading"]

    private func tags(using generator: inout SeededGenerator) -> [String] {
        let count = Int.random(in: 0 ... 3, using: &generator)
        var result: [String] = []
        for _ in 0 ..< count {
            result.append(vocabulary.randomElement(using: &generator) ?? "work")
        }
        return result
    }

    private func requiredTags(using generator: inout SeededGenerator) -> Set<String> {
        let count = Int.random(in: 0 ... 2, using: &generator)
        return Set((0 ..< count).map { _ in
            vocabulary.randomElement(using: &generator)!.lowercased()
        })
    }

    /// The view's one-pass tag map and filter must equal a fresh per-notebook
    /// answer, whatever the tags and the requirement are.
    func testFilterMatchesAFreshComputation() {
        var generator = SeededGenerator(seed: 0xA3_07)
        for _ in 0 ..< 40 {
            var storedTags: [UUID: [String]] = [:]
            var notebooks: [NotebookManifest] = []
            for _ in 0 ..< Int.random(in: 0 ... 60, using: &generator) {
                let notebook = notebook(using: &generator)
                notebooks.append(notebook)
                if Bool.random(using: &generator) {
                    storedTags[notebook.id] = tags(using: &generator)
                }
            }
            let sets = LibraryVisibility.tagSets(for: notebooks) { storedTags[$0] ?? [] }
            let required = requiredTags(using: &generator)

            let filtered = LibraryVisibility.filter(
                notebooks,
                requiredTags: required,
                tagSets: sets
            )
            let fresh = notebooks.filter { notebook in
                required.isSubset(of: Set((storedTags[notebook.id] ?? []).map { $0.lowercased() }))
            }

            XCTAssertEqual(
                filtered.map(\.id),
                fresh.map(\.id),
                "one-pass tag filter disagreed with a fresh filter"
            )
            // The filter keeps the model's order, so the grid's sort survives.
            XCTAssertEqual(
                filtered.map(\.id),
                notebooks.map(\.id).filter { fresh.map(\.id).contains($0) }
            )
        }
    }

    func testNoRequiredTagsKeepsTheListUntouched() {
        var generator = SeededGenerator(seed: 0xA3_07_1)
        let notebooks = (0 ..< 20).map { _ in notebook(using: &generator) }
        let sets = LibraryVisibility.tagSets(for: notebooks) { _ in ["work"] }

        XCTAssertEqual(
            LibraryVisibility.filter(notebooks, requiredTags: [], tagSets: sets).map(\.id),
            notebooks.map(\.id)
        )
    }

    func testTagSetsLowercaseEveryLabel() {
        let id = UUID()
        let sets = LibraryVisibility.tagSets(
            for: [NotebookManifest(id: id, title: "x", createdAt: Date(), updatedAt: Date())]
        ) { _ in ["Work", "UNI", "work"] }

        XCTAssertEqual(sets[id], ["work", "uni"])
    }

    /// The one-pass folder counts must equal a naive per-folder descendant count,
    /// including folders nested three deep.
    func testFolderCountsMatchAFreshTreeWalk() {
        var generator = SeededGenerator(seed: 0xA3_07_2)
        for _ in 0 ..< 30 {
            var folders: [Folder] = []
            for index in 0 ..< Int.random(in: 0 ... 12, using: &generator) {
                let parent = index == 0 || Bool.random(using: &generator)
                    ? nil
                    : folders.randomElement(using: &generator)?.id
                folders.append(
                    Folder(
                        id: UUID(),
                        name: "Folder \(index)",
                        parentID: parent
                    )
                )
            }
            var notebookFolder: [UUID: UUID] = [:]
            for _ in 0 ..< Int.random(in: 0 ... 40, using: &generator) {
                let notebookID = UUID()
                if Bool.random(using: &generator), let folder = folders.randomElement(using: &generator) {
                    notebookFolder[notebookID] = folder.id
                }
            }

            let counts = LibraryVisibility.folderCounts(
                folders: folders,
                notebookFolder: notebookFolder
            )
            let parent = Dictionary(
                uniqueKeysWithValues: folders.compactMap { folder in
                    folder.parentID.map { (folder.id, $0) }
                }
            )
            for folder in folders {
                let fresh = notebookFolder.values.filter { folderID in
                    var current: UUID? = folderID
                    var seen: Set<UUID> = []
                    while let id = current, seen.insert(id).inserted {
                        if id == folder.id { return true }
                        current = parent[id]
                    }
                    return false
                }.count
                XCTAssertEqual(
                    counts[folder.id] ?? 0,
                    fresh,
                    "folder count disagreed for \(folder.name)"
                )
            }
        }
    }
}
