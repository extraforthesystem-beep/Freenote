import Foundation

extension UUID {
    /// The form used in file and folder names.
    var diskName: String {
        uuidString.lowercased()
    }
}

/// The on-disk layout of one library. Pure path arithmetic, no state.
struct LibraryLayout: Sendable {
    let root: URL

    var libraryFile: URL { root.appendingPathComponent("library.json") }
    var folderTreeFile: URL { root.appendingPathComponent("folders.json") }
    var notebooksDirectory: URL { root.appendingPathComponent("notebooks") }
    var trashDirectory: URL { root.appendingPathComponent("trash") }
    var cacheDirectory: URL { root.appendingPathComponent("cache") }

    func notebookDirectory(_ notebookID: UUID) -> URL {
        notebooksDirectory.appendingPathComponent(notebookID.diskName)
    }

    func manifestFile(_ notebookID: UUID) -> URL {
        notebookDirectory(notebookID).appendingPathComponent("notebook.json")
    }

    func pagesDirectory(_ notebookID: UUID) -> URL {
        notebookDirectory(notebookID).appendingPathComponent("pages")
    }

    func assetsDirectory(_ notebookID: UUID) -> URL {
        notebookDirectory(notebookID).appendingPathComponent("assets")
    }

    func pageFile(_ pageID: UUID, in notebookID: UUID) -> URL {
        pagesDirectory(notebookID).appendingPathComponent(pageID.diskName + ".page")
    }

    /// The SHA-256 recorded for a page file after it was written. It sits beside
    /// the page and is not part of the page format.
    func pageChecksumFile(_ pageID: UUID, in notebookID: UUID) -> URL {
        pagesDirectory(notebookID).appendingPathComponent(pageID.diskName + ".sha256")
    }

    /// Where page files that failed to decode are kept, so nothing is thrown away.
    func quarantinedPagesDirectory(_ notebookID: UUID) -> URL {
        cacheDirectory
            .appendingPathComponent("corrupt", isDirectory: true)
            .appendingPathComponent(notebookID.diskName, isDirectory: true)
    }

    func trashedNotebookDirectory(_ notebookID: UUID) -> URL {
        trashDirectory.appendingPathComponent(notebookID.diskName)
    }
}
