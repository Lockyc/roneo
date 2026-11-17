import XCTest
@testable import RoneoCore

final class ScratchTests: XCTestCase {
    func testClearRemovesEverythingButHome() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let scratch = Scratch(directory: dir)
        try fm.createDirectory(at: scratch.emptyHome, withIntermediateDirectories: true)
        for name in ["a.pdf", "b.pdf"] {
            try Data("%PDF".utf8).write(to: dir.appendingPathComponent(name))
        }
        try fm.createDirectory(at: dir.appendingPathComponent("stray"), withIntermediateDirectories: true)

        scratch.clear()

        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), ["home"])
    }

    func testClearKeepsFilesYoungerThanTheAge() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("old.pdf"), fresh = dir.appendingPathComponent("fresh.pdf")
        try Data().write(to: old)
        try Data().write(to: fresh)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: old.path)

        Scratch(directory: dir).clear(olderThan: 60)

        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), ["fresh.pdf"])
    }

    func testClearWithoutDirectoryIsHarmless() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        Scratch(directory: dir).clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testEmptyHomeIsCreatedEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let home = Scratch(directory: dir).makeEmptyHome()
        XCTAssertEqual(home, dir.appendingPathComponent("home"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.path), [])
    }
}
