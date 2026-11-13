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
    static let pageWidth: Double = 595
    static let pageHeight: Double = 842
    static let pageSize = CGSize(width: pageWidth, height: pageHeight)

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

@MainActor
enum TemplateImageCache {
    private static let cache: NSCache<NSString, InkImage> = {
        let cache = NSCache<NSString, InkImage>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func removeAll() {
        cache.removeAllObjects()
    }

    static func image(
        for template: PageTemplate,
        pageSize: CGSize = PageTemplateCatalog.pageSize,
        scale: CGFloat = 2
    ) -> InkImage? {
        let key = "\(template.kind)-\(template.spacing)-\(template.lineColor)-\(template.paperColor)-\(pageSize)-\(scale)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = TemplateRenderer.image(template, pageSize: pageSize, scale: scale) else {
            return nil
        }
        let cost = Int(pageSize.width * pageSize.height * scale * scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    static func preview(for template: PageTemplate) -> InkImage? {
        image(for: template, pageSize: PageTemplateCatalog.pageSize, scale: 0.8)
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

    private let root: URL
    @ObservationIgnored private let previews: NSCache<NSString, InkImage> = {
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

    private func fileURL(for template: CustomPageTemplate) -> URL {
        root.appendingPathComponent(template.assetName)
    }

    // MARK: - Reading

    /// Re-reads the index. Templates whose file has gone are left out, so a
    /// deleted or half-copied file cannot show as a blank thumbnail.
    func load() {
        guard let data = try? Data(contentsOf: indexFile),
              let stored = try? JSONDecoder().decode([CustomPageTemplate].self, from: data)
        else {
            templates = []
            return
        }
        templates = stored.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
    }

    func preview(for template: CustomPageTemplate) -> InkImage? {
        let key = "\(template.assetName)-\(PageTemplateCatalog.pageWidth)x\(PageTemplateCatalog.pageHeight)" as NSString
        if let cached = previews.object(forKey: key) { return cached }
        guard let image = TemplateRenderer.image(
            template.template,
            pageSize: PageTemplateCatalog.pageSize,
            scale: 0.8,
            assetsDirectory: root
        ) else { return nil }
        previews.setObject(image, forKey: key)
        return image
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
        let bytes: Data?
        if isPDF {
            bytes = await Self.rasterisedFirstPage(at: url)
        } else {
            bytes = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url)
            }.value
        }
        guard let bytes, !bytes.isEmpty else { throw CustomTemplateError.unreadableFile }

        let fileExtension = isPDF ? "png" : Self.imageExtension(for: bytes, url: url)
        guard isPDF || Self.isReadableImage(bytes) else { throw CustomTemplateError.unreadableFile }

        let template = CustomPageTemplate(
            id: UUID(),
            name: trimmed,
            assetName: try writeTemplateFile(bytes, fileExtension: fileExtension)
        )
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
        previews.removeAllObjects()
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(templates).write(to: indexFile, options: .atomic)
        } catch {
            // A template that cannot be indexed is still usable this session;
            // the next import rewrites the index.
        }
    }

    private func writeTemplateFile(_ data: Data, fileExtension: String) throws -> String {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = Self.hexString(Data(SHA256.hash(data: data))) + "." + fileExtension
        let file = root.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: file.path) {
            try data.write(to: file, options: .atomic)
        }
        return name
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// The extension to store a picture under. Kept from the file, or PNG when
    /// it has none; only our own loaders read it.
    private static func imageExtension(for data: Data, url: URL) -> String {
        let stored = url.pathExtension.lowercased()
        if !stored.isEmpty { return stored }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source)
        else { return "png" }
        return (type as String).split(separator: ".").last.map(String.init)?.lowercased() ?? "png"
    }

    private static func isReadableImage(_ data: Data) -> Bool {
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
