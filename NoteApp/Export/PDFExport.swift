import CoreGraphics
import Foundation
import InkKit
import NoteCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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

/// A single page rendered as a PNG, ready for SwiftUI's file exporter.
struct PNGExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    static var writableContentTypes: [UTType] { [.png] }

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

nonisolated enum NotebookExportError: LocalizedError {
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

/// How far a notebook PDF export has got. Reported once per finished page.
nonisolated struct PDFExportProgress: Sendable, Equatable {
    var pagesCompleted: Int
    var pageCount: Int

    /// 0...1, for a determinate `ProgressView`.
    var fraction: Double {
        pageCount > 0 ? Double(pagesCompleted) / Double(pageCount) : 0
    }
}

@MainActor
enum NotebookExporter {
    /// Renders one page at print resolution and returns PNG bytes.
    static func pngData(
        page: Page,
        assetsDirectory: URL?,
        scale: CGFloat = 2
    ) -> Data? {
        guard let image = PageRenderer.image(
            strokes: page.renderStrokes,
            pageSize: CGSize(width: page.width, height: page.height),
            template: page.template,
            elements: page.visibleElements,
            assetsDirectory: assetsDirectory,
            scale: scale
        ) else { return nil }

        #if os(iOS)
        return image.pngData()
        #else
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff)
        else { return nil }
        return representation.representation(using: .png, properties: [:])
        #endif
    }

    /// Renders every page in order and returns one PDF, one page per notebook page.
    ///
    /// Pages are rendered one at a time off the main actor and drawn straight
    /// into the PDF as they finish, so a long notebook neither blocks the UI
    /// nor needs every page bitmap in memory. `progress` is called on the main
    /// actor after each page.
    static func pdfData(
        session: NotebookSession,
        scale: CGFloat = 2,
        progress: (@MainActor @Sendable (PDFExportProgress) -> Void)? = nil
    ) async throws -> Data {
        let order = session.manifest.pageOrder
        guard !order.isEmpty else { throw NotebookExportError.emptyNotebook }

        let store = session.store
        let notebookID = session.notebookID
        let assetsDirectory = session.assetsDirectory
        let pageCount = order.count

        return try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let data = NSMutableData()
            guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
                throw NotebookExportError.couldNotCreatePDF
            }

            var context: CGContext?
            defer { context?.closePDF() }

            for (index, pageID) in order.enumerated() {
                if Task.isCancelled { throw CancellationError() }

                let page: Page
                do {
                    page = try await store.loadPage(pageID, in: notebookID)
                } catch {
                    throw NotebookExportError.couldNotRenderPage(index + 1)
                }

                let size = CGSize(width: page.width, height: page.height)
                guard let cgImage = render(page: page, size: size, assetsDirectory: assetsDirectory, scale: scale) else {
                    throw NotebookExportError.couldNotRenderPage(index + 1)
                }

                if context == nil {
                    var mediaBox = CGRect(origin: .zero, size: size)
                    guard let created = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                        throw NotebookExportError.couldNotCreatePDF
                    }
                    context = created
                }
                guard let context else { throw NotebookExportError.couldNotCreatePDF }

                var box = CGRect(origin: .zero, size: size)
                let boxData = withUnsafeBytes(of: &box) { Data($0) }
                context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)

                // The bitmap already has page orientation; CGImage draws upright in
                // the PDF's y-up space, so no extra flip here.
                context.draw(cgImage, in: CGRect(origin: .zero, size: size))
                context.endPDFPage()

                if let progress {
                    await progress(
                        PDFExportProgress(pagesCompleted: index + 1, pageCount: pageCount)
                    )
                }
            }

            // Finish the PDF before handing the bytes out; the defer above only
            // covers throwing paths.
            context?.closePDF()
            context = nil
            return data as Data
        }.value
    }

    /// Renders one page and returns its bitmap, without any actor isolation so
    /// the export can call it from a background task.
    private nonisolated static func render(
        page: Page,
        size: CGSize,
        assetsDirectory: URL?,
        scale: CGFloat
    ) -> CGImage? {
        guard let image = PageRenderer.image(
            strokes: page.renderStrokes,
            pageSize: size,
            template: page.template,
            elements: page.visibleElements,
            assetsDirectory: assetsDirectory,
            scale: scale
        ) else { return nil }
        return image.cgImageForExport
    }
}

private extension InkImage {
    nonisolated var cgImageForExport: CGImage? {
        #if os(iOS)
        cgImage
        #else
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}
