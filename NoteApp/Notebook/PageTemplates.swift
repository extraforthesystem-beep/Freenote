import Foundation
import CoreGraphics
import InkKit
import NoteCore

/// One choice in the page template picker.
struct PageTemplateItem: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case basics = "Basics"
        case planning = "Planning"
        case creative = "Creative"

        var id: String { rawValue }
    }

    let id: String
    let name: String
    let category: Category
    let template: PageTemplate
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
