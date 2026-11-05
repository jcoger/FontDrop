import AppKit
import FontDropCore
import XCTest
@testable import FontDrop

/// The pre-merge review fixes (round R7b). Every test uses a throwaway database and preferences suite.
@MainActor
final class ReviewFixTests: XCTestCase {
    private func tempDB() -> String { NSTemporaryDirectory() + "fontdrop-r7b-\(UUID().uuidString).db" }
    private func suite() -> UserDefaults { makeTestSuite("fontdrop-r7b-tests") }

    private func model(db: String? = nil, defaults: UserDefaults? = nil, folder: String? = nil) async -> AppModel {
        var args = ["FontDrop", "--db", db ?? tempDB()]
        if let folder { args += ["--scan-folders", folder] } else { args.append("--bench") }
        let m = AppModel(options: LaunchOptions(arguments: args, environment: [:]), defaults: defaults ?? suite())
        await m.bootstrap()
        return m
    }

    private func fixtureFolder() throws -> String {
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial", "Georgia"].flatMap { f in ["", " Bold", " Italic", " Bold Italic"].map { "\(f)\($0).ttf" } }
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") { throw XCTSkip("no system \(f)") }
        let dir = NSTemporaryDirectory() + "fontdrop-r7b-fixture-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(dir)/\(f)") }
        return dir
    }

    // MARK: 1. The dial's scroll wheel reads the live view

    func testScrollTravelBecomesStopsAndKeepsTheRemainder() {
        var scroll = DialScroll()
        XCTAssertEqual(scroll.add(deltaY: 10, precise: true), [], "under 14 points: nothing yet")
        XCTAssertEqual(scroll.add(deltaY: 10, precise: true), [1], "20 points: one stop up, 6 left")
        XCTAssertEqual(scroll.add(deltaY: -30, precise: true), [-1], "6 - 30 = -24: one stop down, -10 left")
        XCTAssertEqual(scroll.add(deltaY: 5, precise: false), [1], "a line wheel counts 6 points a line: -10 + 30 = 20, one stop up")
        scroll.reset()
        XCTAssertEqual(scroll.remainder, 0)
    }

    /// The bug: the monitor was installed once and kept the first copy of the view, so after one stop it read an old
    /// scale. The box now holds a closure that every body pass replaces.
    func testTheWheelAlwaysCallsTheLatestHandlerSoItMovesOneStopPerTurn() {
        let live = DialLive()
        live.hovering = true
        var ratioIndex = 2                                 // the "view's" current stop
        var turned: [Int] = []
        // Each body pass installs a closure over that pass's value, as RatioDial.body does.
        func render() {
            let current = ratioIndex
            live.step = { direction in
                let next = DialMath.step(from: current, by: direction)
                turned.append(next)
                ratioIndex = next                         // the parent stores it, the dial re-renders
            }
        }
        render()
        XCTAssertTrue(live.scrolled(deltaY: 20, precise: true, ended: false))
        render()
        XCTAssertTrue(live.scrolled(deltaY: 20, precise: true, ended: false))
        XCTAssertEqual(turned, [3, 4], "two turns, two stops: the second did not start from the stale stop")
    }

    func testTheWheelIgnoresEventsOffTheDialAndAfterItGoesAway() {
        let live = DialLive()
        var steps = 0
        live.step = { _ in steps += 1 }
        XCTAssertFalse(live.scrolled(deltaY: 100, precise: true, ended: false), "pointer is not over the dial: the event goes on")
        XCTAssertEqual(steps, 0)
        live.installMonitor(); live.installMonitor(); live.removeMonitor()        // twice installs once; removing is safe
        live.removeMonitor()
    }

    // MARK: 2. The window moves only from its empty chrome

    func testTheWindowDoesNotMoveFromAnywhereAndOnlyTheHandleDrags() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.isMovableByWindowBackground = true            // as the old setup left it
        WindowChrome.configure(window)
        XCTAssertFalse(window.isMovableByWindowBackground, "dragging a control must not move the window")
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(WindowDragHandle.Handle().mouseDownCanMoveWindow, "the empty strip is the way to drag the window")
    }

    // MARK: 5. Command-Z does not reach the library from behind a sheet

    func testUndoGoesToATextBoxFirstThenTheMainWindowOnly() {
        XCTAssertEqual(UndoRoute.route(textCan: true, isMainWindow: false, hasSheet: true), .text, "typing in a sheet's field can be undone")
        XCTAssertEqual(UndoRoute.route(textCan: false, isMainWindow: true, hasSheet: false), .model)
        XCTAssertEqual(UndoRoute.route(textCan: false, isMainWindow: true, hasSheet: true), .ignore, "a sheet or alert is up")
        XCTAssertEqual(UndoRoute.route(textCan: false, isMainWindow: false, hasSheet: false), .ignore, "the sheet itself or the About panel is key")
        XCTAssertEqual(UndoRoute.route(textCan: false, window: nil), .ignore, "no key window")
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        XCTAssertEqual(UndoRoute.route(textCan: false, window: panel), .ignore, "a panel cannot become main")
    }

    // MARK: 4. Return and Space act only on a face that is on screen

    func testReturnAndSpaceIgnoreAFaceTheSearchHides() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let m = await model(folder: dir)
        await m.createBrand("Acme")
        m.filter.sources = [.yours, .google, .system]
        await m.finderSettled()
        m.screen = .display
        m.selectedFamily = "Arial"
        XCTAssertEqual(m.selectedFaceName, "Arial", "on screen: Return would use it")
        XCTAssertTrue(m.canUseSelected)

        m.search = "Georgia"
        await m.finderSettled()
        XCTAssertEqual(m.visibleFamilies.map(\.name), ["Georgia"])
        XCTAssertNil(m.selectedFaceName, "Arial is hidden by the search")
        XCTAssertFalse(m.canUseSelected)
        await m.useSelected()
        XCTAssertNil(m.choices["display"], "Return did not choose the hidden face")
        m.togglePreview()
        XCTAssertNil(m.preview, "Space did not preview it")

        m.search = ""
        await m.finderSettled()
        XCTAssertEqual(m.selectedFaceName, "Arial", "back on screen")
    }

    func testTheTextListHasTheSameGuard() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let m = await model(folder: dir)
        await m.createBrand("Acme")
        m.filter.sources = [.yours, .google, .system]
        await m.finderSettled()
        await m.choose("display", family: "Arial")
        m.screen = .reading
        await m.loadCandidates()
        let rows = ReadingRows.rows(current: m.currentReadingCandidate, shown: m.readingResult.shown, search: m.search)
        let first = try XCTUnwrap(rows.first)
        m.selectedCandidate = first.id
        XCTAssertEqual(m.selectedFaceName, first.family)
        m.search = "zzzz-no-such-family"
        XCTAssertNil(m.selectedFaceName, "the row is filtered out: Return and Space do nothing")
        XCTAssertFalse(m.canUseSelected)
    }

    // MARK: 6. Settings made before a brand exists go onto the first brand

    func testTheScaleColorsAndFaceSettingsSetBeforeAnyBrandAreKept() {
        let scale = ScaleStore(persist: false)
        scale.update(brand: nil) { $0.body = 18; $0.ratio = 1.25; $0.locked = true }
        scale.adoptUnbranded(into: 7)
        XCTAssertEqual(scale.scale(brand: 7).body, 18)
        XCTAssertTrue(scale.scale(brand: 7).locked)
        XCTAssertEqual(scale.scale(brand: nil), TypeScale(), "nothing left for the next brand to take")

        let style = BrandStyleStore(persist: false, defaults: suite())
        let colors = TemplatePalette(background: HexColor(hex: "#101312")!, text: HexColor(hex: "#E8E8E4")!, accent: HexColor(hex: "#3366FF")!)
        style.setPalette(colors, brand: nil)
        style.adoptUnbranded(into: 7)
        XCTAssertEqual(style.palette(brand: 7), colors)
        XCTAssertEqual(style.palette(brand: nil), .paper)

        let faces = TypeSettingsStore(persist: false)
        let key = TypeSettingsStore.key(brand: nil, job: "display", family: "Acme Serif")
        faces.update(key, job: "display") { $0.tracking = 0.02 }
        faces.adoptUnbranded(into: 7)
        let moved = TypeSettingsStore.key(brand: 7, job: "display", family: "Acme Serif")
        XCTAssertEqual(faces.settings(moved, job: "display").tracking, 0.02)
        XCTAssertNil(faces.map[key], "the unbranded copy is gone")
    }

    func testTheFirstBrandTakesWhatWasSetWithNoBrandAndSavesIt() async throws {
        let m = await model()
        XCTAssertTrue(m.brands.isEmpty)
        m.updateScale { $0.body = 18; $0.ratio = 1.25; $0.locked = true }
        let made = await m.createBrand("Acme")
        let id = try XCTUnwrap(made)
        XCTAssertEqual(m.scale.body, 18, "the brand has the settings")
        XCTAssertTrue(m.scale.locked)
        // A bench run never writes. Check the memory path here; the database path is covered below.
        let madeSecond = await m.createBrand("Beta")
        let second = try XCTUnwrap(madeSecond)
        XCTAssertNotEqual(second, id)
        XCTAssertEqual(m.scale, TypeScale(), "a second brand starts clean")
    }

    func testTheLegacyKeyZeroSettingsAreCarriedToTheFirstBrandInTheDatabase() async throws {
        let db = tempDB()
        defer { for suffix in ["", "-wal", "-shm", ".scale.json"] { try? FileManager.default.removeItem(atPath: db + suffix) } }
        try Data(#"{"0":{"body":19,"ratio":1.25,"locked":true}}"#.utf8).write(to: URL(fileURLWithPath: db + ".scale.json"))
        // A real run, not a bench: the write-behind is on, so the carried values reach the table.
        let empty = NSTemporaryDirectory() + "fontdrop-r7b-empty-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: empty) }
        let m = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", db, "--scan-folders", empty], environment: [:]), defaults: suite())
        await m.bootstrap()
        XCTAssertTrue(m.brands.isEmpty)
        let made = await m.createBrand("Acme")
        let id = try XCTUnwrap(made)
        XCTAssertEqual(m.scaleStore.scale(brand: id).body, 19)
        XCTAssertTrue(m.scaleStore.scale(brand: id).locked)
        let rows = try XCTUnwrap(m.core).scalesList()
        XCTAssertEqual(rows.map(\.brandId), [id])
        XCTAssertEqual(rows.first?.body, 19)
    }

    // MARK: 10. A hidden sidebar

    func testTheInspectorRuleDoesNotChargeAHiddenSidebarsWidth() {
        XCTAssertFalse(ReadingLayout.inspectorFits(windowWidth: 1180, sidebarShown: true))
        XCTAssertTrue(ReadingLayout.inspectorFits(windowWidth: 1180, sidebarShown: false), "235 pt come back when the sidebar is hidden")
        XCTAssertTrue(ReadingLayout.inspectorFits(windowWidth: 1360), "the old call still means shown")
        XCTAssertEqual(ReadingLayout.hiddenSidebarInset(sidebarShown: true), 0)
        XCTAssertGreaterThanOrEqual(ReadingLayout.hiddenSidebarInset(sidebarShown: false), 64, "clears the three traffic lights")
    }

    func testTheInspectorComesBackWhenTheSidebarIsHidden() async {
        let m = await model()
        m.screen = .reading
        m.windowWidth = 1180
        m.applyInspectorRule()
        XCTAssertFalse(m.showInspector, "no room beside the sidebar")
        m.showSidebar = false
        m.applyInspectorRule()
        XCTAssertTrue(m.showInspector, "room without it")
    }

    func testTheSidebarStateIsRemembered() async {
        let defaults = suite()
        let first = await model(defaults: defaults)
        XCTAssertTrue(first.showSidebar)
        first.showSidebar = false
        let second = await model(defaults: defaults)
        XCTAssertFalse(second.showSidebar, "hidden stays hidden on the next launch")
        second.showSidebar = true
        let third = await model(defaults: defaults)
        XCTAssertTrue(third.showSidebar)
    }
}
