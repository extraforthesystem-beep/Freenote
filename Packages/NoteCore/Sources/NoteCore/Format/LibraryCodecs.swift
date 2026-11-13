import Foundation

/// Reads and writes `notebook.json`: plain, pretty-printed JSON.
public enum ManifestCodec {
    public static func encode(_ manifest: NotebookManifest) throws -> Data {
        try JSONDocument.encode(manifest, path: manifest.id.uuidString)
    }

    public static func decode(_ data: Data, path: String = "") throws -> NotebookManifest {
        try JSONDocument.decode(NotebookManifest.self, from: data, path: path)
    }
}

/// Reads and writes `folders.json`: plain, pretty-printed JSON.
public enum FolderTreeCodec {
    public static func encode(_ tree: FolderTree) throws -> Data {
        try JSONDocument.encode(tree, path: "folders.json")
    }

    public static func decode(_ data: Data, path: String = "") throws -> FolderTree {
        try JSONDocument.decode(FolderTree.self, from: data, path: path)
    }
}

/// Reads and writes `library.json`: plain, pretty-printed JSON.
public enum LibraryInfoCodec {
    public static func encode(_ info: LibraryInfo) throws -> Data {
        try JSONDocument.encode(info, path: "library.json")
    }

    public static func decode(_ data: Data, path: String = "") throws -> LibraryInfo {
        try JSONDocument.decode(LibraryInfo.self, from: data, path: path)
    }
}
