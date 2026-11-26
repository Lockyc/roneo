import Foundation

/// When a document open from disk re-reads its file: each change notification restarts a settle
/// wait, a file whose size moved during the wait waits again, and a missing file keeps the last
/// content. A notification that leaves the file's `FileStamp` as read is ignored, since reading the
/// file sets its access date and that is reported as a change too. `View` is the window's page and
/// zoom from before a burst of changes, kept until a reload of the settled file is shown, so a
/// reload of a half-written file can't move the view for good. The caller owns the timer.
public struct ReloadGate<View> {
    /// The version of the file the document's content was read from.
    public private(set) var loadedStamp: FileStamp?
    /// True while a settle wait runs.
    public private(set) var isWaiting = false
    /// The view from before the current burst of changes.
    public private(set) var preReloadView: View?
    /// The file's size when the wait last started.
    private var sizeAtChange: Int?

    public enum Settle: Equatable, Sendable {
        /// The file is missing or unreadable: keep showing what was last read.
        case keepLastContent
        /// The file is still changing: start the wait again.
        case wait
        /// Re-read the file.
        case reload
    }

    public init() {}

    /// The file was read; `stamp` was taken before reading, so a write that lands mid-read leaves
    /// a stale stamp and reloads again.
    public mutating func didRead(_ stamp: FileStamp?) {
        loadedStamp = stamp
    }

    /// The file may have changed (`FileWatcher` or the file presenter). `stamp` and `size` are the file's now; `view` is the
    /// window's view, or nil when there is none to keep (a locked PDF). Returns true when the
    /// caller should (re)start the settle wait.
    public mutating func changed(stamp: FileStamp?, size: Int?, view: View?) -> Bool {
        guard isWaiting || stamp != loadedStamp else { return false }
        if preReloadView == nil { preReloadView = view }
        sizeAtChange = size
        isWaiting = true
        return true
    }

    /// The settle wait ran out with the file at `size` (nil when missing).
    public mutating func settled(size: Int?) -> Settle {
        isWaiting = false
        guard let size else { return .keepLastContent }
        guard size == sizeAtChange else {
            sizeAtChange = size
            isWaiting = true
            return .wait
        }
        return .reload
    }

    /// The view to restore now that a reload is shown; the gate forgets it.
    public mutating func takePreReloadView() -> View? {
        defer { preReloadView = nil }
        return preReloadView
    }
}
