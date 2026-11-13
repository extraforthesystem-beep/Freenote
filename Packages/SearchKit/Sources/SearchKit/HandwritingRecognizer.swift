import Foundation
import InkKit
import NoteCore
import PencilKit

/// Turns a page's ink into searchable text.
public protocol HandwritingRecognizing: Sendable {
    /// Changes whenever the system recogniser would produce different text for the same ink.
    var recognitionVersion: Int { get }

    /// The text in `strokes` for the search index, or nil when there is nothing
    /// recognisable. May concatenate several candidate readings.
    func text(for strokes: [StrokeRecord]) async -> String?

    /// The single best reading of `strokes`, or nil when there is nothing
    /// recognisable. Prose readers such as the AI panel use this instead of the
    /// index text, which can contain alternatives ("101\nlol").
    func recognizedText(for strokes: [StrokeRecord]) async -> String?
}

extension HandwritingRecognizing {
    /// A recogniser with no separate best reading falls back to its index text.
    public func recognizedText(for strokes: [StrokeRecord]) async -> String? {
        await text(for: strokes)
    }
}

/// Apple's on-device handwriting recogniser. PencilKit stays inside this file.
public struct PencilKitRecognizer: HandwritingRecognizing {
    public let preferredLanguages: [Locale.Language]?

    public init(preferredLanguages: [Locale.Language]? = nil) {
        self.preferredLanguages = preferredLanguages
    }

    public var recognitionVersion: Int {
        PKStrokeRecognizer.recognitionVersion
    }

    public func text(for strokes: [StrokeRecord]) async -> String? {
        guard !strokes.isEmpty else { return nil }
        let drawing = StrokeCodec.drawing(from: strokes)
        // StrokeCodec drops records PencilKit cannot rebuild, so this can still be empty.
        guard !drawing.strokes.isEmpty else { return nil }

        let recognizer = PKStrokeRecognizer(preferredLanguages: preferredLanguages)
        await recognizer.updateDrawing(drawing)
        guard let content = await recognizer.indexableContent else { return nil }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func recognizedText(for strokes: [StrokeRecord]) async -> String? {
        guard !strokes.isEmpty else { return nil }
        return await text(in: StrokeCodec.drawing(from: strokes))
    }
}

extension PencilKitRecognizer {
    /// Where on the page the ink reads as any of `terms`, in page coordinates.
    /// Uses Apple's on-device ink search, so a match is found in the strokes
    /// themselves rather than in the stored text.
    public func inkBounds(matching terms: [String], in strokes: [StrokeRecord]) async -> [CGRect] {
        guard !terms.isEmpty, !strokes.isEmpty else { return [] }
        let drawing = StrokeCodec.drawing(from: strokes)
        guard !drawing.strokes.isEmpty else { return [] }

        let recognizer = PKStrokeRecognizer(preferredLanguages: preferredLanguages)
        await recognizer.updateDrawing(drawing)
        return await recognizer.bounds(matching: terms)
    }

    /// The text written in `drawing`, for queries written with Apple Pencil.
    public func text(in drawing: PKDrawing) async -> String? {
        guard !drawing.strokes.isEmpty else { return nil }
        let recognizer = PKStrokeRecognizer(preferredLanguages: preferredLanguages)
        await recognizer.updateDrawing(drawing)
        let text = await recognizer.recognizedText()?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return text?.isEmpty == false ? text : nil
    }
}

extension PKStrokeRecognizer {
    /// Runs on the recogniser's actor so the non-Sendable results never leave it.
    fileprivate func bounds(matching terms: [String]) async -> [CGRect] {
        var bounds: [CGRect] = []
        for term in terms {
            for result in await search(term) where !result.bounds.isNull && !result.bounds.isEmpty {
                bounds.append(result.bounds)
            }
        }
        return bounds
    }
}
