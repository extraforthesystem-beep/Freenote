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
    /// Copies the PDF into the notebook's assets once and makes one notebook page
    /// per PDF page, each with a full-page pdfPage element.
    static func importPDF(
        at url: URL,
        into store: LibraryStore,
        title: String? = nil
    ) async throws -> NotebookManifest {
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

        let notebookTitle = (title ?? url.deletingPathExtension().lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let manifest = try await store.createNotebook(
            title: notebookTitle.isEmpty ? "Imported PDF" : notebookTitle
        )
        let assetName = try await store.addAsset(data, fileExtension: "pdf", to: manifest.id)

        var imported = 0
        for index in 0..<document.pageCount {
            guard let pdfPage = document.page(at: index) else { continue }
            var bounds = pdfPage.bounds(for: .mediaBox)
            if bounds.width <= 1 || bounds.height <= 1 {
                bounds = CGRect(x: 0, y: 0, width: PageDefaults.width, height: PageDefaults.height)
            }

            let layer = Page.Layer(id: UUID(), name: "Layer 1")
            let element = PageElement(
                id: UUID(),
                layerID: layer.id,
                frame: ElementFrame(
                    x: 0,
                    y: 0,
                    width: bounds.width,
                    height: bounds.height
                ),
                zIndex: 0,
                updatedAt: Date(),
                content: .pdfPage(assetName: assetName, pageIndex: index)
            )
            let page = Page(
                id: UUID(),
                width: bounds.width,
                height: bounds.height,
                template: .blank,
                layers: [layer],
                elements: [element]
            )
            try await store.savePage(page, in: manifest.id)
            imported += 1
        }

        guard imported > 0 else { throw PDFImportError.noPages }
        return try await store.loadManifest(manifest.id)
    }
}
