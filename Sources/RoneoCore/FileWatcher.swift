import Foundation

/// Calls `onChange` on the main queue the moment the file at `url` may have changed: written,
/// truncated, its attributes touched, deleted, or replaced by a rename or a recreate in its folder.
/// It watches the file and its folder with kqueue, so a report arrives within milliseconds, where
/// a file presenter waits on the file-coordination daemon's batching (over a second). It follows
/// the path, not the file: after a replace it watches whatever file is at `url` now. Reports are
/// "may have changed"; `ReloadGate` decides whether the content did. Create and cancel it on the
/// main queue.
public final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    /// The file number `fileSource` watches; a folder change re-arms only when the file at `url`
    /// is a different one.
    private var watchedFileNumber: UInt64?

    public init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        folderSource = Self.source(path: url.deletingLastPathComponent().path, events: [.write]) { [weak self] _ in
            guard let self else { return }
            if self.currentFileNumber != self.watchedFileNumber { self.armFile() }
            self.onChange()
        }
        armFile()
    }

    deinit { cancel() }

    public func cancel() {
        folderSource?.cancel()
        folderSource = nil
        fileSource?.cancel()
        fileSource = nil
        watchedFileNumber = nil
    }

    private var currentFileNumber: UInt64? {
        var info = stat()
        return stat(url.path, &info) == 0 ? UInt64(info.st_ino) : nil
    }

    /// Watches the file now at `url`, or nothing when there is none; the folder source re-arms it
    /// when one appears.
    private func armFile() {
        fileSource?.cancel()
        fileSource = nil
        watchedFileNumber = currentFileNumber
        guard watchedFileNumber != nil else { return }
        fileSource = Self.source(path: url.path, events: [.write, .extend, .attrib, .delete, .rename, .revoke, .link]) { [weak self] events in
            guard let self, self.fileSource != nil else { return }
            if !events.isDisjoint(with: [.delete, .rename, .revoke]) { self.armFile() }
            self.onChange()
        }
    }

    private static func source(
        path: String, events: DispatchSource.FileSystemEvent,
        handler: @escaping (DispatchSource.FileSystemEvent) -> Void
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [unowned source] in handler(source.data) }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }
}
