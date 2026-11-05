import SwiftUI
import XCTest
@testable import FontDrop

/// Round R2a: every text token on every ground it sits on is 4.5:1 or better, unrounded, in both themes
/// (look spec rule 7). Backgrounds with alpha are composited over the layer beneath before measuring.
final class ContrastTests: XCTestCase {
    func testEveryTextPairPassesInBothThemes() {
        var failures: [String] = []
        for (name, theme) in [("dark", Theme.dark), ("light", Theme.light)] {
            for pair in theme.textPairs {
                let ratio = RGBA.contrast(pair.text, pair.background)
                if ratio < 4.5 { failures.append("\(name): \(pair.name) = \(String(format: "%.3f", ratio))") }
            }
        }
        XCTAssertTrue(failures.isEmpty, "Below 4.5:1:\n" + failures.joined(separator: "\n"))
    }

    func testThereAreManyPairsToCheck() {
        XCTAssertGreaterThan(Theme.dark.textPairs.count, 20)
        XCTAssertEqual(Theme.dark.textPairs.count, Theme.light.textPairs.count)
    }

    func testContrastMathMatchesKnownValues() {
        // Black on white is 21:1. Same color is 1:1.
        XCTAssertEqual(RGBA.contrast(RGBA(0x000000), RGBA(0xFFFFFF)), 21, accuracy: 0.001)
        XCTAssertEqual(RGBA.contrast(RGBA(0x777777), RGBA(0x777777)), 1, accuracy: 0.001)
    }

    func testRedIsOnlyTheSignalToken() {
        XCTAssertEqual(Theme.dark.signal, RGBA(0xE5341D))
        XCTAssertEqual(Theme.light.signal, RGBA(0xE5341D))
        // Red is never text: no text token equals it.
        for theme in [Theme.dark, Theme.light] {
            XCTAssertNotEqual(theme.textPrimary, theme.signal)
            XCTAssertNotEqual(theme.textSecondary, theme.signal)
        }
    }

    func testDarkHasNoShadowsAndLightKeepsGrainOff() {
        XCTAssertTrue(Theme.dark.panelShadow.isEmpty)
        XCTAssertTrue(Theme.dark.barShadow.isEmpty)
        XCTAssertEqual(Theme.dark.grainOpacity, 0.07, accuracy: 0.0001)
        XCTAssertEqual(Theme.light.grainOpacity, 0)
    }

    func testWhySummaryHasAtMostTwoChips() {
        let none = WhySummary(verdict: "x", chips: [])
        XCTAssertTrue(none.chips.count <= 2)
    }

    func testBundledFontsAreInTheApp() {
        for name in ["Doto", "GeistMono"] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "ttf"), "\(name).ttf is not bundled")
            XCTAssertNotNil(Bundle.main.url(forResource: "OFL-\(name)", withExtension: "txt"), "\(name) licence is not bundled")
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "grain", withExtension: "png"))
    }
}
