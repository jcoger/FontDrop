import FontDropCore
import XCTest

/// Real mouse and keyboard on Display (R9a): click a card, scroll the grid, type in the Sample field. The first real
/// use found the mouse dead on Display and Sample impossible to type in. Same fixture as KeyboardUITests: a temp
/// library with two system families and a brand named Acme.
final class MouseUITests: XCTestCase {
    private var dir = ""
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial", "Georgia"].flatMap { f in ["", " Bold", " Italic", " Bold Italic"].map { "\(f)\($0).ttf" } }
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") { throw XCTSkip("no system \(f)") }
        dir = NSTemporaryDirectory() + "fontdrop-ui-mouse-\(UUID().uuidString)"
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

    /// A Display card: one button whose label starts with the family name.
    private func card(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", ", \(name),")).firstMatch
    }

    private func wait(_ seconds: TimeInterval, until check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if check() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return check()
    }

    /// Click a Display card with the mouse: the inspector fills in. Click the Sample field and type: the text lands in it.
    func testClickACardThenTypeInSample() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        let card = card("Georgia")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the Georgia card is drawn")
        card.click()
        let sample = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "Type your own line")).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 10), "clicking a card opened it in the inspector")
        sample.click()
        sample.typeText("Hello")
        XCTAssertTrue(wait(5) { (sample.value as? String) == "Hello" }, "typing reached the Sample field, it holds \(String(describing: sample.value))")
    }

    /// Scroll over the grid: nothing throws and the window stays where it is.
    func testScrollingTheGridDoesNotMoveTheWindow() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        let card = card("Georgia")
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        let before = window.frame
        card.scroll(byDeltaX: 0, deltaY: -60)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(window.frame.origin.x, before.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, before.origin.y, accuracy: 1)
    }
}

extension MouseUITests {
    /// The top row of Display sits in the strip the window buttons use. Clicks there must reach it.
    func testTheSearchFieldAndInspectorToggleTakeClicks() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        let search = app.textFields["Search name, foundry or designer"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.click()
        search.typeText("Geo")
        let ok = (0..<20).contains { _ in RunLoop.current.run(until: Date().addingTimeInterval(0.2)); return (search.value as? String) == "Geo" }
        XCTAssertTrue(ok, "typing reached the search field: \(String(describing: search.value))")
        let toggle = app.buttons["Inspector"].firstMatch
        XCTAssertTrue(toggle.exists)
        toggle.click()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(app.groups["Inspector"].exists, "the toggle hid the inspector")
    }
}
