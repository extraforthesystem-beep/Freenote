import Foundation
import Observation
import TextDocKit

/// Owns the text-document library for one caller-supplied folder.
///
/// The JSON files on disk are the truth; this object mirrors them for SwiftUI
/// and keeps the in-memory list ordered with the most recently edited document
/// first, matching `TextDocumentStore.list()`.
@MainActor
@Observable
final class TextDocModel {
    private let store: TextDocumentStore

    private(set) var documents: [TextDocument] = []
    private(set) var isLoading = true
    private(set) var lastError: String?

    /// Creates a model backed by text-document files under `root`.
    ///
    /// The directory is created on the first save, so a library that has never
    /// held a text document loads as empty.
    init(root: URL) {
        store = TextDocumentStore(root: root)
    }

    // MARK: - Loading

    /// Reads every readable document from disk, most recently updated first.
    ///
    /// A corrupt or future-schema file is skipped instead of hiding the rest of
    /// the library; the skipped count is published through ``lastError``.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let listing = try await store.listReportingIssues()
            documents = listing.documents
            sortDocuments()
            lastError = Self.skippedMessage(count: listing.issues.count)
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: - Editing

    /// Creates and saves a new document, seeded with one empty paragraph.
    ///
    /// A blank title becomes "Untitled". Returns `nil` when the write fails;
    /// the failure is also published through ``lastError``.
    func createDocument(title: String) async -> TextDocument? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = TextDocument(
            title: trimmed.isEmpty ? "Untitled" : trimmed,
            blocks: [TextBlock(kind: .paragraph(text: ""))]
        )
        do {
            try await store.save(document)
            documents.append(document)
            sortDocuments()
            lastError = nil
            return document
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    /// Stamps the document as edited now, writes it, and refreshes the list.
    func save(_ document: TextDocument) async {
        var updated = document
        updated.touch()
        do {
            try await store.save(updated)
            if let index = documents.firstIndex(where: { $0.id == updated.id }) {
                documents[index] = updated
            } else {
                documents.append(updated)
            }
            sortDocuments()
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// Renames a document, keeping its blocks and identity.
    func rename(_ document: TextDocument, to title: String) async {
        var updated = document
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? "Untitled" : trimmed
        await save(updated)
    }

    /// Deletes the document's file and removes it from the in-memory list.
    func delete(_ document: TextDocument) async {
        do {
            try await store.delete(id: document.id)
            documents.removeAll { $0.id == document.id }
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: - Lookup

    /// The current in-memory copy of a document, if it is still in the library.
    func document(withID id: UUID) -> TextDocument? {
        documents.first { $0.id == id }
    }

    /// Clears the published error, for use after presenting it.
    func clearError() {
        lastError = nil
    }

    // MARK: - Helpers

    private func sortDocuments() {
        documents.sort { left, right in
            if left.updatedAt != right.updatedAt {
                return left.updatedAt > right.updatedAt
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    private static func message(for error: Error) -> String {
        if let textDocError = error as? TextDocError {
            return textDocError.description
        }
        return error.localizedDescription
    }

    private static func skippedMessage(count: Int) -> String? {
        guard count > 0 else { return nil }
        if count == 1 {
            return "1 text document couldn't be read and was skipped; the rest are fine."
        }
        return "\(count) text documents couldn't be read and were skipped; the rest are fine."
    }
}
