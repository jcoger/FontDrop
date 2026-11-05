import SwiftUI
import XCTest
@testable import FontDrop

/// Round R1: the sidebar rows, the command-1 to command-3 keys, and the Text and Auto renames.
final class NamesAndStructureTests: XCTestCase {
    func testSidebarIsDisplayTextSet() {
        XCTAssertEqual(Screen.sidebar, [.display, .reading, .set])
        XCTAssertEqual(Screen.sidebar.map(\.title), ["Display", "Text", "Set"])
        XCTAssertFalse(Screen.sidebar.contains(.ui))
        XCTAssertFalse(Screen.sidebar.contains(.mono))
        XCTAssertFalse(Screen.sidebar.contains(.colors))
    }

    func testCommandOneToThreeOpenDisplayTextSet() {
        XCTAssertEqual(Screen.sidebar.compactMap(\.shortcutKey), ["1", "2", "3"])
        XCTAssertEqual(Screen.display.shortcutKey, "1")
        XCTAssertEqual(Screen.reading.shortcutKey, "2")
        XCTAssertEqual(Screen.set.shortcutKey, "3")
        XCTAssertNil(Screen.ui.shortcutKey)
    }

    func testTextIsTheJobNameOnScreen() {
        XCTAssertEqual(Lexicon.jobName("reading"), "Text")
        XCTAssertEqual(Lexicon.jobName("display"), "Display")
        XCTAssertEqual(Lexicon.useFor("reading"), "Use for Text")
        XCTAssertEqual(Lexicon.current("reading"), "Current Text face")
        XCTAssertEqual(Lexicon.picked("reading"), "Text face picked")
        XCTAssertEqual(Lexicon.Reading.title("Agrandir"), "Text for Agrandir")
        XCTAssertEqual(Lexicon.Reading.candidateTitle, "Text candidate")
        XCTAssertEqual(Lexicon.Reading.findingNone, "No Text partners found.")
        XCTAssertEqual(Lexicon.setTheType, "Next: Set")
    }

    func testSetRowSecondLine() {
        var scale = TypeScale()
        XCTAssertEqual(Lexicon.Scale.sidebarLine(scale), "Auto")
        scale.locked = true
        XCTAssertEqual(Lexicon.Scale.sidebarLine(scale), "15 pt \u{00B7} 1.333")
        scale.ratio = 1.25; scale.body = 16
        XCTAssertEqual(Lexicon.Scale.sidebarLine(scale), "16 pt \u{00B7} 1.25")
    }

    func testNoEmDashesInNewStrings() {
        let strings = [Lexicon.goMenu, Lexicon.opticalSize, Lexicon.auto, Lexicon.Scale.autoNote, Lexicon.Scale.autoHelp,
                       Lexicon.Scale.sectionFace, Lexicon.setTheType, Lexicon.findText]
        for s in strings { XCTAssertFalse(s.contains("\u{2014}"), s) }
    }
}
