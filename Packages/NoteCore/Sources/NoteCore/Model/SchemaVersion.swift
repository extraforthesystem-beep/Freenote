import Foundation

/// The on-disk schema version written by this build of NoteCore.
///
/// Every file in the library format carries a `schemaVersion`. A file written by a
/// newer build is refused rather than partly decoded.
public enum SchemaVersion {
    /// The first on-disk format. A file with no `schemaVersion` key predates
    /// versioning and is read as this version — never as `current`, or a later
    /// bump would label old files as files from the new format.
    public static let initial = 1

    public static let current = 1
}
