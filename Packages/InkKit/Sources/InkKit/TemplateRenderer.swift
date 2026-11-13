import CoreGraphics
import CoreText
import Foundation
import NoteCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Draws the printed background of a page. One implementation is used for the
/// live page, thumbnails, the Mac reader and PDF export, so they cannot drift.
public enum TemplateRenderer {
    /// Draws `template` in page points into a context whose y axis already grows
    /// downwards, as `PageRenderer` sets it up.
    public static func draw(_ template: PageTemplate, in context: CGContext, pageSize: CGSize) {
        let page = CGRect(origin: .zero, size: pageSize)
        context.setFillColor(cgColor(template.paperColor))
        context.fill(page)

        let line = template.lineColor
        let spacing = template.spacing > 0 ? template.spacing : 24
        context.setStrokeColor(cgColor(line))
        context.setFillColor(cgColor(line))
        context.setLineWidth(0.8)
        context.clip(to: page)

        switch template.kind {
        case "ruled":
            horizontalLines(context, pageSize: pageSize, spacing: spacing, top: 44, bottom: 44)
        case "ruled-margin":
            horizontalLines(context, pageSize: pageSize, spacing: spacing, top: 44, bottom: 44)
            let margin = CGMutablePath()
            margin.move(to: CGPoint(x: 56, y: 0))
            margin.addLine(to: CGPoint(x: 56, y: pageSize.height))
            context.setStrokeColor(cgColor(RGBAColor(r: 0.86, g: 0.55, b: 0.55, a: 0.75)))
            context.setLineWidth(0.9)
            context.addPath(margin)
            context.strokePath()
            context.setStrokeColor(cgColor(line))
        case "grid":
            grid(context, pageSize: pageSize, spacing: spacing)
        case "dotted":
            dotted(context, pageSize: pageSize, spacing: spacing)
        case "cornell":
            cornell(context, pageSize: pageSize, spacing: spacing, color: line)
        case "todo":
            todo(context, pageSize: pageSize, spacing: spacing, color: line)
        case "meeting":
            meeting(context, pageSize: pageSize, spacing: spacing, color: line)
        case "weekly":
            weekly(context, pageSize: pageSize, spacing: spacing, color: line)
        case "monthly":
            monthly(context, pageSize: pageSize, color: line)
        case "daily":
            daily(context, pageSize: pageSize, spacing: max(32, spacing), color: line)
        case "music":
            music(context, pageSize: pageSize, color: line)
        case "isometric":
            isometric(context, pageSize: pageSize, spacing: max(18, spacing))
        case "hex":
            hexagons(context, pageSize: pageSize, radius: max(12, spacing * 0.7))
        case "handwriting":
            handwriting(context, pageSize: pageSize, spacing: max(28, spacing), color: line)
        case "storyboard":
            storyboard(context, pageSize: pageSize, color: line)
        default:
            break
        }
    }

    /// A bitmap of the template, for previews and for hosting behind the canvas.
    public static func image(
        _ template: PageTemplate,
        pageSize: CGSize,
        scale: CGFloat = 2
    ) -> InkImage? {
        guard pageSize.width > 0, pageSize.height > 0, scale > 0 else { return nil }
        let pixelWidth = Int((pageSize.width * scale).rounded(.up))
        let pixelHeight = Int((pageSize.height * scale).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        draw(template, in: context, pageSize: pageSize)

        guard let cgImage = context.makeImage() else { return nil }
        #if os(iOS)
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        #else
        return NSImage(cgImage: cgImage, size: pageSize)
        #endif
    }

    // MARK: - Basic patterns

    private static func horizontalLines(
        _ context: CGContext,
        pageSize: CGSize,
        spacing: Double,
        top: Double,
        bottom: Double
    ) {
        let path = CGMutablePath()
        var y = top
        while y < pageSize.height - bottom {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: pageSize.width, y: y))
            y += spacing
        }
        context.addPath(path)
        context.strokePath()
    }

    private static func grid(_ context: CGContext, pageSize: CGSize, spacing: Double) {
        let path = CGMutablePath()
        var y = spacing
        while y < pageSize.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: pageSize.width, y: y))
            y += spacing
        }
        var x = spacing
        while x < pageSize.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: pageSize.height))
            x += spacing
        }
        context.addPath(path)
        context.strokePath()
    }

    private static func dotted(_ context: CGContext, pageSize: CGSize, spacing: Double) {
        var y = spacing
        while y < pageSize.height {
            var x = spacing
            while x < pageSize.width {
                context.fillEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                x += spacing
            }
            y += spacing
        }
    }

    // MARK: - Structured templates

    private static func cornell(
        _ context: CGContext,
        pageSize: CGSize,
        spacing: Double,
        color: RGBAColor
    ) {
        let header: Double = 76
        let summaryTop = pageSize.height * 0.78
        let cueWidth = pageSize.width * 0.31
        let margin: Double = 40

        horizontalLines(context, pageSize: pageSize, spacing: spacing, top: header, bottom: pageSize.height - summaryTop)

        let divisions = CGMutablePath()
        divisions.move(to: CGPoint(x: cueWidth, y: header))
        divisions.addLine(to: CGPoint(x: cueWidth, y: summaryTop))
        divisions.move(to: CGPoint(x: margin, y: summaryTop))
        divisions.addLine(to: CGPoint(x: pageSize.width - margin, y: summaryTop))
        divisions.move(to: CGPoint(x: margin, y: header))
        divisions.addLine(to: CGPoint(x: pageSize.width - margin, y: header))
        context.setLineWidth(1.2)
        context.addPath(divisions)
        context.strokePath()

        drawText("Cue", at: CGPoint(x: 40, y: 52), size: 11, color: color, in: context)
        drawText("Notes", at: CGPoint(x: cueWidth + 16, y: 52), size: 11, color: color, in: context)
        drawText("Summary", at: CGPoint(x: 40, y: summaryTop + 14), size: 11, color: color, in: context)
    }

    private static func todo(
        _ context: CGContext,
        pageSize: CGSize,
        spacing: Double,
        color: RGBAColor
    ) {
        let left: Double = 44
        let box: Double = 14
        var y = 64.0
        let path = CGMutablePath()
        context.setLineWidth(0.9)
        while y < pageSize.height - 44 {
            let rect = CGRect(x: left, y: y - box / 2, width: box, height: box)
            context.stroke(rect)
            path.move(to: CGPoint(x: left + box + 14, y: y + 1))
            path.addLine(to: CGPoint(x: pageSize.width - 40, y: y + 1))
            y += spacing
        }
        context.addPath(path)
        context.strokePath()
        drawText("To-do", at: CGPoint(x: left, y: 24), size: 17, color: color, in: context)
    }

    private static func meeting(
        _ context: CGContext,
        pageSize: CGSize,
        spacing: Double,
        color: RGBAColor
    ) {
        let margin: Double = 44
        drawText("Meeting", at: CGPoint(x: margin, y: 26), size: 20, color: color, in: context)

        let titleLine = CGMutablePath()
        titleLine.move(to: CGPoint(x: margin, y: 56))
        titleLine.addLine(to: CGPoint(x: pageSize.width - margin, y: 56))
        context.setLineWidth(1)
        context.addPath(titleLine)
        context.strokePath()

        drawText("Date", at: CGPoint(x: margin, y: 66), size: 10, color: color, in: context)
        drawText("Attendees", at: CGPoint(x: margin, y: 92), size: 10, color: color, in: context)

        let fields = CGMutablePath()
        fields.move(to: CGPoint(x: margin + 46, y: 80))
        fields.addLine(to: CGPoint(x: pageSize.width - margin, y: 80))
        fields.move(to: CGPoint(x: margin + 68, y: 106))
        fields.addLine(to: CGPoint(x: pageSize.width - margin, y: 106))
        fields.move(to: CGPoint(x: margin, y: 124))
        fields.addLine(to: CGPoint(x: pageSize.width - margin, y: 124))
        context.addPath(fields)
        context.strokePath()

        horizontalLines(context, pageSize: pageSize, spacing: spacing, top: 146, bottom: 44)
    }

    private static func weekly(
        _ context: CGContext,
        pageSize: CGSize,
        spacing: Double,
        color: RGBAColor
    ) {
        let margin: Double = 36
        let top: Double = 84
        let bottom = pageSize.height - 40
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let columnWidth = (pageSize.width - margin * 2) / Double(days.count)
        let rowHeight = max(72, spacing > 0 ? spacing * 3 : 96)

        drawText("Week", at: CGPoint(x: margin, y: 26), size: 18, color: color, in: context)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: margin, y: top))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: top))
        for (index, day) in days.enumerated() {
            let x = margin + Double(index) * columnWidth
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: bottom))
            drawText(day, at: CGPoint(x: x + 6, y: 58), size: 10, color: color, in: context)
        }
        path.move(to: CGPoint(x: pageSize.width - margin, y: top))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: bottom))

        var y = top + rowHeight
        while y < bottom {
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
            y += rowHeight
        }

        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
    }

    private static func monthly(_ context: CGContext, pageSize: CGSize, color: RGBAColor) {
        let margin: Double = 32
        let header: Double = 70
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let rows = 5
        let columns = 7
        let width = (pageSize.width - margin * 2) / Double(columns)
        let height = (pageSize.height - header - 36) / Double(rows)

        drawText("Month", at: CGPoint(x: margin, y: 28), size: 18, color: color, in: context)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: margin, y: header))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: header))
        for row in 0...rows {
            let y = header + Double(row) * height
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        }
        for column in 0...columns {
            let x = margin + Double(column) * width
            path.move(to: CGPoint(x: x, y: header))
            path.addLine(to: CGPoint(x: x, y: header + Double(rows) * height))
        }
        context.setLineWidth(0.9)
        context.addPath(path)
        context.strokePath()

        for (index, day) in days.enumerated() {
            let x = margin + Double(index) * width
            drawText(day, at: CGPoint(x: x + 5, y: header - 16), size: 9, color: color, in: context)
        }
    }

    private static func daily(
        _ context: CGContext,
        pageSize: CGSize,
        spacing: Double,
        color: RGBAColor
    ) {
        let margin: Double = 56
        let start = 72.0
        drawText("Day", at: CGPoint(x: 28, y: 26), size: 18, color: color, in: context)

        var hour = 7
        var y = start
        let path = CGMutablePath()
        while y < pageSize.height - 40, hour <= 21 {
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageSize.width - 36, y: y))
            drawText(String(format: "%02d:00", hour), at: CGPoint(x: 12, y: y - 13), size: 9, color: color, in: context)
            hour += 1
            y += spacing
        }
        context.setLineWidth(0.8)
        context.addPath(path)
        context.strokePath()
    }

    // MARK: - Creative templates

    private static func music(_ context: CGContext, pageSize: CGSize, color: RGBAColor) {
        let left: Double = 42
        let right = pageSize.width - 42
        let lineGap: Double = 7
        let staffHeight = lineGap * 4
        let staffGap: Double = 52
        var top: Double = 64

        while top + staffHeight < pageSize.height - 40 {
            let path = CGMutablePath()
            for line in 0...4 {
                let y = top + lineGap * Double(line)
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: right, y: y))
            }
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: left, y: top + staffHeight))
            path.move(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: top + staffHeight))
            context.setLineWidth(0.7)
            context.addPath(path)
            context.strokePath()
            top += staffHeight + staffGap
        }
    }

    private static func isometric(_ context: CGContext, pageSize: CGSize, spacing: Double) {
        let path = CGMutablePath()
        let page = CGRect(origin: .zero, size: pageSize)
        let slope = tan(Double.pi / 6)
        let step = spacing * 1.6

        var x = 0.0
        while x <= pageSize.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: pageSize.height))
            x += step
        }

        // Lines rising to the right: y = slope * x + intercept.
        var intercept = -pageSize.width * slope
        while intercept <= pageSize.height {
            path.move(to: CGPoint(x: 0, y: intercept))
            path.addLine(to: CGPoint(x: pageSize.width, y: intercept + pageSize.width * slope))
            intercept += step
        }

        // Lines falling to the right: y = -slope * x + intercept.
        intercept = 0
        while intercept <= pageSize.height + pageSize.width * slope {
            path.move(to: CGPoint(x: 0, y: intercept))
            path.addLine(to: CGPoint(x: pageSize.width, y: intercept - pageSize.width * slope))
            intercept += step
        }

        context.saveGState()
        context.clip(to: page)
        context.setLineWidth(0.6)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func hexagons(_ context: CGContext, pageSize: CGSize, radius: Double) {
        let height = sqrt(3) * radius
        let horizontalStep = height
        let verticalStep = radius * 1.5
        let path = CGMutablePath()

        var row = 0
        var y = 0.0
        while y < pageSize.height + height {
            let offset = row % 2 == 0 ? 0.0 : horizontalStep / 2
            var x = -horizontalStep + offset
            while x < pageSize.width + horizontalStep {
                addHexagon(to: path, center: CGPoint(x: x, y: y), radius: radius)
                x += horizontalStep
            }
            row += 1
            y += verticalStep
        }

        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: pageSize))
        context.setLineWidth(0.6)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func addHexagon(to path: CGMutablePath, center: CGPoint, radius: Double) {
        let halfHeight = sqrt(3) / 2 * radius
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + halfHeight, y: center.y - radius / 2))
        path.addLine(to: CGPoint(x: center.x + halfHeight, y: center.y + radius / 2))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - halfHeight, y: center.y + radius / 2))
        path.addLine(to: CGPoint(x: center.x - halfHeight, y: center.y - radius / 2))
        path.closeSubpath()
    }

    private static func handwriting(
        _ context: CGContext,
        pageSize: CGSize,
        spacing: Double,
        color: RGBAColor
    ) {
        let margin: Double = 40
        var baseline = 120.0
        let guides = CGMutablePath()
        let baselines = CGMutablePath()

        while baseline < pageSize.height - 40 {
            guides.move(to: CGPoint(x: margin, y: baseline - spacing * 0.38))
            guides.addLine(to: CGPoint(x: pageSize.width - margin, y: baseline - spacing * 0.38))
            guides.move(to: CGPoint(x: margin, y: baseline + spacing * 0.22))
            guides.addLine(to: CGPoint(x: pageSize.width - margin, y: baseline + spacing * 0.22))
            baselines.move(to: CGPoint(x: margin, y: baseline))
            baselines.addLine(to: CGPoint(x: pageSize.width - margin, y: baseline))
            baseline += spacing
        }

        context.setLineDash(phase: 0, lengths: [3, 3])
        context.addPath(guides)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        context.setLineWidth(1)
        context.addPath(baselines)
        context.strokePath()
    }

    private static func storyboard(_ context: CGContext, pageSize: CGSize, color: RGBAColor) {
        let margin: Double = 36
        let gutter: Double = 18
        let columns = 3
        let rows = 3
        let width = (pageSize.width - margin * 2 - gutter * Double(columns - 1)) / Double(columns)
        let height = (pageSize.height - margin * 2 - gutter * Double(rows - 1)) / Double(rows)

        context.setLineWidth(1.1)
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(
                    x: margin + Double(column) * (width + gutter),
                    y: margin + Double(row) * (height + gutter),
                    width: width,
                    height: height
                )
                context.stroke(rect)
                drawText(
                    "\(row * columns + column + 1)",
                    at: CGPoint(x: rect.minX + 6, y: rect.minY + 6),
                    size: 9,
                    color: color,
                    in: context
                )
            }
        }
    }

    // MARK: - Helpers

    private static func drawText(
        _ string: String,
        at point: CGPoint,
        size: CGFloat,
        color: RGBAColor,
        in context: CGContext
    ) {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: cgColor(color),
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes)
        )
        context.saveGState()
        context.textMatrix = .identity
        // The page coordinate system is flipped; flip text back so it reads upright.
        context.translateBy(x: point.x, y: point.y + size)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a)
    }
}
