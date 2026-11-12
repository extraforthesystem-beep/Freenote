import CoreGraphics
import Foundation
import InkKit
import NoteCore
import SwiftUI
import UniformTypeIdentifiers

/// A generated PDF, ready for SwiftUI's file exporter.
struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum NotebookExportError: LocalizedError {
    case emptyNotebook
    case couldNotCreatePDF
    case couldNotRenderPage(Int)

    var errorDescription: String? {
        switch self {
        case .emptyNotebook: "This notebook has no pages to export."
        case .couldNotCreatePDF: "The PDF could not be created."
        case .couldNotRenderPage(let number): "Page \(number) could not be rendered."
        }
    }
}

@MainActor
enum NotebookExporter {
    /// Renders every page in order and returns one PDF, one page per notebook page.
    static func pdfData(session: NotebookSession, scale: CGFloat = 2) async throws -> Data {
        let order = session.manifest.pageOrder
        guard !order.isEmpty else { throw NotebookExportError.emptyNotebook }

        var pages: [Page] = []
        for (index, pageID) in order.enumerated() {
            do {
                pages.append(try await session.store.loadPage(pageID, in: session.notebookID))
            } catch {
                throw NotebookExportError.couldNotRenderPage(index + 1)
            }
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw NotebookExportError.couldNotCreatePDF
        }
        let first = pages[0]
        var mediaBox = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NotebookExportError.couldNotCreatePDF
        }

        for (index, page) in pages.enumerated() {
            let size = CGSize(width: page.width, height: page.height)
            var box = CGRect(origin: .zero, size: size)
            let boxData = withUnsafeBytes(of: &box) { Data($0) }
            context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)

            guard let image = PageRenderer.image(
                strokes: page.strokes,
                pageSize: size,
                template: page.template,
                elements: page.elements,
                assetsDirectory: session.assetsDirectory,
                scale: scale
            ), let cgImage = image.cgImageForExport else {
                context.endPDFPage()
                context.closePDF()
                throw NotebookExportError.couldNotRenderPage(index + 1)
            }

            // The bitmap already has page orientation; CGImage draws upright in
            // the PDF's y-up space, so no extra flip here.
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }
}

private extension InkImage {
    var cgImageForExport: CGImage? {
        #if os(iOS)
        cgImage
        #else
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}
