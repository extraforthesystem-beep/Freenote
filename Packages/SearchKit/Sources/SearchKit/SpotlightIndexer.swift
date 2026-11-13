import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Publishes indexed pages to system search (Core Spotlight), and takes them
/// back out when a page or notebook goes away. Everything stays on this device.
public struct SpotlightIndexer {
    /// One domain per notebook, so deleting a notebook is a single delete call.
    private static let domainPrefix = "noteapp.pages."
    /// Long enough for a page of notes, short enough for one searchable item.
    private static let maximumTextLength = 8_000

    public init() {}

    /// Adds or replaces the pages' entries.
    public func index(_ records: [PageSearchRecord], notebookTitles: [UUID: String]) async throws {
        guard !records.isEmpty else { return }
        let items = records.map { record in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            let title = notebookTitles[record.notebookID] ?? "Notebook"
            attributes.title = record.pageIndex > 0
                ? "\(title) · Page \(record.pageIndex)"
                : title
            attributes.contentDescription = String(record.text.prefix(Self.maximumTextLength))
            attributes.creator = "NoteApp"
            attributes.keywords = ["note", "notes", "notebook", "handwriting"]
            return CSSearchableItem(
                uniqueIdentifier: Self.identifier(pageID: record.pageID, notebookID: record.notebookID),
                domainIdentifier: Self.domain(for: record.notebookID),
                attributeSet: attributes
            )
        }
        try await CSSearchableIndex.default().indexSearchableItems(items)
    }

    /// Removes one page's entry.
    public func remove(pageID: UUID, notebookID: UUID) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [Self.identifier(pageID: pageID, notebookID: notebookID)]
        )
    }

    /// Removes every page of one notebook.
    public func removeNotebook(_ notebookID: UUID) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [Self.domain(for: notebookID)]
        )
    }

    /// Removes every page this app published.
    public func removeAll() async throws {
        try await CSSearchableIndex.default().deleteAllSearchableItems()
    }

    private static func identifier(pageID: UUID, notebookID: UUID) -> String {
        "\(notebookID.uuidString)/\(pageID.uuidString)"
    }

    private static func domain(for notebookID: UUID) -> String {
        domainPrefix + notebookID.uuidString
    }
}
