import Foundation
import NoteCore

/// The library grid's derived lists, as pure functions.
///
/// The library screen calls these once per change of the values they read, not
/// once per body pass: the grid list sorts, the tag filter matches, and the
/// folder badges walk the tree, and doing that on every keystroke costs frames
/// on a base iPad.
enum LibraryVisibility {
    /// Each notebook's lowercased tags, built in one pass, so the tag filter
    /// does not rebuild a `Set` per notebook.
    static func tagSets(
        for notebooks: [NotebookManifest],
        tags: (UUID) -> [String]
    ) -> [UUID: Set<String>] {
        var result: [UUID: Set<String>] = [:]
        result.reserveCapacity(notebooks.count)
        for notebook in notebooks {
            let labels = tags(notebook.id)
            guard !labels.isEmpty else { continue }
            result[notebook.id] = Set(labels.map { $0.lowercased() })
        }
        return result
    }

    /// `notebooks` narrowed to those carrying every required tag key, in the
    /// order they were given, so the grid's sort survives the filter.
    static func filter(
        _ notebooks: [NotebookManifest],
        requiredTags: Set<String>,
        tagSets: [UUID: Set<String>]
    ) -> [NotebookManifest] {
        guard !requiredTags.isEmpty else { return notebooks }
        return notebooks.filter {
            matches(notebookID: $0.id, requiredTags: requiredTags, tagSets: tagSets)
        }
    }

    /// The reference check behind `filter`: a notebook matches when every
    /// required tag is among its own.
    static func matches(
        notebookID: UUID,
        requiredTags: Set<String>,
        tagSets: [UUID: Set<String>]
    ) -> Bool {
        guard !requiredTags.isEmpty else { return true }
        return requiredTags.isSubset(of: tagSets[notebookID] ?? [])
    }

    /// Notebooks per folder, subfolders included: one pass over the
    /// notebook-to-folder map walking each notebook up to the root, instead of
    /// one tree walk per sidebar row. A folder with no notebooks is absent.
    static func folderCounts(
        folders: [Folder],
        notebookFolder: [UUID: UUID]
    ) -> [UUID: Int] {
        guard !folders.isEmpty, !notebookFolder.isEmpty else { return [:] }
        var parent: [UUID: UUID] = [:]
        parent.reserveCapacity(folders.count)
        for folder in folders {
            if let parentID = folder.parentID { parent[folder.id] = parentID }
        }
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(folders.count)
        for folderID in notebookFolder.values {
            // A hand-edited folders.json could contain a cycle; stop at the
            // first repeated folder instead of looping forever.
            var current: UUID? = folderID
            var seen: Set<UUID> = []
            while let id = current, seen.insert(id).inserted {
                counts[id, default: 0] += 1
                current = parent[id]
            }
        }
        return counts
    }
}
