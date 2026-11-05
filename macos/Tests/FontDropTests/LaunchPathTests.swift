import FontDropCore
import XCTest
@testable import FontDrop

/// What a user hits at launch, without `--bench`: the library opens, the background rescan runs, and Reading shows
/// what the rescan found. Every test uses a throwaway DB, a throwaway preferences suite and a fixture folder.
@MainActor
final class LaunchPathTests: XCTestCase {
    private func tempDB() -> String { NSTemporaryDirectory() + "fontdrop-launch-\(UUID().uuidString).db" }

    /// A folder holding one real family with all four styles, copied from the system fonts.
    private func fixtureFolder() throws -> String {
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial.ttf", "Arial Bold.ttf", "Arial Italic.ttf", "Arial Bold Italic.ttf"]
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") {
            throw XCTSkip("no system Arial to build a fixture from")
        }
        let dir = NSTemporaryDirectory() + "fontdrop-fixture-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(dir)/\(f)") }
        return dir
    }

    private func suite() -> UserDefaults { UserDefaults(suiteName: "fontdrop-launch-tests-\(UUID().uuidString)")! }

    // MARK: The launch path

    /// Start on Reading with an empty library and no `--bench`. The rescan scans the fixture folder, and the
    /// Reading list then holds its family. Before the rescan reloaded Reading, this list stayed empty.
    func testLaunchRescanFeedsReading() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let options = LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--scan-folders", dir, "--screen", "reading"], environment: [:])
        XCTAssertFalse(options.bench, "this test is the launch path, so it must not run as a bench")
        let model = AppModel(options: options, defaults: suite())
        XCTAssertEqual(model.scanState, .idle)
        await model.bootstrap()
        XCTAssertTrue(model.rescanDone)
        XCTAssertEqual(model.scanState, .idle, "the scan finished without an error")
        XCTAssertTrue(model.families.contains { $0.name == "Arial" }, "the library holds the scanned family")
        XCTAssertEqual(model.screen, .reading)
        XCTAssertNil(model.candidatesError)
        XCTAssertTrue(model.candidates.contains { $0.family == "Arial" }, "Reading reflects the rescanned library: \(model.candidates.map(\.family))")
        XCTAssertFalse(model.readingIsLoading)
    }

    /// A second bootstrap (a second window, a repeated task) opens nothing and scans nothing.
    func testBootstrapRunsOnce() async {
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench"], environment: [:]))
        await model.bootstrap()
        let steps = model.timings.count
        XCTAssertGreaterThan(steps, 0)
        await model.bootstrap()
        XCTAssertEqual(model.timings.count, steps, "the second call returned at once")
    }

    // MARK: Test runs never touch the real app's state

    func testBenchRunsGetThrowawayPreferences() async {
        let key = "lastBrand"
        let before = UserDefaults.standard.object(forKey: key) as? Int64
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench"], environment: [:]))
        XCTAssertFalse(model.defaults === UserDefaults.standard)
        await model.bootstrap()
        await model.createBrand("Throwaway brand")        // selects it, which saves "lastBrand"
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Int64, before, "the real app's last brand is untouched")
        XCTAssertNotNil(model.defaults.object(forKey: key), "it went to the throwaway suite")
    }

    func testATestHostNeverOpensTheLiveLibrary() {
        let options = LaunchOptions(arguments: ["FontDrop"], environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        XCTAssertTrue(options.bench)
        XCTAssertFalse(options.dbPath.contains("Application Support"))
        XCTAssertTrue(options.dbPath.hasPrefix(NSTemporaryDirectory()))
        // A named DB (the TEST_RUNNER_FONTDROP_DB copy) is still honoured, still as a bench.
        let named = LaunchOptions(arguments: ["FontDrop"], environment: ["XCTestConfigurationFilePath": "x", "FONTDROP_DB": "/tmp/copy.db"])
        XCTAssertEqual(named.dbPath, "/tmp/copy.db")
        XCTAssertTrue(named.bench)
        // A normal launch is not a bench and uses the shared DB.
        let normal = LaunchOptions(arguments: ["FontDrop"], environment: [:])
        XCTAssertFalse(normal.bench)
        XCTAssertTrue(normal.dbPath.contains("Application Support"))
    }

    // MARK: Saved style files that moved

    func testStylePathIsKeptRemappedOrDropped() {
        let valid = ["/fonts/New/Alpha-Regular.otf", "/fonts/New/Alpha-Bold.otf", "/fonts/New/Alpha-Bold.ttf"]
        XCTAssertEqual(StylePathRepair.repaired("/fonts/New/Alpha-Regular.otf", valid: valid), "/fonts/New/Alpha-Regular.otf", "still listed")
        XCTAssertEqual(StylePathRepair.repaired("/fonts/Old/Alpha-Regular.otf", valid: valid), "/fonts/New/Alpha-Regular.otf", "moved folder, same file name")
        XCTAssertEqual(StylePathRepair.repaired("/fonts/Old/alpha-bold.TTF", valid: valid), "/fonts/New/Alpha-Bold.otf", "the .otf of the style wins")
        XCTAssertNil(StylePathRepair.repaired("/fonts/Old/Alpha-Black.otf", valid: valid), "gone: drop it")
    }

    func testStoreRepairsSavedStylePathsAfterTheLibraryChanges() {
        let store = TypeSettingsStore(persist: false)
        store.update("1/reading/Alpha", job: "reading") { $0.stylePath = "/old/Alpha-Bold.otf" }
        store.update("1/reading/Beta", job: "reading") { $0.stylePath = "/gone/Beta-Black.otf" }
        store.update("1/display/Gamma", job: "display") { $0.stylePath = "/kept/Gamma-Bold.otf" }     // family not in the library
        store.update("1/reading/Delta", job: "reading") { $0.stylePath = "/d/Delta-Regular.otf" }       // still listed
        let changed = store.repairStylePaths(
            files: ["Alpha": ["/new/Alpha-Regular.otf", "/new/Alpha-Bold.otf"], "Beta": ["/b/Beta-Regular.otf"], "Delta": ["/d/Delta-Regular.otf"]],
            regular: ["Alpha": "/new/Alpha-Regular.otf", "Beta": "/b/Beta-Regular.otf", "Delta": "/d/Delta-Regular.otf"])
        XCTAssertEqual(changed, 2)
        XCTAssertEqual(store.settings("1/reading/Alpha", job: "reading").stylePath, "/new/Alpha-Bold.otf")
        XCTAssertNil(store.settings("1/reading/Beta", job: "reading").stylePath)
        XCTAssertEqual(store.settings("1/display/Gamma", job: "display").stylePath, "/kept/Gamma-Bold.otf")
        XCTAssertEqual(store.settings("1/reading/Delta", job: "reading").stylePath, "/d/Delta-Regular.otf")
    }

    // MARK: Scan status

    func testScanStatusStringsArePlainAndHaveNoEmDashes() {
        for s in [Lexicon.Scan.updating, Lexicon.Scan.failed, Lexicon.Scan.retry, Lexicon.Scan.scanningFonts] {
            XCTAssertFalse(s.contains("\u{2014}"), s)
            XCTAssertFalse(s.contains("\u{2013}"), s)
        }
        XCTAssertEqual(Lexicon.Scan.updating, "Updating your library\u{2026}")
        XCTAssertEqual(Lexicon.Scan.scanningFonts, "Scanning your fonts\u{2026}")
    }

    func testTheScanningStateEndsWhenTheScanDoes() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--scan-folders", dir], environment: [:]), defaults: suite())
        XCTAssertFalse(model.scanningEmptyLibrary, "not scanning yet")
        await model.bootstrap()
        XCTAssertFalse(model.scanningEmptyLibrary, "done: the library has families")
    }
}
