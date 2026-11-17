import Foundation
import PDFKit

/// With `RONEO_PERF=1` in the environment, prints `first-draw-ms <n>` to stdout — the time from
/// the kernel's process start time (`kinfo_proc.p_starttime`, so dyld and launch are included) to
/// the first PDF page drawn into a view — and terminates the app.
enum FirstDrawTimer {
    static let isEnabled = ProcessInfo.processInfo.environment["RONEO_PERF"] == "1"
    @MainActor private static var reported = false

    /// Called from every page draw; reports once, from the main thread.
    static func pageDidDraw() {
        guard isEnabled else { return }
        let now = Date()
        DispatchQueue.main.async {
            guard !reported else { return }
            reported = true
            let ms = Int((now.timeIntervalSince(processStart()) * 1000).rounded())
            print("first-draw-ms \(ms)")
            fflush(stdout)
            NSApplication.shared.terminate(nil)
        }
    }

    private static func processStart() -> Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}

/// Every page of a viewed document: reports its first draw to `FirstDrawTimer`.
final class TimedPage: PDFPage {
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        FirstDrawTimer.pageDidDraw()
    }
}
