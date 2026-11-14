import Foundation
import Testing
@testable import TextDocKit

/// List items carry their own identity, and identity survives the edits that
/// used to rebind a row to another item: a split in the middle, a merge, and a
/// save and reload.
@Suite("List item identity")
struct ListItemIdentityTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "TextDocKitListItemTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func bulletItems(_ block: TextBlock) -> [ListItem] {
        guard case let .bulletList(items) = block.kind else { return [] }
        return items
    }

    @Test("An old file that stored list items as plain strings still loads")
    func oldStringItemsLoad() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)

        let document = TextDocument(
            title: "Old",
            blocks: [TextBlock(kind: .bulletList(items: ["One", "Two"]))]
        )
        try await store.save(document)

        // Rewrite the saved file the way the previous format wrote it: the
        // items were strings, with no identity of their own.
        let file = store.fileURL(for: document.id)
        let data = try Data(contentsOf: file)
        var json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json = Self.replacingListItemsWithStrings(json) as? [String: Any] ?? json
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let loaded = try await store.load(id: document.id)
        #expect(loaded.title == "Old")
        #expect(loaded.blocks.map(\.text) == ["One\nTwo"])
        let items = bulletItems(loaded.blocks[0])
        #expect(items.map(\.text) == ["One", "Two"])
        #expect(Set(items.map(\.id)).count == 2)
    }

    @Test("An item object without an id decodes with a fresh identity")
    func itemWithoutIDDecodes() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)
        let id = UUID()
        let file = store.fileURL(for: id)
        let json = """
        {
          "schemaVersion": 1,
          "id": "\(id.uuidString)",
          "title": "No id",
          "blocks": [
            {
              "id": "\(UUID().uuidString)",
              "kind": {
                "bulletList": { "items": [ { "text": "Only" } ] }
              }
            }
          ],
          "createdAt": 0,
          "updatedAt": 0
        }
        """
        try Data(json.utf8).write(to: file)

        let loaded = try await store.load(id: id)
        let items = bulletItems(loaded.blocks[0])
        #expect(items.map(\.text) == ["Only"])
        #expect(items.count == 1)
    }

    @Test("Item identity survives a save and reload")
    func identitySurvivesRoundTrip() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(root: root)

        let first = ListItem(text: "One")
        let second = ListItem(text: "Two")
        let document = TextDocument(
            blocks: [TextBlock(kind: .numberedList(items: [first, second]))]
        )
        try await store.save(document)

        let loaded = try await store.load(id: document.id)
        guard case let .numberedList(items) = loaded.blocks[0].kind else {
            Issue.record("Expected a numbered list")
            return
        }
        #expect(items.map(\.id) == [first.id, second.id])
    }

    @Test("Splitting a list in the middle keeps every item's identity")
    func splitKeepsIdentity() throws {
        let one = ListItem(text: "One")
        let two = ListItem(text: "TwoThree")
        let three = ListItem(text: "Four")
        let block = TextBlock(kind: .bulletList(items: [one, two, three]))
        var document = TextDocument(blocks: [block])

        _ = document.splitBlock(id: block.id, itemIndex: 1, offset: 3)

        let head = bulletItems(document.blocks[0])
        #expect(head.map(\.id) == [one.id, two.id])
        #expect(head.map(\.text) == ["One", "Two"])
        let tail = bulletItems(document.blocks[1])
        #expect(tail.first?.text == "Three")
        #expect(tail.last?.id == three.id)
    }

    @Test("Merging two items keeps the identity of the item that survives")
    func mergeKeepsSurvivingIdentity() throws {
        let one = ListItem(text: "Hello")
        let two = ListItem(text: "World")
        let three = ListItem(text: "Again")
        let block = TextBlock(kind: .numberedList(items: [one, two, three]))
        var document = TextDocument(blocks: [block])

        _ = document.mergeBlockBackward(id: block.id, itemIndex: 1)

        guard case let .numberedList(items) = document.blocks[0].kind else {
            Issue.record("Expected a numbered list")
            return
        }
        #expect(items.map(\.text) == ["HelloWorld", "Again"])
        #expect(items.map(\.id) == [one.id, three.id])
    }

    /// Turns every `{"id": …, "text": …}` item back into the bare string the
    /// first format wrote.
    private static func replacingListItemsWithStrings(_ value: Any) -> Any {
        if let array = value as? [Any] {
            return array.map { replacingListItemsWithStrings($0) }
        }
        guard var object = value as? [String: Any] else { return value }
        for key in object.keys {
            if key == "bulletList" || key == "numberedList",
               var list = object[key] as? [String: Any],
               let items = list["items"] as? [Any] {
                list["items"] = items.compactMap { ($0 as? [String: Any])?["text"] as? String }
                object[key] = list
            } else {
                object[key] = replacingListItemsWithStrings(object[key] as Any)
            }
        }
        return object
    }
}
