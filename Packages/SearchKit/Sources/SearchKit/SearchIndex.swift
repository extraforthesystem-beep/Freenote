import CryptoKit
import Foundation
import NoteCore
import PDFKit
import Vision

/// Where the text a page was indexed from came from. Search results are grouped
/// by this, the way Goodnotes separates "Written Notes", "Text" and "PDFs".
public enum PageTextSource: String, Codable, Hashable, Sendable, CaseIterable {
    case handwriting
    case typedText
    case pdf

    /// Section heading a search UI shows for this source.
    public var sectionTitle: String {
        switch self {
        case .handwriting: "Written Notes"
        case .typedText: "Text"
        case .pdf: "PDFs"
        }
    }

    /// Stable display order: handwriting, typed text, then PDF text.
    var displayOrder: Int {
        switch self {
        case .handwriting: 0
        case .typedText: 1
        case .pdf: 2
        }
    }
}

/// One source's readable text on a page, kept apart so a hit can say which kind
/// of content matched.
public struct PageTextSegment: Codable, Hashable, Sendable {
    public var source: PageTextSource
    public var text: String

    public init(source: PageTextSource, text: String) {
        self.source = source
        self.text = text
    }
}

/// One page's recognised text, with the ink state and recogniser version it came from.
public struct PageSearchRecord: Codable, Hashable, Sendable {
    /// Bumped when the record layout changes. Older records are dropped on load
    /// and recognised again, rather than surfacing hits with unknown sources.
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var notebookID: UUID
    public var pageID: UUID
    /// 1-based page number in the notebook, or 0 when the page order is unknown.
    public var pageIndex: Int
    /// Every segment's text joined by newlines. Kept for callers that display the
    /// page's whole indexed text; searches read `segments`.
    public var text: String
    public var segments: [PageTextSegment]
    public var contentHash: String
    public var recognitionVersion: Int
    public var updatedAt: Date
    /// The newest stroke or element on the page; nil for records written before
    /// it was stored, which fall back to `updatedAt`.
    public var editedAt: Date?

    /// When the page was last changed, as near as the index knows.
    public var lastEdited: Date { editedAt ?? updatedAt }

    public init(
        schemaVersion: Int = PageSearchRecord.currentSchemaVersion,
        notebookID: UUID,
        pageID: UUID,
        pageIndex: Int = 0,
        text: String,
        segments: [PageTextSegment] = [],
        contentHash: String,
        recognitionVersion: Int,
        updatedAt: Date,
        editedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.notebookID = notebookID
        self.pageID = pageID
        self.pageIndex = pageIndex
        self.text = text
        self.segments = segments
        self.contentHash = contentHash
        self.recognitionVersion = recognitionVersion
        self.updatedAt = updatedAt
        self.editedAt = editedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case notebookID
        case pageID
        case pageIndex
        case text
        case segments
        case contentHash
        case recognitionVersion
        case updatedAt
        case editedAt
    }

    /// Files written before segments existed decode with version 0 and no
    /// segments, which marks them old enough to re-index.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        notebookID = try container.decode(UUID.self, forKey: .notebookID)
        pageID = try container.decode(UUID.self, forKey: .pageID)
        pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex) ?? 0
        text = try container.decode(String.self, forKey: .text)
        segments = try container.decodeIfPresent([PageTextSegment].self, forKey: .segments) ?? []
        contentHash = try container.decode(String.self, forKey: .contentHash)
        recognitionVersion = try container.decode(Int.self, forKey: .recognitionVersion)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
    }
}

/// One place in one source of one page where every query term was found.
public struct SearchHit: Identifiable, Hashable, Sendable {
    public var id: String
    public var notebookID: UUID
    public var pageID: UUID
    /// 1-based page number for display; 0 when the index does not know the order.
    public var pageIndex: Int
    public var source: PageTextSource
    /// A single-line excerpt of the indexed text around the first match.
    public var snippet: String
    /// The matched text's range inside `snippet`, for highlighting.
    public var matchRange: Range<String.Index>?
    /// How many query terms this page matched. All of them, by construction.
    public var matchedTermCount: Int

    public init(
        id: String,
        notebookID: UUID,
        pageID: UUID,
        pageIndex: Int = 0,
        source: PageTextSource = .handwriting,
        snippet: String,
        matchRange: Range<String.Index>? = nil,
        matchedTermCount: Int
    ) {
        self.id = id
        self.notebookID = notebookID
        self.pageID = pageID
        self.pageIndex = pageIndex
        self.source = source
        self.snippet = snippet
        self.matchRange = matchRange
        self.matchedTermCount = matchedTermCount
    }

    /// The page number as a label, for chips and result rows.
    public var pageLabel: String {
        pageIndex > 0 ? "p.\(pageIndex)" : "Page"
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
        /// Typed text boxes are searchable too, and changing one must re-index.
        var typedText: String
        /// PDF page references are part of the fingerprint so pointing a page at
        /// a different PDF asset re-indexes it.
        var pdfRefs: [String]
    }

    private static let indexFileName = "search-index.json"
    private static let snippetLength = 80
    /// Characters kept before the match so the excerpt opens with context.
    private static let snippetLead = 25
    /// Shortest word considered for the tolerant prefix match.
    private static let tolerantMinimumLength = 3
    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private static let foldOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private let root: URL
    private var records: [PageKey: PageSearchRecord] = [:]
    private var loaded = false
    /// Open `beginDeferringWrites()` calls. While above zero, changes stay in
    /// memory and `isDirty` records that the file is behind.
    private var writeDeferrals = 0
    private var isDirty = false

    /// `root` is the library cache directory; the index lives at `root/search-index.json`.
    public init(root: URL) {
        self.root = root
    }

    // MARK: Loading and saving

    /// A missing file is an empty index. A file that cannot be decoded throws.
    public func load() throws {
        // Reading the file would drop changes still waiting to be written.
        try flushDeferredWrites()
        let url = indexURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            records = [:]
            loaded = true
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let stored = try JSONDecoder().decode([PageSearchRecord].self, from: data)
            // A record from an older layout is re-recognised instead of being
            // shown without a source.
            let current = stored.filter { $0.schemaVersion == PageSearchRecord.currentSchemaVersion }
            records = Dictionary(
                current.map { (PageKey(notebookID: $0.notebookID, pageID: $0.pageID), $0) },
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

    /// Writes the file now, or marks it stale while writes are deferred.
    private func persist() throws {
        guard writeDeferrals == 0 else {
            isDirty = true
            return
        }
        try write()
    }

    /// Keeps changes in memory until the matching `endDeferringWrites()`.
    ///
    /// The index is one JSON file, so writing it after every page makes a
    /// first pass over N pages cost O(N²) bytes encoded and written. Callers
    /// that update many pages in a row open a deferral, flush now and then
    /// with `flushDeferredWrites()`, and close it at the end. Searches see
    /// every change at once; only the file lags behind.
    public func beginDeferringWrites() {
        writeDeferrals += 1
    }

    /// Closes one deferral and writes the file if it was the last one and
    /// anything changed.
    public func endDeferringWrites() throws {
        writeDeferrals = max(0, writeDeferrals - 1)
        guard writeDeferrals == 0 else { return }
        try flushDeferredWrites()
    }

    /// Writes pending changes now, even while writes are deferred.
    public func flushDeferredWrites() throws {
        guard isDirty else { return }
        try write()
    }

    private func write() throws {
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
        isDirty = false
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
    ///
    /// `pageIndex` is the page's 1-based position in the notebook, carried into
    /// every hit so search UIs can label it without looking the order up again.
    @discardableResult
    public func update(
        page: Page,
        in notebookID: UUID,
        pageIndex: Int = 0,
        using recognizer: any HandwritingRecognizing,
        assetsDirectory: URL? = nil
    ) async throws -> PageSearchRecord? {
        try ensureLoaded()

        let contentHash = Self.contentHash(of: page)
        let key = PageKey(notebookID: notebookID, pageID: page.id)
        if let existing = records[key],
           existing.contentHash == contentHash,
           existing.recognitionVersion == recognizer.recognitionVersion {
            // The text is unchanged but the page moved: refresh the number only,
            // without paying for recognition again.
            // Records from before edit dates were stored get theirs the same way.
            guard existing.pageIndex != pageIndex || existing.editedAt == nil else { return nil }
            var moved = existing
            moved.pageIndex = pageIndex
            moved.editedAt = Self.editedAt(of: page) ?? existing.updatedAt
            records[key] = moved
            try persist()
            return moved
        }

        var segments: [PageTextSegment] = []
        let typed = Self.typedText(in: page)
        if !typed.isEmpty {
            segments.append(PageTextSegment(source: .typedText, text: typed))
        }
        let pdfText = Self.pdfText(in: page, assetsDirectory: assetsDirectory)
        if !pdfText.isEmpty {
            segments.append(PageTextSegment(source: .pdf, text: pdfText))
        }
        if !page.strokes.isEmpty {
            let recognized = await recognizer.text(for: page.strokes)
            if let recognized, !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(
                    PageTextSegment(
                        source: .handwriting,
                        text: recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            }
        }
        let text = segments.map(\.text).joined(separator: "\n")

        let record = PageSearchRecord(
            notebookID: notebookID,
            pageID: page.id,
            pageIndex: pageIndex,
            text: text,
            segments: segments,
            contentHash: contentHash,
            recognitionVersion: recognizer.recognitionVersion,
            updatedAt: Date(),
            editedAt: Self.editedAt(of: page)
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

    /// Every page-and-source whose indexed text contains all query terms.
    /// Pass `notebookID` to scope the search to one notebook.
    public func search(_ query: String, in notebookID: UUID? = nil) -> [SearchHit] {
        search(SearchQuery(query), filter: SearchFilter(notebookIDs: notebookID.map { [$0] }))
    }

    /// Every page-and-source whose indexed text satisfies `query` and passes `filter`.
    public func search(_ query: SearchQuery, filter: SearchFilter) -> [SearchHit] {
        guard !query.isEmpty, !filter.sources.isEmpty else { return [] }
        _ = try? ensureLoaded()

        let candidates: [PageSearchRecord]
        if let notebookIDs = filter.notebookIDs {
            candidates = records.values.filter { notebookIDs.contains($0.notebookID) }
        } else {
            candidates = Array(records.values)
        }

        var hits: [SearchHit] = []
        for record in candidates {
            if let editedAfter = filter.editedAfter, record.lastEdited < editedAfter { continue }
            for segment in record.segments where !segment.text.isEmpty && filter.sources.contains(segment.source) {
                guard let excerpt = Self.excerpt(in: segment.text, matching: query) else { continue }
                hits.append(
                    SearchHit(
                        id: "\(record.notebookID.uuidString):\(record.pageID.uuidString):\(segment.source.rawValue)",
                        notebookID: record.notebookID,
                        pageID: record.pageID,
                        pageIndex: record.pageIndex,
                        source: segment.source,
                        snippet: excerpt.snippet,
                        matchRange: excerpt.matchRange,
                        matchedTermCount: query.groups.count
                    )
                )
            }
        }

        hits.sort { lhs, rhs in
            if lhs.matchedTermCount != rhs.matchedTermCount {
                return lhs.matchedTermCount > rhs.matchedTermCount
            }
            if lhs.notebookID != rhs.notebookID {
                return lhs.notebookID.uuidString < rhs.notebookID.uuidString
            }
            if lhs.pageIndex != rhs.pageIndex {
                return lhs.pageIndex < rhs.pageIndex
            }
            if lhs.source != rhs.source {
                return lhs.source.displayOrder < rhs.source.displayOrder
            }
            return lhs.pageID.uuidString < rhs.pageID.uuidString
        }
        return hits
    }

    /// Every group must match and no excluded term may appear. Returns the earliest match's excerpt.
    private static func excerpt(in text: String, matching query: SearchQuery) -> (snippet: String, matchRange: Range<String.Index>?)? {
        for term in query.excluded where phraseMatch(of: term.text, in: text) != nil {
            return nil
        }
        var matches: [Range<String.Index>] = []
        for group in query.groups {
            let found = group.compactMap { term in
                term.isPhrase ? phraseMatch(of: term.text, in: text) : firstMatch(of: term.text, in: text)
            }
            guard let earliest = found.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
            matches.append(earliest)
        }
        guard let first = matches.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        return snippet(in: text, around: first)
    }

    /// An exact case- and diacritic-insensitive match, where a space in `phrase` also
    /// matches a line break, since recognised ink breaks lines where the writer did.
    private static func phraseMatch(of phrase: String, in text: String) -> Range<String.Index>? {
        if let range = text.range(of: phrase, options: matchOptions) {
            return range
        }
        let words = phrase.split(whereSeparator: \.isWhitespace)
        guard words.count > 1 else { return nil }
        let pattern = words.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        return text.range(of: pattern, options: matchOptions.union(.regularExpression))
    }

    /// An exact case- and diacritic-insensitive substring match first, then a
    /// tolerant word-prefix match so "force" still finds the misrecognised "forc"
    /// and "forc" finds "force".
    private static func firstMatch(of term: String, in text: String) -> Range<String.Index>? {
        guard !term.isEmpty else { return nil }
        if let range = text.range(of: term, options: matchOptions) {
            return range
        }

        let foldedTerm = fold(term)
        guard foldedTerm.count >= tolerantMinimumLength else { return nil }

        var found: Range<String.Index>?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            let foldedWord = fold(String(text[range]))
            guard foldedWord.count >= tolerantMinimumLength else { return }
            // The query may be longer than the recognised word ("force" → "forc"),
            // but only for words long enough to be a real recognition, so a short
            // query is not answered by a stray fragment.
            if foldedWord.hasPrefix(foldedTerm) {
                found = range
                stop = true
            } else if foldedWord.count >= 4, foldedTerm.hasPrefix(foldedWord) {
                found = range
                stop = true
            }
        }
        return found
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: foldOptions, locale: .current)
    }

    /// A single-line excerpt of about `snippetLength` characters around `match`,
    /// trimmed to whole words, with the matched text's range inside it.
    private static func snippet(in text: String, around match: Range<String.Index>) -> (snippet: String, matchRange: Range<String.Index>) {
        let matchStart = text.distance(from: text.startIndex, to: match.lowerBound)
        let matchEnd = text.distance(from: text.startIndex, to: match.upperBound)

        var start = max(0, matchStart - snippetLead)
        var end = min(text.count, start + snippetLength)
        if end < matchEnd {
            end = min(text.count, matchEnd)
        }

        // Do not open or close the excerpt mid-word, unless that would drop the
        // match itself.
        if start > 0 {
            var candidate = start
            while candidate < matchStart, !isWhitespace(at: candidate, in: text) {
                candidate += 1
            }
            if candidate < matchStart { start = candidate }
        }
        if end < text.count {
            var candidate = end
            while candidate > matchEnd, !isWhitespace(at: candidate - 1, in: text) {
                candidate -= 1
            }
            if candidate > matchEnd { end = candidate }
        }

        let window = text[
            text.index(text.startIndex, offsetBy: start)
                ..< text.index(text.startIndex, offsetBy: end)
        ]

        // Flatten newlines and runs of spaces, remembering where the match lands.
        var collapsed = ""
        var collapsedMatchStart = 0
        var collapsedMatchEnd = 0
        var offset = start
        var pendingSpace = false
        for character in window {
            if character.isWhitespace {
                if !collapsed.isEmpty { pendingSpace = true }
                offset += 1
                continue
            }
            if pendingSpace {
                collapsed.append(" ")
                pendingSpace = false
            }
            if offset == matchStart { collapsedMatchStart = collapsed.count }
            collapsed.append(character)
            offset += 1
            if offset == matchEnd { collapsedMatchEnd = collapsed.count }
        }

        var snippet = collapsed
        if start > 0 {
            snippet = "…" + snippet
            collapsedMatchStart += 1
            collapsedMatchEnd += 1
        }
        if end < text.count {
            snippet += "…"
        }

        let lower = snippet.index(snippet.startIndex, offsetBy: collapsedMatchStart)
        let upper = snippet.index(snippet.startIndex, offsetBy: collapsedMatchEnd)
        return (snippet, lower..<upper)
    }

    private static func isWhitespace(at offset: Int, in text: String) -> Bool {
        text[text.index(text.startIndex, offsetBy: offset)].isWhitespace
    }

    // MARK: Fingerprint

    /// A stable hash of the ink alone: strokes plus deleted IDs, independent of
    /// page template, size and layers, so those edits do not trigger recognition.
    private static func editedAt(of page: Page) -> Date? {
        let strokeDates = page.strokes.map(\.createdAt)
        let elementDates = page.elements.map(\.updatedAt)
        return (strokeDates + elementDates).max()
    }

    private static func typedText(in page: Page) -> String {
        page.elements.compactMap { element -> String? in
            let text: String
            switch element.content {
            case let .text(value, _, _, _): text = value
            case let .stickyNote(value, _): text = value
            default: return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n")
    }

    /// The text of every PDF page on the page. A scanned page has no text layer,
    /// so its words are read from an on-device image render instead.
    private static func pdfText(in page: Page, assetsDirectory: URL?) -> String {
        guard let assetsDirectory else { return "" }
        var parts: [String] = []
        for element in page.elements {
            guard case let .pdfPage(assetName, pageIndex) = element.content,
                  pageIndex >= 0
            else { continue }
            let url = assetsDirectory.appendingPathComponent(assetName)
            guard let document = PDFDocument(url: url),
                  let pdfPage = document.page(at: pageIndex)
            else { continue }
            let stored = pdfPage.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = stored.isEmpty ? ocrText(from: pdfPage) : stored
            guard !text.isEmpty else { continue }
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }

    /// Reads the words in a scanned PDF page with Vision. Runs once per page,
    /// because the index keeps the result until the page or PDF reference
    /// changes; it is deliberately not run on every search.
    private static func ocrText(from pdfPage: PDFPage) -> String {
        let bounds = pdfPage.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return "" }
        // A4 at about 2.5× is enough for the recogniser without a huge bitmap.
        let scale = min(3, 2_000 / max(bounds.width, bounds.height))
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return "" }

        // A white page, like paper, reads better than a transparent one.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        pdfPage.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return "" }

        return (request.results ?? [])
            .sorted { left, right in
                // Vision's boxes start at the bottom-left; group into lines
                // from the top and read each line left to right.
                let leftLine = Int((1 - left.boundingBox.midY) * 50)
                let rightLine = Int((1 - right.boundingBox.midY) * 50)
                if leftLine != rightLine { return leftLine < rightLine }
                return left.boundingBox.minX < right.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pdfRefs(in page: Page) -> [String] {
        page.elements.compactMap { element in
            guard case let .pdfPage(assetName, pageIndex) = element.content else { return nil }
            return "\(assetName)#\(pageIndex)"
        }
        .sorted()
    }

    private static func contentHash(of page: Page) -> String {
        let snapshot = InkSnapshot(
            strokes: page.strokes,
            deletedStrokeIDs: page.deletedStrokeIDs.map(\.uuidString).sorted(),
            typedText: typedText(in: page),
            pdfRefs: pdfRefs(in: page)
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
