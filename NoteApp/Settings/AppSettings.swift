import Foundation
import NoteCore

/// The app's preferences, stored in `UserDefaults`.
///
/// Views read the same keys through `@AppStorage`; the accessors here are for
/// code that runs outside a view (creating a notebook, indexing). Every value
/// falls back to its default when the key has never been written, so no
/// registration pass is needed at launch.
enum AppSettings {
    /// The stored keys. The prefix keeps these apart from the editor's own keys.
    enum Key {
        static let showPageNumber = "noteapp.settings.showPageNumber"
        static let openDocumentsAsNewTabs = "noteapp.settings.openDocumentsAsNewTabs"
        static let newNotebookPaperSize = "noteapp.settings.newNotebookPaperSize"
        static let newNotebookOrientation = "noteapp.settings.newNotebookOrientation"
        static let newNotebookTemplateID = "noteapp.settings.newNotebookTemplateID"
        static let handwritingRecognitionEnabled = "noteapp.settings.handwritingRecognitionEnabled"
        static let holdToDrawShapes = "noteapp.settings.holdToDrawShapes"
    }

    /// The catalog id of the plain blank template.
    static let defaultTemplateID = "blank"

    // MARK: - Document editing

    static var showPageNumber: Bool {
        bool(Key.showPageNumber, default: true)
    }

    static var openDocumentsAsNewTabs: Bool {
        bool(Key.openDocumentsAsNewTabs, default: true)
    }

    // MARK: - New notebooks

    static var newNotebookPaperSize: PaperSize {
        PaperSize(rawValue: string(Key.newNotebookPaperSize) ?? "") ?? .a4
    }

    static var newNotebookOrientation: PageOrientation {
        PageOrientation(rawValue: string(Key.newNotebookOrientation) ?? "") ?? .portrait
    }

    static var newNotebookTemplateID: String {
        string(Key.newNotebookTemplateID) ?? defaultTemplateID
    }

    /// The first page's template, or the blank page when the stored catalog id
    /// no longer exists (a catalog rename must not break notebook creation).
    static var newNotebookTemplate: PageTemplate {
        PageTemplateCatalog.all.first { $0.id == newNotebookTemplateID }?.template
            ?? PageTemplate.blank
    }

    /// The first page's size in points, from the paper size and orientation.
    static var newNotebookPageSize: (width: Double, height: Double) {
        newNotebookPaperSize.size(newNotebookOrientation)
    }

    // MARK: - Handwriting recognition

    static var handwritingRecognitionEnabled: Bool {
        bool(Key.handwritingRecognitionEnabled, default: true)
    }

    // MARK: - Writing

    static var holdToDrawShapes: Bool {
        bool(Key.holdToDrawShapes, default: true)
    }

    // MARK: - Reading

    private static func bool(_ key: String, default fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func string(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }
}
