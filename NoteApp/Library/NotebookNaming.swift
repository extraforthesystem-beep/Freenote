import Foundation

/// Default titles for notebooks the user creates without naming them.
///
/// A new notebook is called after the day it was made ("Notes 14 Nov"), so a
/// fresh library does not read as a column of notebooks all called "Untitled
/// Notebook". A second notebook made the same day gets " 2", then " 3", and so
/// on, based on the titles already in the library.
enum NotebookNaming {
    /// The title for a notebook created on `date`, avoiding `existing` titles.
    ///
    /// `locale` decides the day and month order, so the name reads the way the
    /// user writes dates. A title already in the library keeps its name; only
    /// the new notebook gets a suffix.
    nonisolated static func defaultNotebookTitle(
        for date: Date,
        existing: Set<String>,
        locale: Locale = .current
    ) -> String {
        let day = date.formatted(
            .dateTime.day().month(.abbreviated).locale(locale)
        )
        let base = "Notes \(day)"
        guard existing.contains(base) else { return base }
        var suffix = 2
        while existing.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }
}
