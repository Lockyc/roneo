import Foundation
import RoneoCore

/// The printer list every window's bar starts from, read from CUPS once and shared: a window that
/// opens within `maxAge` of the last read reuses it, a later one reads it again. Main thread only.
final class PrinterDirectory {
    static let shared = PrinterDirectory()

    /// `first` is the system default when it is in `names`, else the first queue.
    typealias Printers = BarState.Printers

    /// The `HOME` the CUPS tools run with: empty, so no `~/.cups/lpoptions` applies.
    static let emptyHome = Scratch.app.makeEmptyHome()
    let cups = Cups(runner: ProcessRunner(), emptyHome: PrinterDirectory.emptyHome)
    private static let maxAge: TimeInterval = 30
    private let queue = DispatchQueue(label: "roneo.printers", qos: .userInitiated)
    private var loaded: (printers: Printers, at: Date)?
    /// Callers waiting on the read in progress; empty when none runs.
    private var waiting: [(Result<Printers, Error>) -> Void] = []

    /// Calls `completion` on main with the list: the shared one when fresh, else after reading it
    /// again. A failed read isn't kept, so the next window tries again.
    func load(_ completion: @escaping (Result<Printers, Error>) -> Void) {
        if let loaded, Date().timeIntervalSince(loaded.at) < Self.maxAge {
            completion(.success(loaded.printers))
            return
        }
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        let cups = self.cups
        queue.async { [weak self] in
            let result = Result { () throws -> Printers in
                let list = try cups.printers()
                let first = list.defaultName.flatMap { list.names.contains($0) ? $0 : nil } ?? list.names.first
                let descriptions = Dictionary(uniqueKeysWithValues: list.names.map { ($0, cups.description(of: $0)) })
                return Printers(names: list.names, descriptions: descriptions, first: first,
                                caps: first.flatMap { try? cups.capabilities(for: $0) })
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let printers) = result { self.loaded = (printers, Date()) }
                let callers = self.waiting
                self.waiting = []
                callers.forEach { $0(result) }
            }
        }
    }
}
