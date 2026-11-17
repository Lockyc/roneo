import XCTest
@testable import RoneoCore

private let brotherFixture = """
Collate/Collate: True *False
ColorModel/Color Mode: Gray *RGB
cupsPrintQuality/Quality: *Normal
Duplex/2-Sided Printing: None *DuplexNoTumble DuplexTumble
PageSize/Media Size: 195x270mm 210x270mm 215x345mm 3x5 *A4 A5 A6 B5 B6 Env10 EnvC5 EnvDL EnvMonarch Executive FanFoldGermanLegal ISOB5 Legal Letter Oficio Custom.WIDTHxHEIGHT
MediaType/MediaType: stationery stationery-lightweight stationery-heavyweight envelope envelope-heavyweight envelope-lightweight labels photographic-glossy stationery-bond com.brother-recycled *any
InputSlot/Media Source: auto manual main
"""

private struct FakeRunner: CommandRunner {
    let outputs: [String: String]

    func run(_ executable: String, _ args: [String], environment: [String: String]?) throws -> CommandResult {
        let key = ([executable] + args).joined(separator: " ")
        guard let out = outputs[key] else { return CommandResult(status: 1, stdout: "", stderr: "unexpected: \(key)") }
        return CommandResult(status: 0, stdout: out, stderr: "")
    }
}

final class CupsTests: XCTestCase {
    func testParsesBrotherFixture() {
        let caps = PrinterOptionsParser.parse(brotherFixture)
        XCTAssertEqual(caps.options.count, 7)
        let duplex = caps.option("Duplex")
        XCTAssertEqual(duplex?.choices, ["None", "DuplexNoTumble", "DuplexTumble"])
        XCTAssertEqual(duplex?.defaultChoice, "DuplexNoTumble")
        XCTAssertEqual(duplex?.label, "2-Sided Printing")
        let size = caps.option("PageSize")
        XCTAssertEqual(size?.defaultChoice, "A4")
        XCTAssertFalse(size?.choices.contains("Custom.WIDTHxHEIGHT") ?? true)
        XCTAssertEqual(caps.option("InputSlot")?.defaultChoice, "auto")
        XCTAssertTrue(caps.supportsDuplex)
        XCTAssertEqual(caps.defaultSides, .double)
    }

    func testParsesPrinterWithoutDuplex() {
        let text = brotherFixture.split(separator: "\n").filter { !$0.hasPrefix("Duplex") }.joined(separator: "\n")
        let caps = PrinterOptionsParser.parse(text)
        XCTAssertNil(caps.option("Duplex"))
        XCTAssertFalse(caps.supportsDuplex)
        XCTAssertEqual(caps.defaultSides, .single)
    }

    func testDefaultPrinterParsing() throws {
        let some = Cups(runner: FakeRunner(outputs: [
            "lpstat -e": "A\nB\n",
            "lpstat -d": "system default destination: B\n",
        ]))
        XCTAssertEqual(try some.printers().defaultName, "B")
        let none = Cups(runner: FakeRunner(outputs: [
            "lpstat -e": "A\n",
            "lpstat -d": "no system default destination\n",
        ]))
        XCTAssertNil(try none.printers().defaultName)
    }

    func testPrinterListParsing() throws {
        let cups = Cups(runner: FakeRunner(outputs: [
            "lpstat -e": "A\n\n  B_two \n",
            "lpstat -d": "no system default destination\n",
        ]))
        XCTAssertEqual(try cups.printers().names, ["A", "B_two"])
    }

    /// macOS `lpstat -e` prints nothing and exits 0 with no destinations; upstream CUPS exits 1
    /// with "No destinations added.". Both are an empty list, not an unreachable print system.
    func testNoDestinationsIsAnEmptyList() throws {
        let none = CommandResult(status: 0, stdout: "no system default destination\n", stderr: "")
        for list in [CommandResult(status: 0, stdout: "", stderr: ""),
                     CommandResult(status: 1, stdout: "", stderr: "lpstat: No destinations added.\n")] {
            let cups = Cups(runner: RecordingRunner(results: ["lpstat -e": list, "lpstat -d": none]))
            let printers = try cups.printers()
            XCTAssertEqual(printers.names, [])
            XCTAssertNil(printers.defaultName)
        }
        let down = CommandResult(status: 1, stdout: "", stderr: "lpstat: Scheduler is not running.\n")
        XCTAssertThrowsError(try Cups(runner: RecordingRunner(results: ["lpstat -e": down, "lpstat -d": none])).printers())
    }

    func testCapabilitiesUsesPrinterFlag() throws {
        let cups = Cups(runner: FakeRunner(outputs: ["lpoptions -p P -l": brotherFixture]))
        XCTAssertEqual(try cups.capabilities(for: "P").options.count, 7)
    }

    func testPrinterDescription() {
        let cups = Cups(runner: FakeRunner(outputs: [
            "lpstat -l -p Brother_X": "printer Brother_X is idle.\n\tContent types: any\n\tDescription: Brother X series\n\tAlerts: none\n",
            "lpstat -l -p Blank": "printer Blank is idle.\n\tDescription: \n\tLocation: \n",
        ]))
        XCTAssertEqual(cups.description(of: "Brother_X"), "Brother X series")
        XCTAssertEqual(cups.description(of: "Blank"), "Blank")
        XCTAssertEqual(cups.description(of: "Missing"), "Missing")
    }
}
