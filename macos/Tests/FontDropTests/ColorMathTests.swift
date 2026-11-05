import XCTest
@testable import FontDrop

/// The color math behind the Colors popover: hex parse and format, HSB, contrast, mixing.
final class ColorMathTests: XCTestCase {
    func testHexRoundTrip() throws {
        for hex in ["#FFFFFF", "#0A0A0A", "#E5341D", "#2B5C93", "#101312", "#000000"] {
            let c = try XCTUnwrap(HexColor(hex: hex))
            XCTAssertEqual(c.hex, hex)
        }
    }

    func testHexAcceptsThreeOrSixDigitsWithOrWithoutHash() throws {
        XCTAssertEqual(HexColor(hex: "fff")?.hex, "#FFFFFF")
        XCTAssertEqual(HexColor(hex: "#abc")?.hex, "#AABBCC")
        XCTAssertEqual(HexColor(hex: "e5341d")?.hex, "#E5341D")
        XCTAssertEqual(HexColor(hex: " #E5341D ")?.hex, "#E5341D")
    }

    func testHexRejectsOtherLengthsAndNonHexDigits() {
        for bad in ["", "#", "ff", "ffff", "fffff", "fffffff", "ggg", "#12345z", "##FFF"] {
            XCTAssertNil(HexColor(hex: bad), "\(bad) should not parse")
        }
    }

    func testHSBRoundTripWithinOneStep() throws {
        for hex in ["#E5341D", "#2B5C93", "#7C7A1E", "#B57E93", "#FFFFFF", "#000000", "#808080", "#101312"] {
            let c = try XCTUnwrap(HexColor(hex: hex))
            let (h, s, b) = c.hsb
            let back = HexColor(h: h, s: s, b: b)
            XCTAssertEqual(back.r, c.r, accuracy: 1.0 / 255, hex)
            XCTAssertEqual(back.g, c.g, accuracy: 1.0 / 255, hex)
            XCTAssertEqual(back.b, c.b, accuracy: 1.0 / 255, hex)
        }
    }

    func testHSBKnownValues() throws {
        let red = try XCTUnwrap(HexColor(hex: "#FF0000")).hsb
        XCTAssertEqual(red.h, 0, accuracy: 0.001); XCTAssertEqual(red.s, 1, accuracy: 0.001); XCTAssertEqual(red.b, 1, accuracy: 0.001)
        let green = try XCTUnwrap(HexColor(hex: "#00FF00")).hsb
        XCTAssertEqual(green.h, 1.0 / 3, accuracy: 0.001)
        let blue = try XCTUnwrap(HexColor(hex: "#0000FF")).hsb
        XCTAssertEqual(blue.h, 2.0 / 3, accuracy: 0.001)
        let gray = try XCTUnwrap(HexColor(hex: "#808080")).hsb
        XCTAssertEqual(gray.s, 0, accuracy: 0.001)
        XCTAssertEqual(HexColor(h: 0.5, s: 1, b: 1).hex, "#00FFFF")
        XCTAssertEqual(HexColor(h: 1.0, s: 1, b: 1).hex, "#FF0000", "hue 1 wraps to red")
    }

    func testContrastBlackOnWhite() throws {
        let ink = try XCTUnwrap(HexColor(hex: "#0A0A0A")), paper = try XCTUnwrap(HexColor(hex: "#FFFFFF"))
        XCTAssertEqual(ink.contrast(with: paper), 19.8, accuracy: 0.05)
        XCTAssertEqual(paper.contrast(with: ink), ink.contrast(with: paper), "order does not matter")
        XCTAssertEqual(paper.contrast(with: paper), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(HexColor(hex: "#000")).contrast(with: paper), 21, accuracy: 0.0001)
    }

    func testPaperPaletteReadsNineteenPointEight() {
        XCTAssertEqual(ContrastBand.display(TemplatePalette.paper.contrastRatio), "19.8")
        XCTAssertEqual(TemplatePalette.paper.contrastBand, .fine)
    }

    func testContrastBands() {
        XCTAssertEqual(ContrastBand(ratio: 21), .fine)
        XCTAssertEqual(ContrastBand(ratio: 4.5), .fine)
        XCTAssertEqual(ContrastBand(ratio: 4.49), .largeOnly)
        XCTAssertEqual(ContrastBand(ratio: 3), .largeOnly)
        XCTAssertEqual(ContrastBand(ratio: 2.99), .tooLow)
        XCTAssertEqual(ContrastBand(ratio: 1), .tooLow)
        XCTAssertEqual(Lexicon.Colors.band(.fine), "Fine for body text")
        XCTAssertEqual(Lexicon.Colors.band(.largeOnly), "Large text only")
        XCTAssertEqual(Lexicon.Colors.band(.tooLow), "Too low to read")
    }

    func testDisplayNeverRoundsAcrossABandEdge() {
        XCTAssertEqual(ContrastBand.display(4.49), "4.4")
        XCTAssertEqual(ContrastBand.display(2.99), "2.9")
        XCTAssertEqual(ContrastBand.display(4.5), "4.5")
        XCTAssertEqual(ContrastBand.display(3.0), "3.0")
    }

    func testPresetsAreFineForBodyTextExceptSignalAccentRules() {
        // Text on background must be readable in every preset.
        for preset in TemplatePalette.presets {
            XCTAssertEqual(preset.palette.contrastBand, .fine, preset.name)
        }
    }

    func testMixingAndDerivedColors() throws {
        let white = try XCTUnwrap(HexColor(hex: "#FFFFFF")), black = try XCTUnwrap(HexColor(hex: "#000000"))
        XCTAssertEqual(white.mixed(with: black, amount: 0).hex, "#FFFFFF")
        XCTAssertEqual(white.mixed(with: black, amount: 1).hex, "#000000")
        XCTAssertEqual(white.mixed(with: black, amount: 0.5).hex, "#808080")
        // Paper's secondary text on the Paper palette is close to the board's #6B6B6B.
        let secondary = TemplatePalette.paper.secondary
        XCTAssertEqual(secondary.r * 255, 0x6B, accuracy: 4)
        // Text on the accent is whichever role reads better.
        XCTAssertEqual(TemplatePalette.bone.onColor(TemplatePalette.bone.accent), TemplatePalette.bone.background)
    }

    func testPaletteJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(["1": TemplatePalette.night])
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("#101312"), "saved as readable hex")
        let back = try JSONDecoder().decode([String: TemplatePalette].self, from: data)
        XCTAssertEqual(back["1"], .night)
    }
}
