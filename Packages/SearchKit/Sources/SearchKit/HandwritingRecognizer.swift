import Foundation
import InkKit
import NoteCore
import PencilKit

/// Turns a page's ink into searchable text.
public protocol HandwritingRecognizing: Sendable {
    /// Changes whenever the system recogniser would produce different text for the same ink.
    var recognitionVersion: Int { get }

    /// The text in `strokes`, or nil when there is nothing recognisable.
    func text(for strokes: [StrokeRecord]) async -> String?
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
}
