import FontDropCore
import XCTest
@testable import FontDrop

/// R8: what the owner saw on the first real launch.
@MainActor
final class R8Tests: XCTestCase {
    private func fixtureFolder() throws -> String {
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial.ttf", "Arial Bold.ttf", "Arial Italic.ttf", "Arial Bold Italic.ttf"]
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") { throw XCTSkip("no system Arial") }
        let dir = NSTemporaryDirectory() + "fontdrop-r8-fixture-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(dir)/\(f)") }
        return dir
    }

    private func model(folder: String, defaults: UserDefaults) -> AppModel {
        let db = NSTemporaryDirectory() + "fontdrop-r8-\(UUID().uuidString).db"
        return AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", db, "--scan-folders", folder], environment: [:]), defaults: defaults)
    }

    // MARK: Saved is not remembered

    /// The exact value an older build left in the owner's preferences.
    private let oldValue = #"{"showHidden":false,"kinds":[],"sources":[],"traits":[],"savedOnly":true}"#

    func testPersistedSavedOnlyIsIgnoredAndCleared() {
        let d = makeTestSuite("fontdrop-r8-tests")
        d.set(Data(oldValue.utf8), forKey: FinderFilter.storageKey)
        XCTAssertFalse(FinderFilter.load(from: d).savedOnly)
        let again = try? JSONSerialization.jsonObject(with: d.data(forKey: FinderFilter.storageKey)!) as? [String: Any]
        XCTAssertEqual(again?["savedOnly"] as? Bool, false, "the old value is rewritten once, not left behind")
    }

    func testSavedOnlyIsNeverWritten() {
        let d = makeTestSuite("fontdrop-r8-tests")
        var f = FinderFilter.standard
        f.savedOnly = true
        f.save(to: d)
        XCTAssertFalse(FinderFilter.load(from: d).savedOnly)
    }

    func testLaunchWithPersistedSavedOnlyShowsTheFullGrid() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let d = makeTestSuite("fontdrop-r8-tests")
        d.set(Data(oldValue.utf8), forKey: FinderFilter.storageKey)
        let model = model(folder: dir, defaults: d)
        await model.bootstrap()
        await model.finderSettled()
        XCTAssertFalse(model.filter.savedOnly)
        XCTAssertTrue(model.visibleFamilies.contains { $0.name == "Arial" }, "the grid is full, not empty")
    }

    func testSavedWithNothingSavedFallsBackAndShowAllFontsResets() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = model(folder: dir, defaults: makeTestSuite("fontdrop-r8-tests"))
        await model.bootstrap()
        model.filter.savedOnly = true
        await model.finderSettled()
        XCTAssertTrue(model.visibleFamilies.isEmpty, "Saved with nothing saved is empty")
        model.showAllFonts()
        await model.finderSettled()
        XCTAssertFalse(model.filter.savedOnly)
        XCTAssertEqual(model.filter.sources, FinderFilter.standard.sources)
        XCTAssertFalse(model.visibleFamilies.isEmpty)
    }

    func testANewBrandStartsOnTheStandardScope() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = model(folder: dir, defaults: makeTestSuite("fontdrop-r8-tests"))
        await model.bootstrap()
        model.filter.sources = [.system]
        model.filter.savedOnly = true
        await model.createBrand("Acme")
        XCTAssertEqual(model.filter.sources, [.yours, .google])
        XCTAssertFalse(model.filter.savedOnly)
    }

    // MARK: The inspector

    func testInspectorShowsNothingForAFaceTheGridCannotShow() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = model(folder: dir, defaults: makeTestSuite("fontdrop-r8-tests"))
        await model.bootstrap()
        await model.createBrand("Acme")
        await model.finderSettled()
        model.selectedFamily = "Arial"
        XCTAssertEqual(model.inspectedFamily(job: "display")?.name, "Arial")
        model.filter.savedOnly = true            // nothing is saved, so the grid is empty
        await model.finderSettled()
        XCTAssertTrue(model.visibleFamilies.isEmpty)
        XCTAssertNil(model.inspectedFamily(job: "display"), "an empty grid shows the empty inspector")
        await model.choose("display", family: "Arial")
        XCTAssertEqual(model.inspectedFamily(job: "display")?.name, "Arial", "a chosen face shows as the current one")
    }

    // MARK: Sample field and window buttons

    func testSampleScalesLongLinesToFitAndLeavesShortOnesAlone() {
        XCTAssertEqual(SampleFit.scale(lineWidth: 100, width: 200), 1)
        XCTAssertEqual(SampleFit.scale(lineWidth: 400, width: 200), 0.5, accuracy: 0.0001)
    }

    func testButtonsSitTwentyPointsInsideThePanel() {
        let h = WindowChrome.panelGutter + WindowChrome.buttonInset + 14 + WindowChrome.panelGutter
        let pts = WindowButtons.layout(buttonSize: CGSize(width: 14, height: 14), step: 20, stripHeight: h)
        XCTAssertEqual(pts[0].x, 28)
        XCTAssertEqual(h - pts[0].y - 14, 28, "top edge: gutter plus inset")
        XCTAssertEqual(pts[2].x, 68)
        let rightEdge = pts[2].x + 14
        XCTAssertGreaterThanOrEqual(ReadingLayout.hiddenInset + WindowChrome.panelGutter, rightEdge + 8, "content clears the lights when the sidebar is hidden")
    }
}
