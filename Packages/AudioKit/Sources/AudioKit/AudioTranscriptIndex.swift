import Foundation
import NoteCore

/// Puts a clip's transcript on the pages it was written on, so spoken words can
/// be found by the notebook's search.
public enum AudioTranscriptIndex {
    /// The transcript text of every clip that was recording while ink was
    /// written on `page`. Clips with no transcript, and pages with no ink from a
    /// recording, contribute nothing.
    ///
    /// A clip can span page turns, so a page only takes a clip's text when it
    /// has a stroke written inside the clip's window.
    public static func text(
        for page: Page,
        clips: [AudioClip],
        transcripts: [UUID: Transcript]
    ) -> String {
        let ordered = clips.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var parts: [String] = []
        for clip in ordered {
            guard page.strokes.contains(where: { clip.contains($0.createdAt) }) else { continue }
            let transcript = transcripts[clip.id]?.text ?? ""
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }
}
