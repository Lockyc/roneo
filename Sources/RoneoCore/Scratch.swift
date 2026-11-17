import Foundation

/// The app's scratch directory: the files handed to `lp`, and `emptyHome`, the `HOME` the CUPS
/// tools run with.
public struct Scratch: Sendable {
    public let directory: URL

    /// `temporaryDirectory/roneo`.
    public static let app = Scratch(directory: FileManager.default.temporaryDirectory.appendingPathComponent("roneo"))

    public init(directory: URL) {
        self.directory = directory
    }

    public var emptyHome: URL { directory.appendingPathComponent("home") }

    /// Creates `emptyHome` when missing and returns it.
    public func makeEmptyHome() -> URL {
        try? FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        return emptyHome
    }

    /// Removes everything but `emptyHome` last modified more than `age` seconds ago: files a crash
    /// or a force quit left behind before their job's cleanup ran. A file younger than `age` may
    /// belong to a job another running instance is sending.
    public func clear(olderThan age: TimeInterval = 0, now: Date = Date()) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name != emptyHome.lastPathComponent {
            let url = directory.appendingPathComponent(name)
            let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? .distantPast
            if now.timeIntervalSince(modified) >= age { try? fm.removeItem(at: url) }
        }
    }
}
