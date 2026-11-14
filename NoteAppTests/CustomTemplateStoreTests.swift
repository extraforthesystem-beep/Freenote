import NoteCore
import XCTest
@testable import NoteApp

/// The imported-template index: an unreadable index is reported, not shown as
/// an empty library, and its bytes are never lost.
@MainActor
final class CustomTemplateStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomTemplateStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private var indexFile: URL { root.appendingPathComponent("index.json") }
    private var preservedIndexFile: URL { root.appendingPathComponent("index-unreadable.json") }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }

    func testAStoreWithNoIndexIsEmptyAndFine() {
        let store = CustomTemplateStore(root: root)
        store.load()

        XCTAssertTrue(store.templates.isEmpty)
        XCTAssertFalse(store.indexUnreadable)
    }

    func testCorruptIndexIsReportedNotSilentlyEmpty() throws {
        try write("{ not a list of templates", to: indexFile)
        let store = CustomTemplateStore(root: root)
        store.load()

        XCTAssertTrue(store.templates.isEmpty)
        XCTAssertTrue(store.indexUnreadable, "a corrupt index must be surfaced, not shown as no templates")
    }

    func testTemplatesWhoseFileHasGoneAreLeftOut() throws {
        let template = CustomPageTemplate(id: UUID(), name: "Planner", assetName: "missing.png")
        try JSONEncoder().encode([template]).write(to: indexFile)
        let store = CustomTemplateStore(root: root)

        store.load()

        XCTAssertFalse(store.indexUnreadable)
        XCTAssertTrue(store.templates.isEmpty)
    }

    func testUnreadableIndexIsKeptWhenTheListIsWrittenAgain() throws {
        let corrupt = "{ not a list of templates"
        try write(corrupt, to: indexFile)
        let store = CustomTemplateStore(root: root)
        store.load()
        XCTAssertTrue(store.indexUnreadable)

        // Any write keeps the bytes that could not be read, instead of
        // replacing them with this session's list.
        store.remove(CustomPageTemplate(id: UUID(), name: "Gone", assetName: "gone.png"))

        let preserved = try String(contentsOf: preservedIndexFile, encoding: .utf8)
        XCTAssertEqual(preserved, corrupt)
        XCTAssertFalse(store.indexUnreadable, "the new index is the one on disk now")
    }

    func testRetryReturnsTheTemplatesOnceTheIndexIsFixed() throws {
        try write("{ not a list of templates", to: indexFile)
        let store = CustomTemplateStore(root: root)
        store.load()
        XCTAssertTrue(store.indexUnreadable)

        // The picture is on disk, as an import would leave it.
        try write("picture", to: root.appendingPathComponent("planner.png"))
        let template = CustomPageTemplate(id: UUID(), name: "Planner", assetName: "planner.png")
        try JSONEncoder().encode([template]).write(to: indexFile)

        store.load()

        XCTAssertFalse(store.indexUnreadable)
        XCTAssertEqual(store.templates.map(\.id), [template.id])
    }
}
