import XCTest
@testable import RoneoCore

final class BarChoicesTests: XCTestCase {
    func testChoiceLabel() {
        let table: [(String, String)] = [
            ("stationery-heavyweight", "Stationery heavyweight"), ("any", "Any"), ("auto", "Auto"),
            ("A4", "A4"), ("195x270mm", "195x270mm"), ("com.brother-recycled", "Brother recycled"),
            ("Env10", "Env10"), ("photographic-glossy", "Photographic glossy"), ("", ""),
        ]
        for (keyword, expected) in table {
            XCTAssertEqual(ChoiceLabel.display(keyword), expected, keyword)
        }
    }

    private func caps(_ line: String) -> PrinterCapabilities { PrinterOptionsParser.parse(line) }

    func testColourChoices() {
        XCTAssertEqual(caps("ColorModel/Color Mode: Gray *RGB").colourChoices, ColourChoices(colour: "RGB", grey: "Gray"))
        XCTAssertEqual(caps("ColorModel/Color Mode: *Gray CMYK RGB").colourChoices, ColourChoices(colour: "CMYK", grey: "Gray"))
        XCTAssertEqual(caps("ColorModel/Color Mode: Grayscale *KGray").colourChoices, nil)
        XCTAssertEqual(caps("ColorModel/Color Mode: Black *CMYK").colourChoices, ColourChoices(colour: "CMYK", grey: "Black"))
        XCTAssertEqual(caps("ColorModel/Color Mode: *KGray RGB").colourChoices, ColourChoices(colour: "RGB", grey: "KGray"))
        XCTAssertTrue(ColourChoices.isGrey("Monochrome"))
        XCTAssertFalse(ColourChoices.isGrey("RGB"))
        XCTAssertEqual(caps("ColorModel/Color Mode: *CMYK RGB").colourChoices, nil)
        XCTAssertEqual(caps("PageSize/Media Size: *A4").colourChoices, nil)
    }

    func testSelectionPageCount() {
        XCTAssertEqual(PageSelection.all.pageCount(of: 7), 7)
        XCTAssertEqual(PageSelection.current.pageCount(of: 7), 1)
        XCTAssertEqual(PageSelection.range("1-3, 5").pageCount(of: 7), 4)
        XCTAssertEqual(PageSelection.range("2,2").pageCount(of: 7), 1)
        XCTAssertEqual(PageSelection.range("1-4, 3-6").pageCount(of: 7), 6)
        XCTAssertEqual(PageSelection.range("5, 1-3, 4").pageCount(of: 7), 5)
        XCTAssertEqual(PageSelection.range("8").pageCount(of: 7), nil)
    }
}
