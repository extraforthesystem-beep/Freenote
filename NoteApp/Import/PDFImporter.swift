import Foundation
import NoteCore
import PDFKit

enum PDFImportError: LocalizedError {
    case unreadablePDF
    case emptyPDF
    case noPages

    var errorDescription: String? {
        switch self {
        case .unreadablePDF: "This file is not a PDF the app can read."
        case .emptyPDF: "The PDF has no pages."
        case .noPages: "No page could be imported."
        }
    }
}

@MainActor
enum PDFImporter {
    /// One PDF page found while scanning the document off the main actor.
    private nonisolated struct ScannedPage: Sendable {
        let index: Int
        let size: CGSize
    }

    private nonisolated struct ScanResult: Sendable {
        let data: Data
        let pages: [ScannedPage]
    }

    /// Copies the PDF into the notebook's assets once and makes one notebook page
    /// per PDF page, each with a full-page pdfPage element.
    ///
    /// Reading and parsing happen off the main actor. If anything fails after
    /// the notebook was created, the half-created notebook is removed again so
    /// the library is never left with an empty import.
    static func importPDF(
        at url: URL,
        into store: LibraryStore,
        title: String? = nil
    ) async throws -> NotebookManifest {
        let fallbackPageSize = CGSize(width: PageDefaults.width, height: PageDefaults.height)
        let scan = try await scanPDF(at: url, fallbackPageSize: fallbackPageSize)

        let notebookTitle = (title ?? url.deletingPathExtension().lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var createdNotebook: NotebookManifest?
        do {
            let manifest = try await store.createNotebook(
                title: notebookTitle.isEmpty ? "Imported PDF" : notebookTitle
            )
            createdNotebook = manifest

            let assetName = try await store.addAsset(scan.data, fileExtension: "pdf", to: manifest.id)

            var imported = 0
            for scanned in scan.pages {
                let layer = Page.Layer(id: UUID(), name: "Layer 1")
                let element = PageElement(
                    id: UUID(),
                    layerID: layer.id,
                    frame: ElementFrame(
                        x: 0,
                        y: 0,
                        width: scanned.size.width,
                        height: scanned.size.height
                    ),
                    zIndex: 0,
                    updatedAt: Date(),
                    content: .pdfPage(assetName: assetName, pageIndex: scanned.index)
                )
                let page = Page(
                    id: UUID(),
                    width: scanned.size.width,
                    height: scanned.size.height,
                    template: .blank,
                    layers: [layer],
                    elements: [element]
                )
                try await store.savePage(page, in: manifest.id)
                imported += 1
            }

            guard imported > 0 else { throw PDFImportError.noPages }
            return try await store.loadManifest(manifest.id)
        } catch {
            if let createdNotebook {
                try? await store.deleteNotebook(createdNotebook.id)
                try? await store.purgeNotebook(createdNotebook.id)
            }
            throw error
        }
    }

    /// Reads and inspects the PDF on a background task, returning only values
    /// safe to cross back to the main actor.
    private nonisolated static func scanPDF(
        at url: URL,
        fallbackPageSize: CGSize
    ) async throws -> ScanResult {
        try await Task.detached(priority: .userInitiated) { () throws -> ScanResult in
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw PDFImportError.unreadablePDF
            }

            guard let document = PDFDocument(data: data) else {
                throw PDFImportError.unreadablePDF
            }
            guard document.pageCount > 0 else {
                throw PDFImportError.emptyPDF
            }

            var pages: [ScannedPage] = []
            pages.reserveCapacity(document.pageCount)
            for index in 0..<document.pageCount {
                guard let pdfPage = document.page(at: index) else { continue }
                var bounds = pdfPage.bounds(for: .mediaBox)
                if bounds.width <= 1 || bounds.height <= 1 {
                    bounds = CGRect(origin: .zero, size: fallbackPageSize)
                }
                pages.append(ScannedPage(index: index, size: bounds.size))
            }

            guard !pages.isEmpty else { throw PDFImportError.noPages }
            return ScanResult(data: data, pages: pages)
        }.value
    }
}
