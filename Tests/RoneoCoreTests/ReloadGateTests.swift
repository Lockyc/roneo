import XCTest
@testable import RoneoCore

final class ReloadGateTests: XCTestCase {
    private let s1 = FileStamp(fileNumber: 7, size: 100, modified: Date(timeIntervalSince1970: 1_000))
    private let s2 = FileStamp(fileNumber: 7, size: 120, modified: Date(timeIntervalSince1970: 2_000))

    private func readGate() -> ReloadGate<String> {
        var gate = ReloadGate<String>()
        gate.didRead(s1)
        return gate
    }

    /// Reading the file sets its access date, which the presenter reports as a change; with the
    /// stamp as read, that report must not start a wait, or every reload triggers the next.
    func testAChangeThatLeavesTheStampAsReadIsIgnored() {
        var gate = readGate()
        XCTAssertFalse(gate.changed(stamp: s1, size: 100, view: "page 4"))
        XCTAssertFalse(gate.isWaiting)
        XCTAssertNil(gate.preReloadView)
    }

    /// The reload loop: after a reload reads the new version, its own access-date report is
    /// ignored, so the cycle stops.
    func testAReloadDoesNotTriggerAnother() {
        var gate = readGate()
        XCTAssertTrue(gate.changed(stamp: s2, size: 120, view: "page 4"))
        XCTAssertEqual(gate.settled(size: 120), .reload)
        gate.didRead(s2)
        XCTAssertEqual(gate.takePreReloadView(), "page 4")
        XCTAssertFalse(gate.changed(stamp: s2, size: 120, view: "page 4"))
    }

    /// Mid-burst, a report whose stamp matches what was read still restarts the wait: the file is
    /// being written, and a stamp can match a half-written state.
    func testAnyChangeDuringAWaitRestartsIt() {
        var gate = readGate()
        XCTAssertTrue(gate.changed(stamp: s2, size: 120, view: "page 4"))
        XCTAssertTrue(gate.changed(stamp: s1, size: 100, view: "page 9"))
        XCTAssertTrue(gate.isWaiting)
    }

    /// A file still growing when the wait runs out waits again instead of loading half of it.
    func testASizeChangeDuringTheWaitWaitsAgain() {
        var gate = readGate()
        XCTAssertTrue(gate.changed(stamp: s2, size: 50, view: "page 4"))
        XCTAssertEqual(gate.settled(size: 80), .wait)
        XCTAssertTrue(gate.isWaiting)
        XCTAssertEqual(gate.settled(size: 80), .reload)
        XCTAssertFalse(gate.isWaiting)
    }

    func testAMissingFileKeepsTheLastContent() {
        var gate = readGate()
        XCTAssertTrue(gate.changed(stamp: nil, size: nil, view: "page 4"))
        XCTAssertEqual(gate.settled(size: nil), .keepLastContent)
        XCTAssertFalse(gate.isWaiting)
    }

    /// The view from before the burst is the one restored, not one a half-written reload moved to.
    func testTheViewFromBeforeTheBurstIsKept() {
        var gate = readGate()
        XCTAssertTrue(gate.changed(stamp: s2, size: 120, view: "page 4"))
        XCTAssertTrue(gate.changed(stamp: s2, size: 130, view: "page 1"))
        XCTAssertEqual(gate.settled(size: 130), .reload)
        XCTAssertEqual(gate.takePreReloadView(), "page 4")
        XCTAssertNil(gate.takePreReloadView())
    }

    /// A locked PDF has no view to keep; the first view seen after it unlocks is the one kept.
    func testALockedDocumentKeepsNoView() {
        var gate = readGate()
        XCTAssertTrue(gate.changed(stamp: s2, size: 120, view: nil))
        XCTAssertNil(gate.preReloadView)
        XCTAssertTrue(gate.changed(stamp: s2, size: 120, view: "page 2"))
        XCTAssertEqual(gate.preReloadView, "page 2")
    }
}
