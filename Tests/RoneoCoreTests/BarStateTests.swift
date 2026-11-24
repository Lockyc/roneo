import XCTest
@testable import RoneoCore

final class BarStateTests: XCTestCase {
    private struct Unreachable: Error {}

    private let printers = ["A", "B", "C"]
    private let descriptions = ["A": "Alpha", "B": "Bravo", "C": "Charlie"]
    private let document = BarState.Document(
        pdf: .init(pageCount: 3, isLocked: false, allowsPrinting: true), fileExists: true)

    private func loaded(caps: PrinterCapabilities?) -> Result<BarState.Printers, Error> {
        .success(.init(names: printers, descriptions: descriptions, first: "A", caps: caps))
    }

    /// A failed options read for a newly chosen printer leaves the bar, and Print, on the printer
    /// it was showing, and says so in the status.
    func testUnreadableOptionsKeepTheBarOnItsPrinter() {
        var state = BarState()
        state.printersLoaded(loaded(caps: brotherCapabilities))
        XCTAssertEqual(state.choose("B"), .loadOptions("B"))
        XCTAssertEqual(state.blockReason(document: document), BarState.loadingReason)
        let status = state.optionsLoaded("B", nil)
        XCTAssertEqual(state.selectedPrinter, "A")
        XCTAssertEqual(state.settings?.printer, "A")
        XCTAssertNil(state.blockReason(document: document))
        XCTAssertEqual(status, "Can't read Bravo's options")
    }

    /// The default printer's unreadable options block Print with that reason, and choosing a
    /// readable printer recovers.
    func testUnreadableDefaultBlocksUntilAnotherPrinterLoads() {
        var state = BarState()
        state.printersLoaded(loaded(caps: nil))
        XCTAssertEqual(state.selectedPrinter, "A")
        XCTAssertEqual(state.blockReason(document: document), "Can't read Alpha's options")
        XCTAssertEqual(state.choose("B"), .loadOptions("B"))
        XCTAssertNil(state.optionsLoaded("B", simplexCapabilities))
        XCTAssertEqual(state.settings?.printer, "B")
        XCTAssertNil(state.blockReason(document: document))
    }

    /// A locked PDF reads as locked, not as still loading, once the bar has its printer.
    func testLockedPDFGivesItsOwnReason() {
        var state = BarState()
        state.printersLoaded(loaded(caps: brotherCapabilities))
        var locked = document
        locked.pdf?.isLocked = true
        XCTAssertEqual(state.blockReason(document: locked), BarState.locked)
    }

    func testReasonsBeforeAnythingLoads() {
        var state = BarState()
        XCTAssertEqual(state.blockReason(document: nil), BarState.noPDF)
        XCTAssertEqual(state.blockReason(document: document), BarState.loadingReason)
        XCTAssertEqual(state.controlsBlocked, BarState.loadingReason)
        state.printersLoaded(.failure(Unreachable()))
        XCTAssertEqual(state.blockReason(document: document), BarState.unreachable)
        XCTAssertEqual(state.controlsBlocked, BarState.unreachable)
    }

    func testSendingBlocksASecondPrint() {
        var state = BarState()
        state.printersLoaded(loaded(caps: brotherCapabilities))
        state.sending = true
        XCTAssertEqual(state.blockReason(document: document), BarState.sendingReason)
        state.sending = false
        XCTAssertNil(state.blockReason(document: document))
    }

    // MARK: Sequences

    private enum Step: CustomStringConvertible {
        case choose(String), deliver(PrinterCapabilities?)
        var description: String {
            switch self {
            case .choose(let p): return "choose(\(p))"
            case .deliver(let caps): return caps == nil ? "deliver(fail)" : "deliver(ok)"
            }
        }
    }

    /// Every sequence of up to five popup choices and options deliveries, from each way the list
    /// can load, as the bar allows them (the popup is disabled while a printer's options load). After
    /// every step, the printer the popup shows is the one Print sends to, and Print has that
    /// printer's options.
    func testThePopupAlwaysShowsThePrinterPrintUses() {
        let starts: [(String, Result<BarState.Printers, Error>)] = [
            ("loaded", loaded(caps: brotherCapabilities)),
            ("loaded, default unreadable", loaded(caps: nil)),
            ("unreachable", .failure(Unreachable())),
        ]
        let steps: [Step] = printers.map { .choose($0) } + [.deliver(simplexCapabilities), .deliver(nil)]
        var checked = 0

        func walk(_ state: BarState, pending: String?, trail: [String], depth: Int) {
            if let settings = state.settings {
                XCTAssertEqual(state.selectedPrinter, settings.printer, trail.joined(separator: " → "))
                XCTAssertNotNil(state.selectedCapabilities, trail.joined(separator: " → "))
            }
            checked += 1
            guard depth > 0 else { return }
            for step in steps {
                var next = state
                var nextPending = pending
                switch step {
                case .choose(let printer):
                    guard pending == nil, !(state.printers ?? []).isEmpty else { continue }
                    if case .loadOptions(let p) = next.choose(printer) { nextPending = p }
                case .deliver(let caps):
                    guard let p = pending else { continue }
                    next.optionsLoaded(p, caps)
                    nextPending = nil
                }
                walk(next, pending: nextPending, trail: trail + [step.description], depth: depth - 1)
            }
        }

        for (name, result) in starts {
            var state = BarState()
            state.printersLoaded(result)
            walk(state, pending: nil, trail: [name], depth: 5)
        }
        XCTAssertGreaterThan(checked, 100)
    }
}
