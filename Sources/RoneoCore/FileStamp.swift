import Foundation

/// Which version of a file is on disk: its identity, size and modification date. Two stamps differ
/// only when the file's content may have changed. Reading the file, or touching its access date or
/// extended attributes, leaves the stamp alone; the file presenter is told of those as changes.
public struct FileStamp: Equatable, Sendable {
    public let fileNumber: Int
    public let size: Int
    public let modified: Date

    init(fileNumber: Int, size: Int, modified: Date) {
        self.fileNumber = fileNumber
        self.size = size
        self.modified = modified
    }

    /// nil when the file is missing or unreadable.
    public init?(of url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileNumber = attributes[.systemFileNumber] as? Int,
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        self.fileNumber = fileNumber
        self.size = size
        self.modified = modified
    }
}
