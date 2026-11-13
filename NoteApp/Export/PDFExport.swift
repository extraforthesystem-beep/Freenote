import CoreGraphics
import Foundation
import InkKit
import NoteCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
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
    /// True during the second pass of an editable export, when each page's
    /// ink is written as annotations.
    var isAddingAnnotations = false

    /// 0...1, for a determinate `ProgressView`.
    var fraction: Double {
        pageCount > 0 ? Double(pagesCompleted) / Double(pageCount) : 0
    }
}

/// What a PDF export contains.
nonisolated struct PDFExportOptions: Sendable, Equatable {
    enum Pages: Sendable, Equatable {
        case all
        case current
        /// One-based, inclusive.
        case range(from: Int, to: Int)
    }

    enum Ink: String, Sendable, CaseIterable, Identifiable {
        /// Ink drawn into the page as vector outlines.
        case flattened
        /// Ink written as PDF ink annotations other apps can edit. Translucent
        /// ink (highlighters) is drawn into the page instead: PDFKit cannot
        /// store an annotation's opacity, so it would come out solid.
        case editable

        var id: String { rawValue }
    }

    var pages: Pages = .all
    var includeTemplate = true
    var ink: Ink = .flattened
    var includeOutline = true

    /// The zero-based page indices to export, in order, for a notebook of
    /// `pageCount` pages whose current page is `currentIndex`.
    func pageIndices(pageCount: Int, currentIndex: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        switch pages {
        case .all:
            return Array(0..<pageCount)
        case .current:
            return [min(max(currentIndex, 0), pageCount - 1)]
        case let .range(from, to):
            let low = min(max(min(from, to), 1), pageCount)
            let high = min(max(max(from, to), 1), pageCount)
            return Array((low - 1)...(high - 1))
        }
    }
}

@MainActor
enum NotebookExporter {
    /// Renders one page at print resolution and returns PNG bytes.
    ///
    /// Drawn and encoded off the main actor: a scanned PDF page takes tens of
    /// milliseconds to draw at 2×, and encoding a page-sized PNG costs as much
    /// again, both of which stalled the editor when they ran inline. Ink is
    /// always drawn as stored — `PageRenderer` forces the light appearance for
    /// it — so a dark-mode export never comes out inverted.
    static func pngData(
        page: Page,
        assetsDirectory: URL?,
        scale: CGFloat = 2
    ) async -> Data? {
        await Task.detached(priority: .userInitiated) { () -> Data? in
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
        }.value
    }

    /// Exports the pages `options` selects as one vector PDF, one PDF page per
    /// notebook page.
    ///
    /// Pages are loaded and drawn one at a time off the main actor, straight
    /// into a temporary file, so a long notebook neither blocks the UI nor
    /// holds more than one page in memory. Editable exports then reopen the
    /// file with PDFKit and add each page's opaque ink as annotations, again
    /// one page at a time; translucent ink was drawn into the page, because an
    /// annotation cannot carry its opacity (see `VectorPDFAnnotations`).
    /// `outlineTitles` maps page IDs to outline entries. `progress` is called
    /// on the main actor after each page.
    static func pdfData(
        session: NotebookSession,
        options: PDFExportOptions = PDFExportOptions(),
        outlineTitles: [UUID: String] = [:],
        progress: (@MainActor @Sendable (PDFExportProgress) -> Void)? = nil
    ) async throws -> Data {
        let order = session.manifest.pageOrder
        let indices = options.pageIndices(pageCount: order.count, currentIndex: session.pageIndex)
        guard !indices.isEmpty else { throw NotebookExportError.emptyNotebook }
        let pageIDs = indices.map { order[$0] }

        let store = session.store
        let notebookID = session.notebookID
        let assetsDirectory = session.assetsDirectory
        let title = session.manifest.title
        let creator = appName
        let outline: [(pageIndex: Int, title: String)] = options.includeOutline
            ? pageIDs.enumerated().compactMap { index, pageID in
                outlineTitles[pageID].map { (index, $0) }
            }
            : []
        let pageCount = pageIDs.count

        return try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("export-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: url) }

            guard let writer = VectorPDFWriter(url: url, title: title, creator: creator) else {
                throw NotebookExportError.couldNotCreatePDF
            }
            for (index, pageID) in pageIDs.enumerated() {
                if Task.isCancelled { throw CancellationError() }
                let page: Page
                do {
                    page = try await store.loadPage(pageID, in: notebookID)
                } catch {
                    throw NotebookExportError.couldNotRenderPage(indices[index] + 1)
                }
                // An editable export writes only opaque ink as annotations;
                // translucent ink (highlighters) is drawn into the page, since
                // PDFKit cannot store an annotation's opacity and would export
                // it solid. See `VectorPDFAnnotations.isTranslucent`.
                var drawnPage = page
                var includeInk = options.ink == .flattened
                if options.ink == .editable {
                    drawnPage.strokes = page.renderStrokes.filter(VectorPDFAnnotations.isTranslucent)
                    includeInk = !drawnPage.strokes.isEmpty
                }
                writer.addPage(
                    drawnPage,
                    assetsDirectory: assetsDirectory,
                    includeTemplate: options.includeTemplate,
                    includeInk: includeInk
                )
                if let progress {
                    await progress(PDFExportProgress(pagesCompleted: index + 1, pageCount: pageCount))
                }
            }
            writer.setOutline(outline)
            writer.close()

            guard options.ink == .editable else {
                return try Data(contentsOf: url)
            }

            guard let document = PDFDocument(url: url) else {
                throw NotebookExportError.couldNotCreatePDF
            }
            for (index, pageID) in pageIDs.enumerated() {
                if Task.isCancelled { throw CancellationError() }
                let page: Page
                do {
                    page = try await store.loadPage(pageID, in: notebookID)
                } catch {
                    throw NotebookExportError.couldNotRenderPage(indices[index] + 1)
                }
                if let pdfPage = document.page(at: index) {
                    // Opaque ink only: translucent ink was drawn into the page
                    // above, because PDFKit cannot store an ink annotation's
                    // opacity (see `VectorPDFAnnotations.isTranslucent`).
                    VectorPDFAnnotations.addInkAnnotations(
                        for: page.renderStrokes,
                        to: pdfPage,
                        pageHeight: CGFloat(page.height)
                    )
                }
                if let progress {
                    await progress(
                        PDFExportProgress(
                            pagesCompleted: index + 1,
                            pageCount: pageCount,
                            isAddingAnnotations: true
                        )
                    )
                }
            }
            guard let data = document.dataRepresentation() else {
                throw NotebookExportError.couldNotCreatePDF
            }
            return data
        }.value
    }

    /// The app's display name, for the PDF's Creator field.
    private static var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "NoteApp"
    }
}
