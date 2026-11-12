import Foundation

/// The on-disk schema version written by this build of NoteCore.
///
/// Every file in the library format carries a `schemaVersion`. A file written by a
/// newer build is refused rather than partly decoded.
public enum SchemaVersion {
    public static let current = 1
}
