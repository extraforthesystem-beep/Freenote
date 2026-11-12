import CryptoKit
import Foundation
import NoteCore

/// One page's recognised text, with the ink state and recogniser version it came from.
public struct PageSearchRecord: Codable, Hashable, Sendable {
    public var notebookID: UUID
    public var pageID: UUID
    public var text: String
    public var contentHash: String
    public var recognitionVersion: Int
    public var updatedAt: Date

    public init(
        notebookID: UUID,
        pageID: UUID,
        text: String,
        contentHash: String,
        recognitionVersion: Int,
        updatedAt: Date
    ) {
        self.notebookID = notebookID
        self.pageID = pageID
        self.text = text
        self.contentHash = contentHash
        self.recognitionVersion = recognitionVersion
        self.updatedAt = updatedAt
    }
}

/// A page whose indexed text contains every term of a query.
public struct SearchHit: Identifiable, Hashable, Sendable {
    public var id: String
    public var notebookID: UUID
    public var pageID: UUID
    public var snippet: String
    /// How many query terms this page matched. All of them, by construction.
    public var matchedTermCount: Int

    public init(
        id: String,
        notebookID: UUID,
        pageID: UUID,
        snippet: String,
        matchedTermCount: Int
    ) {
        self.id = id
        self.notebookID = notebookID
        self.pageID = pageID
        self.snippet = snippet
        self.matchedTermCount = matchedTermCount
    }
}

public enum SearchIndexError: Error, Hashable, Sendable, CustomStringConvertible {
    case corruptIndex(file: String, reason: String)

    public var description: String {
        switch self {
        case let .corruptIndex(file, reason):
            "search index \(file) is unreadable: \(reason)"
        }
    }
}

/// Page text plus the ink fingerprint it was recognised from, persisted as one JSON file.
public actor SearchIndex {
    private struct PageKey: Hashable, Sendable {
        var notebookID: UUID
        var pageID: UUID
    }

    private struct InkSnapshot: Encodable {
        var strokes: [StrokeRecord]
        var deletedStrokeIDs: [String]
    }

    private static let indexFileName = "search-index.json"
    private static let snippetRadius = 60
    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private let root: URL
    private var records: [PageKey: PageSearchRecord] = [:]
    private var loaded = false

    /// `root` is the library cache directory; the index lives at `root/search-index.json`.
    public init(root: URL) {
        self.root = root
    }

    // MARK: Loading and saving

    /// A missing file is an empty index. A file that cannot be decoded throws.
    public func load() throws {
        let url = indexURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            records = [:]
            loaded = true
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let stored = try JSONDecoder().decode([PageSearchRecord].self, from: data)
            records = Dictionary(
                stored.map { (PageKey(notebookID: $0.notebookID, pageID: $0.pageID), $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            loaded = true
        } catch {
            records = [:]
            loaded = false
            throw SearchIndexError.corruptIndex(
                file: url.lastPathComponent,
                reason: error.localizedDescription
            )
        }
    }

    private var indexURL: URL {
        root.appendingPathComponent(Self.indexFileName)
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        try load()
    }

    private func persist() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(sortedRecords())

        let temporaryURL = root.appendingPathComponent("search-index-\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: indexURL.path) {
            _ = try fileManager.replaceItemAt(indexURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: indexURL)
        }
    }

    // MARK: Records

    public func record(for notebookID: UUID, pageID: UUID) -> PageSearchRecord? {
        _ = try? ensureLoaded()
        return records[PageKey(notebookID: notebookID, pageID: pageID)]
    }

    public func isFresh(notebookID: UUID, pageID: UUID, page: Page, recognizerVersion: Int) -> Bool {
        guard let record = record(for: notebookID, pageID: pageID) else { return false }
        return record.recognitionVersion == recognizerVersion
            && record.contentHash == Self.contentHash(of: page)
    }

    /// Recognises a page only when its ink or the recogniser version changed.
    /// Returns nil when nothing was written.
    @discardableResult
    public func update(
        page: Page,
        in notebookID: UUID,
        using recognizer: any HandwritingRecognizing
    ) async throws -> PageSearchRecord? {
        try ensureLoaded()

        let contentHash = Self.contentHash(of: page)
        let key = PageKey(notebookID: notebookID, pageID: page.id)
        if let existing = records[key],
           existing.contentHash == contentHash,
           existing.recognitionVersion == recognizer.recognitionVersion {
            return nil
        }

        var text = ""
        if !page.strokes.isEmpty {
            let recognized = await recognizer.text(for: page.strokes)
            text = recognized?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let record = PageSearchRecord(
            notebookID: notebookID,
            pageID: page.id,
            text: text,
            contentHash: contentHash,
            recognitionVersion: recognizer.recognitionVersion,
            updatedAt: Date()
        )
        records[key] = record
        try persist()
        return record
    }

    public func remove(pageID: UUID, notebookID: UUID) throws {
        try ensureLoaded()
        guard records.removeValue(forKey: PageKey(notebookID: notebookID, pageID: pageID)) != nil else {
            return
        }
        try persist()
    }

    public func removeNotebook(_ notebookID: UUID) throws {
        try ensureLoaded()
        let kept = records.filter { $0.key.notebookID != notebookID }
        guard kept.count != records.count else { return }
        records = kept
        try persist()
    }

    public func allRecords() -> [PageSearchRecord] {
        _ = try? ensureLoaded()
        return sortedRecords()
    }

    // MARK: Search

    public func search(_ query: String) -> [SearchHit] {
        let terms = Self.terms(in: query)
        guard !terms.isEmpty else { return [] }
        _ = try? ensureLoaded()

        var hits: [SearchHit] = []
        for record in records.values {
            let matches = terms.compactMap { Self.firstRange(of: $0, in: record.text) }
            guard matches.count == terms.count,
                  let first = matches.min(by: { $0.lowerBound < $1.lowerBound })
            else { continue }

            hits.append(
                SearchHit(
                    id: "\(record.notebookID.uuidString):\(record.pageID.uuidString)",
                    notebookID: record.notebookID,
                    pageID: record.pageID,
                    snippet: Self.snippet(in: record.text, around: first),
                    matchedTermCount: matches.count
                )
            )
        }

        hits.sort { lhs, rhs in
            if lhs.matchedTermCount != rhs.matchedTermCount {
                return lhs.matchedTermCount > rhs.matchedTermCount
            }
            if lhs.notebookID != rhs.notebookID {
                return lhs.notebookID.uuidString < rhs.notebookID.uuidString
            }
            return lhs.pageID.uuidString < rhs.pageID.uuidString
        }
        return hits
    }

    private static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func firstRange(of term: String, in text: String) -> Range<String.Index>? {
        text.range(of: term, options: matchOptions)
    }

    private static func snippet(in text: String, around match: Range<String.Index>) -> String {
        let lower = text.index(match.lowerBound, offsetBy: -snippetRadius, limitedBy: text.startIndex)
            ?? text.startIndex
        let upper = text.index(match.upperBound, offsetBy: snippetRadius, limitedBy: text.endIndex)
            ?? text.endIndex

        var snippet = String(text[lower..<upper])
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if lower > text.startIndex { snippet = "…" + snippet }
        if upper < text.endIndex { snippet += "…" }
        return snippet
    }

    // MARK: Fingerprint

    /// A stable hash of the ink alone: strokes plus deleted IDs, independent of
    /// page template, size and layers, so those edits do not trigger recognition.
    private static func contentHash(of page: Page) -> String {
        let snapshot = InkSnapshot(
            strokes: page.strokes,
            deletedStrokeIDs: page.deletedStrokeIDs.map(\.uuidString).sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(snapshot) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sortedRecords() -> [PageSearchRecord] {
        records.values.sorted { lhs, rhs in
            if lhs.notebookID != rhs.notebookID {
                return lhs.notebookID.uuidString < rhs.notebookID.uuidString
            }
            return lhs.pageID.uuidString < rhs.pageID.uuidString
        }
    }
}
