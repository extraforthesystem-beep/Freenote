import CoreGraphics
import Foundation
import InkKit
import NoteCore
import PDFKit

enum PDFImportError: LocalizedError {
    case unreadablePDF
    case emptyPDF
    case noPages
    case passwordRequired
    case wrongPassword
    case insertFailed
    /// Some, or all, of the chosen pages were written before the import stopped.
    case partialInsert(added: Int, total: Int)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF: "This file is not a PDF the app can read."
        case .emptyPDF: "The PDF has no pages."
        case .noPages: "No page could be imported."
        case .passwordRequired: "This PDF is protected. Enter its password to import it."
        case .wrongPassword: "That password did not work. Try again."
        case .insertFailed: "The PDF pages could not be inserted into this notebook."
        case let .partialInsert(added, total):
            added >= total
                ? "All \(total) pages were inserted, but the notebook could not be updated. Close this sheet instead of inserting again."
                : "\(added) of \(total) pages were inserted before the insert stopped. Those pages are already in the notebook, so close this sheet instead of inserting again."
        }
    }
}

/// Where blank writing space is added beside each imported PDF page, so notes
/// can go next to the text instead of on top of it. Page points added per side;
/// the page grows, the PDF keeps its own size.
nonisolated enum PDFPageMargin: String, CaseIterable, Identifiable, Sendable {
    case none
    case left
    case right
    case both

    /// A comfortable column to write a margin note in.
    static let width: Double = 240

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .left: "Left"
        case .right: "Right"
        case .both: "Both Sides"
        }
    }

    var addsLeft: Bool { self == .left || self == .both }
    var addsRight: Bool { self == .right || self == .both }

    var leftInset: Double { addsLeft ? Self.width : 0 }
    var rightInset: Double { addsRight ? Self.width : 0 }
}

/// Which PDF pages to import, in the 1-based numbers the range picker shows.
enum PDFPageSelection: Sendable, Hashable {
    case all
    case range(from: Int, to: Int)

    /// The 0-based page indices, clamped to the document and never empty for a
    /// document with pages.
    nonisolated func pdfIndices(pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        switch self {
        case .all:
            return Array(0..<pageCount)
        case let .range(from, to):
            let lower = min(max(1, min(from, to)), pageCount)
            let upper = min(max(1, max(from, to)), pageCount)
            return Array((lower - 1)...(upper - 1))
        }
    }
}

/// What the unlock step needs to know before a range can be offered.
struct PDFDocumentInfo: Sendable {
    let pageCount: Int
}

/// The notebook pages an import produced, plus the outline titles for them.
struct PDFImportResult: Sendable {
    let manifest: NotebookManifest
    /// Page id to outline title, ready for `PageOutline`.
    let titles: [UUID: String]
}

struct PDFPageInsertResult: Sendable {
    let count: Int
    let titles: [UUID: String]
}

/// Turns a PDF into notebook pages that keep referencing the original file.
///
/// Reading, unlocking, path conversion and the rewrite of the stored copy all
/// happen on a background task; only the short page writes cross back. Nothing
/// here renders a thumbnail, so a large document costs one page of work at a
/// time.
@MainActor
enum PDFImporter {
    /// Above this many pages the import sheet shows a determinate bar.
    static let progressPageThreshold = 20

    // MARK: - Inspecting

    /// Reads only the page count, and unlocks the document when it is
    /// password protected. Throws `passwordRequired` or `wrongPassword` so the
    /// caller can ask for one and try again.
    static func inspect(at url: URL, password: String?) async throws -> PDFDocumentInfo {
        try await Task.detached(priority: .userInitiated) { () throws -> PDFDocumentInfo in
            guard let document = PDFDocument(url: url) else {
                throw PDFImportError.unreadablePDF
            }
            if document.isLocked {
                guard let password, !password.isEmpty else {
                    throw PDFImportError.passwordRequired
                }
                guard document.unlock(withPassword: password) else {
                    throw PDFImportError.wrongPassword
                }
            }
            guard document.pageCount > 0 else { throw PDFImportError.emptyPDF }
            return PDFDocumentInfo(pageCount: document.pageCount)
        }.value
    }

    // MARK: - New notebook

    /// Creates a notebook with one page per selected PDF page.
    ///
    /// The PDF is copied into the notebook's assets once. When the file needs a
    /// password or carries ink annotations, the stored copy is rewritten:
    /// encryption is stripped and the converted annotations are removed. The
    /// password itself is never stored or logged.
    static func importPDF(
        at url: URL,
        into store: LibraryStore,
        title: String? = nil,
        selection: PDFPageSelection = .all,
        margin: PDFPageMargin = .none,
        password: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> PDFImportResult {
        let scan = try await scan(
            at: url,
            selection: selection,
            password: password,
            progress: scaledProgress(onProgress, to: 0.5)
        )

        let notebookTitle = (title ?? url.deletingPathExtension().lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var createdNotebook: NotebookManifest?
        do {
            let manifest = try await store.createNotebook(
                title: notebookTitle.isEmpty ? "Imported PDF" : notebookTitle
            )
            createdNotebook = manifest

            let assetName = try await store.addAsset(scan.data, fileExtension: "pdf", to: manifest.id)

            var pageIDs: [UUID] = []
            pageIDs.reserveCapacity(scan.pages.count)
            for (done, scanned) in scan.pages.enumerated() {
                // A cancelled import leaves nothing behind: the catch below
                // removes the half-created notebook.
                try Task.checkCancellation()
                let page = makePage(scanned, assetName: assetName, margin: margin)
                try await store.savePage(page, in: manifest.id)
                pageIDs.append(page.id)
                onProgress?(0.5 + 0.5 * Double(done + 1) / Double(scan.pages.count))
            }
            guard !pageIDs.isEmpty else { throw PDFImportError.noPages }

            let titles = pageTitles(
                outline: scan.outline,
                pdfPages: scan.pages.map(\.index),
                pageIDs: pageIDs
            )
            return PDFImportResult(
                manifest: try await store.loadManifest(manifest.id),
                titles: titles
            )
        } catch {
            // A half-created notebook would list as an empty import.
            if let createdNotebook {
                try? await store.deleteNotebook(createdNotebook.id)
                try? await store.purgeNotebook(createdNotebook.id)
            }
            throw error
        }
    }

    // MARK: - Existing notebook

    /// Inserts the selected pages after the current page, or at the end of the
    /// notebook, and shows the first one.
    static func insertPages(
        at url: URL,
        into session: NotebookSession,
        selection: PDFPageSelection,
        atEnd: Bool = false,
        margin: PDFPageMargin = .none,
        password: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> PDFPageInsertResult {
        let store = session.store
        let notebookID = session.notebookID

        let scan = try await scan(
            at: url,
            selection: selection,
            password: password,
            progress: scaledProgress(onProgress, to: 0.8)
        )

        // Nothing is written until the scan is done, so a cancel here leaves the
        // notebook exactly as it was.
        try Task.checkCancellation()
        let assetName = try await store.addAsset(scan.data, fileExtension: "pdf", to: notebookID)
        try Task.checkCancellation()
        let pages = scan.pages.map { makePage($0, assetName: assetName, margin: margin) }
        let index = atEnd ? session.pageCount : session.pageIndex + 1

        let inserted = try await session.insertPages(pages, at: index) { written, total in
            onProgress?(0.8 + 0.2 * Double(written) / Double(max(total, 1)))
        }
        guard inserted == pages.count else {
            // The pages written before the failure are on disk and already in the
            // notebook, so say how many landed instead of a bare failure the user
            // would retry and duplicate.
            let insertedIDs = Set(pages.map(\.id))
            let added = session.manifest.pageOrder.filter(insertedIDs.contains).count
            guard added > 0 else { throw PDFImportError.insertFailed }
            throw PDFImportError.partialInsert(added: added, total: pages.count)
        }
        onProgress?(1)

        return PDFPageInsertResult(
            count: inserted,
            titles: pageTitles(
                outline: scan.outline,
                pdfPages: scan.pages.map(\.index),
                pageIDs: pages.map(\.id)
            )
        )
    }

    // MARK: - Reading

    private nonisolated struct ScannedPage: Sendable {
        let index: Int
        let size: CGSize
        /// Ink annotations already in page points.
        let strokes: [PDFInkStroke]
    }

    private nonisolated struct ScanResult: Sendable {
        /// The bytes to store as the notebook's PDF asset.
        let data: Data
        let pages: [ScannedPage]
        let outline: [PDFOutlineItem]
    }

    /// Reads the selected pages off the main task: their size, their ink
    /// annotations as page-space strokes, the document outline, and the bytes
    /// the notebook should keep.
    private nonisolated static func scan(
        at url: URL,
        selection: PDFPageSelection,
        password: String?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> ScanResult {
        let fallbackPageSize = CGSize(width: PageDefaults.width, height: PageDefaults.height)
        // A detached task does not inherit the caller's cancellation, so it is
        // forwarded: a cancelled import must not keep scanning a 1 000-page PDF.
        return try await detached(priority: .userInitiated) { () throws -> ScanResult in
            let (document, originalData) = try open(url, password: password)
            let indices = selection.pdfIndices(pageCount: document.pageCount)
            guard !indices.isEmpty else { throw PDFImportError.noPages }

            var pages: [ScannedPage] = []
            pages.reserveCapacity(indices.count)
            var hasInk = false
            for (done, index) in indices.enumerated() {
                try Task.checkCancellation()
                guard let pdfPage = document.page(at: index) else { continue }
                var bounds = pdfPage.bounds(for: .mediaBox)
                if bounds.width <= 1 || bounds.height <= 1 {
                    bounds = CGRect(origin: .zero, size: fallbackPageSize)
                }
                let strokes = PDFImportConversion.inkStrokes(in: pdfPage, pageSize: bounds.size)
                if !strokes.isEmpty { hasInk = true }
                pages.append(ScannedPage(index: index, size: bounds.size, strokes: strokes))
                progress?(Double(done + 1) / Double(indices.count))
            }
            guard !pages.isEmpty else { throw PDFImportError.noPages }

            // The outline is read before the stored copy is rewritten: building
            // the copy can remove annotations from the pages below.
            let outline = PDFImportConversion.outlineItems(in: document)

            let stored: Data
            if !document.isEncrypted && !hasInk {
                // Nothing to change: keep the file byte for byte, so importing
                // the same PDF twice reuses one asset.
                stored = originalData
            } else if let rewritten = PDFImportConversion.data(
                removingInkAnnotationsOn: Set(indices),
                from: document
            ) {
                // A fresh document also drops the encryption of an unlocked
                // file, so the asset opens later without the password.
                stored = rewritten
            } else {
                throw PDFImportError.unreadablePDF
            }

            return ScanResult(data: stored, pages: pages, outline: outline)
        }
    }

    /// Opens the PDF, unlocking it when needed, and hands back the bytes it was
    /// read from. Reading happens off the main task, so everything here is
    /// nonisolated.
    private nonisolated static func open(
        _ url: URL,
        password: String?
    ) throws -> (document: PDFDocument, data: Data) {
        let data = try readData(at: url)
        guard let document = PDFDocument(data: data) else { throw PDFImportError.unreadablePDF }
        if document.isLocked {
            guard let password, !password.isEmpty else { throw PDFImportError.passwordRequired }
            guard document.unlock(withPassword: password) else { throw PDFImportError.wrongPassword }
        }
        guard document.pageCount > 0 else { throw PDFImportError.emptyPDF }
        return (document, data)
    }

    private nonisolated static func readData(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw PDFImportError.unreadablePDF
        }
    }

    private nonisolated static func scaledProgress(
        _ progress: (@Sendable (Double) -> Void)?,
        to share: Double
    ) -> (@Sendable (Double) -> Void)? {
        guard let progress else { return nil }
        return { fraction in progress(fraction * share) }
    }

    /// Runs `work` off the main task and forwards the caller's cancellation to
    /// it. `Task.detached` does not inherit cancellation on its own, so without
    /// this a cancelled import would keep scanning every page.
    private nonisolated static func detached<T: Sendable>(
        priority: TaskPriority = .userInitiated,
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let task = Task.detached(priority: priority, operation: work)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Pages

    /// One notebook page backed by one PDF page, with its imported ink on the
    /// page's only layer. A writing margin widens the page and moves the PDF
    /// and its ink across, so both keep their own size and position.
    private static func makePage(
        _ scanned: ScannedPage,
        assetName: String,
        margin: PDFPageMargin
    ) -> Page {
        let layer = Page.Layer(id: UUID(), name: "Layer 1")
        let left = margin.leftInset
        let right = margin.rightInset
        let element = PageElement(
            id: UUID(),
            layerID: layer.id,
            frame: ElementFrame(
                x: left,
                y: 0,
                width: scanned.size.width,
                height: scanned.size.height
            ),
            zIndex: 0,
            updatedAt: Date(),
            content: .pdfPage(assetName: assetName, pageIndex: scanned.index)
        )
        let strokes = PDFImportConversion.strokeRecords(
            for: scanned.strokes,
            layerID: layer.id
        )
        return Page(
            id: UUID(),
            width: scanned.size.width + left + right,
            height: scanned.size.height,
            template: .blank,
            layers: [layer],
            strokes: left > 0 ? strokes.map { $0.translatedBy(x: left) } : strokes,
            elements: [element]
        )
    }

    /// Outline entries become page titles. The outline model is flat, so
    /// nesting is shown with indentation. When several entries point at one
    /// page the first (shallowest) one names it.
    private static func pageTitles(
        outline: [PDFOutlineItem],
        pdfPages: [Int],
        pageIDs: [UUID]
    ) -> [UUID: String] {
        guard pdfPages.count == pageIDs.count else { return [:] }
        var pageIDByPDFIndex: [Int: UUID] = [:]
        for (pdfIndex, pageID) in zip(pdfPages, pageIDs) {
            pageIDByPDFIndex[pdfIndex] = pageID
        }

        var titles: [UUID: String] = [:]
        for item in outline {
            guard let pdfIndex = item.pageIndex,
                  let pageID = pageIDByPDFIndex[pdfIndex],
                  titles[pageID] == nil
            else { continue }
            let indent = String(repeating: "    ", count: min(max(item.depth, 0), 6))
            titles[pageID] = indent + item.title
        }
        return titles
    }
}

private extension StrokeRecord {
    /// The stroke moved sideways, for a page that grew a writing margin. The
    /// points stay in PDF page space and the stroke's own transform carries the
    /// shift, the same way a moved stroke is stored.
    func translatedBy(x: Double) -> StrokeRecord {
        guard transform.count == StrokeRecord.transformElementCount else { return self }
        var moved = self
        moved.transform[4] += x
        return moved
    }
}
