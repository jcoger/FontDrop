import FontDropCore
import XCTest

/// Drives the real app with real key events and scrolls, and never clicks. The library is a temp copy with one brand
/// named Acme and two system families (Arial, Georgia), so nothing here touches the designer's own library.
///
/// `--isolated` keeps the run apart from the designer's setup: the temp database, no preferences saved, a rescan of the fixture folder only.
final class KeyboardUITests: XCTestCase {
    private var dir = ""
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial", "Georgia"].flatMap { f in ["", " Bold", " Italic", " Bold Italic"].map { "\(f)\($0).ttf" } }
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") { throw XCTSkip("no system \(f)") }
        dir = NSTemporaryDirectory() + "fontdrop-ui-\(UUID().uuidString)"
        let fonts = dir + "/fonts"
        try FileManager.default.createDirectory(atPath: fonts, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(fonts)/\(f)") }
        // Seed the library: the two families and the brand. The app opens this file and rescans nothing.
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

    /// The sidebar row for a job reads "Display, Arial" once a face is chosen, and just "Display" before.
    private func chosenFace(_ job: String) -> String? {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(job), "))
        guard rows.count > 0 else { return nil }
        return rows.firstMatch.label
    }

    private func wait(_ seconds: TimeInterval, until check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if check() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return check()
    }

    func testKeysWorkAtLaunchWithoutAClick() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))

        // Display: Down, Return. No click first: the grid has the keys from the start.
        XCTAssertTrue(wait(20) { self.app.descendants(matching: .any)["Display"].exists || self.chosenFace("Display") != nil })
        _ = wait(6) { self.app.staticTexts["Arial"].exists || self.app.staticTexts["Georgia"].exists }     // the cards are drawn
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(wait(8) { self.chosenFace("Display") != nil }, "Down then Return chose a Display face")

        // Text: command-2, then Down, Return. The list takes the keys without a click.
        app.typeKey("2", modifierFlags: .command)
        var chosen = false
        for _ in 0..<10 where !chosen {
            RunLoop.current.run(until: Date().addingTimeInterval(1))      // the candidates load in the background
            app.typeKey(.downArrow, modifierFlags: [])
            app.typeKey(.return, modifierFlags: [])
            chosen = wait(1.5) { self.chosenFace("Text") != nil }
        }
        XCTAssertTrue(chosen, "Down then Return chose a Text face")

        // Set: command-3. (With both faces chosen, Set shows the dial.) Scroll the dial: each turn is one stop, from the live value, not from the first one.
        app.typeKey("3", modifierFlags: .command)
        let dial = app.descendants(matching: .any)["Ratio"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 10))
        // The dial's own accessibility value is a description XCUITest cannot read, so read the ratio where the app also
        // shows it: the sidebar's Set row, "Set, 15 pt · 1.2" once the scale is locked.
        func ratio() -> String {
            let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Set, "))
            guard rows.count > 0 else { return "" }
            return rows.firstMatch.label.components(separatedBy: "\u{00B7} ").last ?? ""
        }
        dial.hover()
        // Down to the first stop (1.2), however far Auto started from it.
        for _ in 0..<5 where ratio() != "1.2" {
            dial.scroll(byDeltaX: 0, deltaY: -40)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTAssertEqual(ratio(), "1.2", "scrolling down reached the first stop")
        dial.scroll(byDeltaX: 0, deltaY: 40)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(ratio(), "1.25", "the first scroll up moved one stop")
        dial.scroll(byDeltaX: 0, deltaY: 40)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(ratio(), "1.333", "the second scroll moved a second stop, not the same one again")
    }

    /// A drag that starts on a control must not move the window.
    func testDraggingTheDialDoesNotMoveTheWindow() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        // Set only shows the dial once Display and Text each have a face.
        _ = wait(6) { self.app.staticTexts["Arial"].exists || self.app.staticTexts["Georgia"].exists }
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(wait(8) { self.chosenFace("Display") != nil })
        app.typeKey("2", modifierFlags: .command)
        var chosen = false
        for _ in 0..<10 where !chosen {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            app.typeKey(.downArrow, modifierFlags: [])
            app.typeKey(.return, modifierFlags: [])
            chosen = wait(1.5) { self.chosenFace("Text") != nil }
        }
        XCTAssertTrue(chosen)
        app.typeKey("3", modifierFlags: .command)
        let dial = app.descendants(matching: .any)["Ratio"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 20))
        let before = window.frame
        let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3))
        start.press(forDuration: 0.2, thenDragTo: end)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(window.frame.origin.x, before.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, before.origin.y, accuracy: 1)
    }
}
