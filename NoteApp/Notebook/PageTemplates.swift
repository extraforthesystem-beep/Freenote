import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import InkKit
import NoteCore
import Observation
import PDFKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// One choice in the page template picker.
struct PageTemplateItem: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case basics = "Basics"
        case planning = "Planning"
        case creative = "Creative"
        /// Imported templates; the picker fills this section from the store.
        case custom = "Custom"

        var id: String { rawValue }
    }

    let id: String
    let name: String
    let category: Category
    let template: PageTemplate
    /// The imported template behind this item, when it is a custom one.
    var custom: CustomPageTemplate?
}

enum PageTemplateCatalog {
    // Read off the main actor too: previews are drawn in a detached task.
    nonisolated static let pageWidth: Double = 595
    nonisolated static let pageHeight: Double = 842
    nonisolated static let pageSize = CGSize(width: pageWidth, height: pageHeight)

    static let lineColor = RGBAColor(r: 0.60, g: 0.67, b: 0.77)
    static let warmLineColor = RGBAColor(r: 0.68, g: 0.62, b: 0.54)
    static let cream = RGBAColor(r: 0.995, g: 0.985, b: 0.955)

    static let all: [PageTemplateItem] = [
        item("blank", "Blank", .basics, "blank"),
        item("ruled-narrow", "Ruled · Narrow", .basics, "ruled", spacing: 18),
        item("ruled-medium", "Ruled · Medium", .basics, "ruled", spacing: 24),
        item("ruled-wide", "Ruled · Wide", .basics, "ruled", spacing: 32),
        item("ruled-margin", "Ruled · Margin", .basics, "ruled-margin", spacing: 24),
        item("grid-small", "Grid · Small", .basics, "grid", spacing: 12),
        item("grid-medium", "Grid · Medium", .basics, "grid", spacing: 18),
        item("grid-large", "Grid · Large", .basics, "grid", spacing: 24),
        item("dotted-small", "Dotted · Small", .basics, "dotted", spacing: 12),
        item("dotted-medium", "Dotted · Medium", .basics, "dotted", spacing: 18),
        item("dotted-large", "Dotted · Large", .basics, "dotted", spacing: 24),

        item("cornell", "Cornell Notes", .planning, "cornell", spacing: 24, paper: cream, line: warmLineColor),
        item("todo", "To-Do List", .planning, "todo", spacing: 30),
        item("meeting", "Meeting Notes", .planning, "meeting", spacing: 26),
        item("weekly", "Weekly Planner", .planning, "weekly", spacing: 0),
        item("monthly", "Monthly Planner", .planning, "monthly", spacing: 0),
        item("daily", "Daily Planner", .planning, "daily", spacing: 40),

        item("music", "Music Staff", .creative, "music", spacing: 0),
        item("isometric", "Isometric", .creative, "isometric", spacing: 24),
        item("hex", "Hexagon", .creative, "hex", spacing: 24),
        item("handwriting", "Handwriting Practice", .creative, "handwriting", spacing: 32),
        item("storyboard", "Storyboard", .creative, "storyboard", spacing: 0),
    ]

    static func items(in category: PageTemplateItem.Category) -> [PageTemplateItem] {
        all.filter { $0.category == category }
    }

    /// The picker's items for the imported templates, newest last.
    static func customItems(_ templates: [CustomPageTemplate]) -> [PageTemplateItem] {
        templates.map { template in
            PageTemplateItem(
                id: "custom-\(template.id.uuidString)",
                name: template.name,
                category: .custom,
                template: template.template,
                custom: template
            )
        }
    }

    static func name(for template: PageTemplate) -> String? {
        all.first { sameLayout($0.template, template) }?.name
    }

    static func sameLayout(_ a: PageTemplate, _ b: PageTemplate) -> Bool {
        a.kind == b.kind && abs(a.spacing - b.spacing) < 0.001
    }

    private static func item(
        _ id: String,
        _ name: String,
        _ category: PageTemplateItem.Category,
        _ kind: String,
        spacing: Double = 0,
        paper: RGBAColor = .white,
        line: RGBAColor = lineColor
    ) -> PageTemplateItem {
        PageTemplateItem(
            id: id,
            name: name,
            category: category,
            template: PageTemplate(kind: kind, spacing: spacing, lineColor: line, paperColor: paper)
        )
    }
}

/// The memory a bitmap takes, for the image caches' cost limits.
nonisolated func bitmapCost(_ image: InkImage) -> Int {
    #if os(iOS)
    let pixels = image.size.width * image.size.height * image.scale * image.scale
    #else
    let pixels = image.size.width * image.size.height
    #endif
    return Int(pixels * 4)
}

@MainActor
enum TemplateImageCache {
    /// Preview bitmaps are drawn at this scale; a picker cell is small.
    nonisolated static let previewScale: CGFloat = 0.8

    private static let cache: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func removeAll() {
        cache.removeAllObjects()
    }

    /// The preview if it is already drawn. Never draws: a view body must not.
    static func cachedPreview(for template: PageTemplate) -> InkImage? {
        cache.object(forKey: key(for: template))
    }

    /// Keeps a preview drawn off the main actor.
    static func storePreview(_ image: InkImage, for template: PageTemplate) {
        cache.setObject(image, forKey: key(for: template), cost: bitmapCost(image))
    }

    /// Draws a preview off the main actor. The caller stores it and shows it,
    /// so a cell's body never renders one.
    nonisolated static func renderedPreview(for template: PageTemplate) async -> InkImage? {
        await Task.detached(priority: .utility) {
            TemplateRenderer.image(
                template,
                pageSize: PageTemplateCatalog.pageSize,
                scale: previewScale
            )
        }.value
    }

    private static func key(for template: PageTemplate) -> NSString {
        let pageSize = PageTemplateCatalog.pageSize
        return "\(template.kind)-\(template.spacing)-\(template.lineColor)-\(template.paperColor)-\(pageSize)-\(previewScale)" as NSString
    }
}

/// A page template imported from a PDF page or a picture. The image lives in
/// the library's `templates` folder; applying it copies the same file into the
/// notebook's assets, so a page keeps its background wherever the notebook goes.
struct CustomPageTemplate: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// What the picker shows.
    var name: String
    /// The file name, shared by the template library and every notebook using it.
    var assetName: String

    var template: PageTemplate { .custom(assetName: assetName) }
}

enum CustomTemplateError: LocalizedError {
    case unreadableFile
    case nameRequired

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "That file is not a PDF or picture the app can read."
        case .nameRequired: "Give the template a name."
        }
    }
}

/// The app's imported page templates: one picture per template, plus a small
/// index file. Files are the truth here as everywhere else; the list is only
/// what the index says and what still exists on disk.
@MainActor
@Observable
final class CustomTemplateStore {
    /// The imported templates, oldest first.
    private(set) var templates: [CustomPageTemplate] = []
    /// The index file exists but could not be read. The list in memory is not
    /// the truth then, so the picker offers a retry instead of showing an empty
    /// Custom section, as though the templates had been deleted.
    private(set) var indexUnreadable = false

    private let root: URL
    /// Preview bitmaps, keyed by the template's file: the file name is a
    /// content hash, so two templates never share a key by accident. Static so
    /// a memory warning can empty it.
    @ObservationIgnored private static let previews: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    init(root: URL) {
        self.root = root
    }

    private var indexFile: URL {
        root.appendingPathComponent("index.json")
    }

    /// Where an index that could not be read is kept when the list is written
    /// again, so its bytes are never lost by a failed read.
    private var unreadableIndexFile: URL {
        root.appendingPathComponent("index-unreadable.json")
    }

    private func fileURL(for template: CustomPageTemplate) -> URL {
        root.appendingPathComponent(template.assetName)
    }

    static func removeAllPreviews() {
        previews.removeAllObjects()
    }

    // MARK: - Reading

    /// Re-reads the index. Templates whose file has gone are left out, so a
    /// deleted or half-copied file cannot show as a blank thumbnail.
    func load() {
        indexUnreadable = false
        templates = []
        guard FileManager.default.fileExists(atPath: indexFile.path) else { return }
        do {
            let data = try Data(contentsOf: indexFile)
            let stored = try JSONDecoder().decode([CustomPageTemplate].self, from: data)
            templates = stored.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        } catch {
            // A corrupt index is not an empty one: keep it and say so.
            indexUnreadable = true
        }
    }

    /// A drawn preview, if there is one. Never draws.
    func cachedPreview(for template: CustomPageTemplate) -> InkImage? {
        Self.previews.object(forKey: Self.previewKey(for: template))
    }

    /// Draws a template's preview off the main actor — it decodes the imported
    /// picture and draws the whole sheet — and keeps it for the next cell.
    func renderPreview(for template: CustomPageTemplate) async -> InkImage? {
        let key = Self.previewKey(for: template)
        if let cached = Self.previews.object(forKey: key) { return cached }
        let root = root
        let pageTemplate = template.template
        let rendered = await Task.detached(priority: .utility) {
            TemplateRenderer.image(
                pageTemplate,
                pageSize: PageTemplateCatalog.pageSize,
                scale: TemplateImageCache.previewScale,
                assetsDirectory: root
            )
        }.value
        guard let rendered else { return nil }
        Self.previews.setObject(rendered, forKey: key, cost: bitmapCost(rendered))
        return rendered
    }

    private static func previewKey(for template: CustomPageTemplate) -> NSString {
        "\(template.assetName)-\(PageTemplateCatalog.pageWidth)x\(PageTemplateCatalog.pageHeight)" as NSString
    }

    // MARK: - Importing

    /// Turns the chosen PDF (first page) or picture into a template. The file is
    /// read now and stored under a content hash, so importing it twice keeps one
    /// file and two names are still possible.
    func importTemplate(from url: URL, name: String) async throws -> CustomPageTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CustomTemplateError.nameRequired }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let isPDF = url.pathExtension.lowercased() == "pdf"
        // Reading (and checking) the file, then writing it under its content
        // hash, is one off-main job: a multi-megabyte picture or a rasterised
        // PDF page is not work for the actor that draws the UI.
        let root = root
        let assetName = try await Task.detached(priority: .userInitiated) {
            try await Self.storeCopy(of: url, isPDF: isPDF, in: root)
        }.value

        let template = CustomPageTemplate(id: UUID(), name: trimmed, assetName: assetName)
        templates.append(template)
        save()
        return template
    }

    func remove(_ template: CustomPageTemplate) {
        templates.removeAll { $0.id == template.id }
        // The same picture imported twice is one file, so it only goes when
        // nothing else names it.
        if !templates.contains(where: { $0.assetName == template.assetName }) {
            try? FileManager.default.removeItem(at: fileURL(for: template))
        }
        save()
        Self.previews.removeAllObjects()
    }

    // MARK: - Using

    /// Copies the template's picture into a notebook's assets, so the page can
    /// draw it through the notebook's own folder. Already there: nothing to do.
    func install(_ template: CustomPageTemplate, in assetsDirectory: URL?) {
        guard let assetsDirectory else { return }
        let destination = assetsDirectory.appendingPathComponent(template.assetName)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? FileManager.default.createDirectory(
            at: assetsDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.copyItem(at: fileURL(for: template), to: destination)
    }

    // MARK: - Files

    private func save() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if indexUnreadable {
                // The index on disk could not be read: keep its bytes beside
                // the new one rather than writing over it.
                try? FileManager.default.removeItem(at: unreadableIndexFile)
                try? FileManager.default.moveItem(at: indexFile, to: unreadableIndexFile)
                indexUnreadable = false
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(templates).write(to: indexFile, options: .atomic)
        } catch {
            // A template that cannot be indexed is still usable this session;
            // the next import rewrites the index.
        }
    }

    /// Reads the chosen file, checks it, and keeps a copy under its content
    /// hash. Synchronous and off the main actor, so the read, the check and the
    /// write are one job; the caller runs it in a detached task.
    private nonisolated static func storeCopy(of url: URL, isPDF: Bool, in root: URL) async throws -> String {
        let bytes: Data?
        if isPDF {
            bytes = await Self.rasterisedFirstPage(at: url)
        } else {
            bytes = try? Data(contentsOf: url)
        }
        guard let bytes, !bytes.isEmpty else { throw CustomTemplateError.unreadableFile }

        let fileExtension = isPDF ? "png" : Self.imageExtension(for: bytes, url: url)
        guard isPDF || Self.isReadableImage(bytes) else { throw CustomTemplateError.unreadableFile }

        return try writeTemplateFile(bytes, fileExtension: fileExtension, in: root)
    }

    private nonisolated static func writeTemplateFile(
        _ data: Data,
        fileExtension: String,
        in root: URL
    ) throws -> String {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = Self.hexString(Data(SHA256.hash(data: data))) + "." + fileExtension
        let file = root.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: file.path) {
            try data.write(to: file, options: .atomic)
        }
        return name
    }

    private nonisolated static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// The extension to store a picture under. Kept from the file, or PNG when
    /// it has none; only our own loaders read it.
    private nonisolated static func imageExtension(for data: Data, url: URL) -> String {
        let stored = url.pathExtension.lowercased()
        if !stored.isEmpty { return stored }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source)
        else { return "png" }
        return (type as String).split(separator: ".").last.map(String.init)?.lowercased() ?? "png"
    }

    private nonisolated static func isReadableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    /// The first page of a PDF, drawn once at template resolution. Rendering
    /// here rather than at draw time keeps the page render path to plain images.
    private nonisolated static func rasterisedFirstPage(at url: URL) async -> Data? {
        // A4 at 2×: enough detail for a planner page, small enough to draw once.
        let size = CGSize(width: 1190, height: 1684)
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
                return nil
            }
            let image = page.thumbnail(of: size, for: .mediaBox)
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
}
