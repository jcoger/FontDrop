import FontDropCore
import XCTest

/// The arrow keys on Display (R9c): real key events, with and without a click first. The library is a temp copy with
/// nine system families, so the grid has several rows. Selection shows as the "selected" trait on a card.
final class ArrowKeysUITests: XCTestCase {
    private var dir = ""
    private var app: XCUIApplication!
    private let names = ["Arial", "Georgia", "Verdana", "Tahoma", "Trebuchet MS", "Courier New", "Times New Roman", "Comic Sans MS", "Impact"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        let source = "/System/Library/Fonts/Supplemental"
        var files: [String] = []
        for n in names {
            let found = ["", " Bold", " Italic", " Bold Italic"].map { "\(n)\($0).ttf" }.filter { FileManager.default.fileExists(atPath: "\(source)/\($0)") }
            if found.isEmpty { throw XCTSkip("no system \(n)") }
            files += found
        }
        dir = NSTemporaryDirectory() + "fontdrop-ui-arrows-\(UUID().uuidString)"
        let fonts = dir + "/fonts"
        try FileManager.default.createDirectory(atPath: fonts, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(fonts)/\(f)") }
        let db = dir + "/fontdrop.db"
        do {
            let library = try Library.open(path: db)
            _ = try library.refreshLibraryFolders(folders: [fonts])
            _ = try library.brandCreate(name: "Acme")
        }
        app = XCUIApplication()
        app.launchArguments = ["--db", db, "--isolated", "--scan-folders", fonts, "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if !dir.isEmpty { try? FileManager.default.removeItem(atPath: dir) }
    }

    private func card(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", ", \(name),")).firstMatch
    }

    /// A Text list row reads "Arial, ..." (its name, then its note).
    private func textRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "value BEGINSWITH %@", "\(name), ")).firstMatch
    }

    private func wait(_ seconds: TimeInterval, until check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if check() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return check()
    }

    /// The card that carries the selected trait, if exactly one does.
    private func selected() -> String? {
        let hits = names.filter { card($0).exists && card($0).isSelected }
        return hits.count == 1 ? hits[0] : nil
    }

    private func press(_ key: XCUIKeyboardKey) {
        app.typeKey(key, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    private func ready() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(card("Arial").waitForExistence(timeout: 20), "the cards are drawn")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    /// No click: Down selects the first card, Right moves one, Down moves a row, Up moves back, Left moves back.
    func testArrowsMoveThroughTheGridAtLaunch() throws {
        ready()
        press(.downArrow)
        let first = try XCTUnwrap(selected(), "Down at launch selected a card")
        let y0 = card(first).frame.minY
        press(.rightArrow)
        let second = try XCTUnwrap(selected())
        XCTAssertNotEqual(first, second, "Right moved one card")
        XCTAssertEqual(card(second).frame.minY, y0, accuracy: 2, "Right stays in the row")
        press(.downArrow)
        let third = try XCTUnwrap(selected())
        XCTAssertGreaterThan(card(third).frame.minY, y0 + 20, "Down moved a row")
        press(.upArrow)
        XCTAssertEqual(selected(), second, "Up moved back a row")
        press(.leftArrow)
        XCTAssertEqual(selected(), first, "Left moved back one")
    }

    /// After a click on a card the arrows start from that card.
    func testArrowsAfterClickingACard() throws {
        ready()
        card("Georgia").click()
        XCTAssertTrue(wait(5) { self.selected() == "Georgia" }, "the click selected Georgia")
        press(.rightArrow)
        let next = try XCTUnwrap(selected())
        XCTAssertNotEqual(next, "Georgia", "Right moved off the clicked card")
        press(.downArrow)
        XCTAssertGreaterThan(card(try XCTUnwrap(selected())).frame.minY, card(next).frame.minY + 20, "Down moved a row")
    }

    /// After a click on empty grid space (the heading area) the arrows still move the selection.
    func testArrowsAfterClickingEmptySpace() throws {
        ready()
        card("Georgia").click()
        XCTAssertTrue(wait(5) { self.selected() == "Georgia" })
        let heading = app.staticTexts["Choose the Display face"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        heading.coordinate(withNormalizedOffset: CGVector(dx: 6, dy: 0.5)).click()      // far right of the heading, on empty ground
        press(.rightArrow)
        XCTAssertNotNil(selected())
        XCTAssertNotEqual(selected(), "Georgia", "Right moved after a click on empty space")
    }

    /// Arrows typed in the search field stay in it. Escape gives the keys back to the grid.
    func testArrowsStayInTheSearchFieldAndEscapeReturnsToTheGrid() throws {
        ready()
        card("Georgia").click()
        XCTAssertTrue(wait(5) { self.selected() == "Georgia" })
        let search = app.textFields["Search name, foundry or designer"].firstMatch
        search.click()
        search.typeText("a")
        press(.leftArrow)
        press(.downArrow)
        XCTAssertEqual(selected(), "Georgia", "arrows typed in search did not move the selection")
        search.typeKey(.escape, modifierFlags: [])        // clears the text
        search.typeKey(.escape, modifierFlags: [])        // gives the keys back
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        press(.rightArrow)
        XCTAssertNotNil(selected())
        XCTAssertNotEqual(selected(), "Georgia", "after Escape the arrows move the grid")
    }

    /// Arrows typed in the Sample field stay in it. Escape gives the keys back to the grid.
    func testArrowsStayInTheSampleFieldAndEscapeReturnsToTheGrid() throws {
        ready()
        card("Georgia").click()
        XCTAssertTrue(wait(5) { self.selected() == "Georgia" })
        let sample = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "Type your own line")).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.click()
        sample.typeText("ab")
        press(.leftArrow)
        press(.rightArrow)
        press(.downArrow)
        XCTAssertEqual(selected(), "Georgia", "arrows typed in Sample did not move the selection")
        XCTAssertEqual(sample.value as? String, "ab")
        sample.typeKey(.escape, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        press(.rightArrow)
        XCTAssertNotNil(selected())
        XCTAssertNotEqual(selected(), "Georgia", "after Escape the arrows move the grid")
    }

    /// Space previews the selected face.
    func testSpacePreviews() throws {
        ready()
        press(.downArrow)
        let name = try XCTUnwrap(selected())
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Preview")).firstMatch.waitForExistence(timeout: 5), "Space opened the preview of \(name)")
    }

    /// Text: a new brand selects nothing. Down selects the first row, Down again the next.
    func testTextListSelectsNothingUntilAKeyThenMoves() throws {
        ready()
        app.typeKey("2", modifierFlags: .command)
        func rowSelected() -> String? {
            let hits = names.filter { n in
                let row = textRow(n)
                return row.exists && row.isSelected
            }
            return hits.count == 1 ? hits[0] : nil
        }
        XCTAssertTrue(wait(20) { self.names.contains { self.textRow($0).exists } }, "the Text list is drawn")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertNil(rowSelected(), "no row is selected before a key or click")
        press(.downArrow)
        let first = try XCTUnwrap(rowSelected(), "Down selected the first row")
        press(.downArrow)
        let second = try XCTUnwrap(rowSelected())
        XCTAssertNotEqual(first, second, "Down moved to the next row")
        press(.upArrow)
        XCTAssertEqual(rowSelected(), first, "Up moved back")
    }
}
