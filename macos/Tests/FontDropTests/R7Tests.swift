import FontDropCore
import SQLite3
import XCTest
@testable import FontDrop

/// Round R7: keyboard, number fields, launch safety, About. Every test uses a throwaway DB and preferences suite.
@MainActor
final class R7Tests: XCTestCase {
    private func tempDB() -> String { NSTemporaryDirectory() + "fontdrop-r7-\(UUID().uuidString).db" }
    private func suite() -> UserDefaults { makeTestSuite("fontdrop-r7-tests") }

    private func makeModel(extra: [String] = []) async -> AppModel {
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench"] + extra, environment: [:]), defaults: suite())
        await model.bootstrap()
        await model.createBrand("Test brand")
        return model
    }

    private func family(_ name: String, id: String) -> FamilySummary {
        FamilySummary(name: name, filePath: "/nonexistent/\(name).otf", fontId: id, styleCount: 1, skeleton: "geometric",
                      serif: false, isTrial: false, foundryUrl: nil, vendor: nil, foundry: nil)
    }

    /// A folder with two real families (Arial and Georgia, each with four styles), copied from the system fonts.
    private func fixtureFolder() throws -> String {
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial.ttf", "Arial Bold.ttf", "Arial Italic.ttf", "Arial Bold Italic.ttf",
                     "Georgia.ttf", "Georgia Bold.ttf", "Georgia Italic.ttf", "Georgia Bold Italic.ttf"]
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") { throw XCTSkip("no system \(f)") }
        let dir = NSTemporaryDirectory() + "fontdrop-r7-fixture-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(dir)/\(f)") }
        return dir
    }

    // MARK: Number fields

    func testNumberFieldReadsWhatWasTyped() {
        let range = 9.0...24.0
        XCTAssertEqual(NumberFieldMath.parse("17", range: range), 17)
        XCTAssertEqual(NumberFieldMath.parse(" 17.5 pt", range: range), 17.5)
        XCTAssertEqual(NumberFieldMath.parse("1,5", range: 0.8...2.2), 1.5, "a comma is a decimal mark")
        XCTAssertEqual(NumberFieldMath.parse("99", range: range), 24, "clamped to the top")
        XCTAssertEqual(NumberFieldMath.parse("2", range: range), 9, "clamped to the bottom")
        XCTAssertEqual(NumberFieldMath.parse("-0.02 em", range: -0.08...0.3), -0.02)
        XCTAssertNil(NumberFieldMath.parse("abc", range: range))
        XCTAssertNil(NumberFieldMath.parse("", range: range))
    }

    func testNumberFieldSteps() {
        let range = 0.8...2.2
        XCTAssertEqual(NumberFieldMath.stepped(1.45, by: 0.05, direction: 1, range: range), 1.5, "no float noise: 1.5000000000000002")
        XCTAssertEqual(NumberFieldMath.stepped(2.2, by: 0.05, direction: 1, range: range), 2.2, "stops at the top")
        XCTAssertEqual(NumberFieldMath.stepped(0.8, by: 0.05, direction: -1, range: range), 0.8, "stops at the bottom")
        XCTAssertEqual(NumberFieldMath.stepped(15, by: 1, direction: -1, range: 9...24), 14)
        XCTAssertEqual(NumberFieldMath.text(1.5, decimals: 2), "1.50")
    }

    // MARK: Arrow keys in the Display grid

    func testGridNavigationMovesByCellAndRow() {
        XCTAssertEqual(GridNav.columns(width: 800, minimum: 220, spacing: 14), 3)
        XCTAssertEqual(GridNav.columns(width: 200, minimum: 220, spacing: 14), 1, "never zero")
        XCTAssertEqual(GridNav.move(count: 10, from: nil, .right, columns: 3), 0, "nothing selected: the first card")
        XCTAssertEqual(GridNav.move(count: 10, from: 0, .right, columns: 3), 1)
        XCTAssertEqual(GridNav.move(count: 10, from: 1, .down, columns: 3), 4)
        XCTAssertEqual(GridNav.move(count: 10, from: 4, .up, columns: 3), 1)
        XCTAssertEqual(GridNav.move(count: 10, from: 1, .up, columns: 3), 1, "stops at the top row")
        XCTAssertEqual(GridNav.move(count: 10, from: 8, .down, columns: 3), 8, "stops at the last row")
        XCTAssertEqual(GridNav.move(count: 10, from: 9, .right, columns: 3), 9)
        XCTAssertEqual(GridNav.move(count: 10, from: 0, .left, columns: 3), 0)
        XCTAssertNil(GridNav.move(count: 0, from: nil, .down, columns: 3))
    }

    // MARK: Undo and redo of a face choice or clear

    func testUndoAndRedoAcrossBothFaces() async {
        let model = await makeModel()
        model.installLibrary([family("Alpha", id: "a"), family("Beta", id: "b"), family("Gamma", id: "g")], [])
        XCTAssertFalse(model.canUndoLast)
        await model.choose("display", family: "Alpha")
        await model.choose("reading", family: "Beta")
        await model.choose("display", family: "Gamma")
        await model.clear("reading")
        XCTAssertEqual(model.undoLastLabel, "Undo clear Text face")

        await model.undoLast()                                        // takes the clear back
        XCTAssertEqual(model.choices["reading"], "Beta")
        XCTAssertEqual(model.redoLastLabel, "Redo clear Text face")
        await model.undoLast()                                        // Gamma back to Alpha
        XCTAssertEqual(model.choices["display"], "Alpha")
        await model.undoLast()                                        // Text face off again (first choice)
        XCTAssertNil(model.choices["reading"])
        await model.undoLast()                                        // Display face off (first choice)
        XCTAssertNil(model.choices["display"])
        XCTAssertFalse(model.canUndoLast)

        await model.redoLast()
        XCTAssertEqual(model.choices["display"], "Alpha")
        await model.redoLast(); await model.redoLast()
        XCTAssertEqual(model.choices["display"], "Gamma")
        await model.redoLast()
        XCTAssertNil(model.choices["reading"], "the clear is done again")
        XCTAssertFalse(model.canRedoLast)

        // A new choice ends the redo line.
        await model.undoLast()
        XCTAssertTrue(model.canRedoLast)
        await model.choose("display", family: "Beta")
        XCTAssertFalse(model.canRedoLast)
    }

    func testTheButtonUndoAndTheMenuUndoShareOneHistory() async {
        let model = await makeModel()
        model.installLibrary([family("Alpha", id: "a"), family("Beta", id: "b")], [])
        await model.choose("reading", family: "Alpha")
        await model.choose("reading", family: "Beta")
        await model.undo("reading")                                   // the inspector's Undo button
        XCTAssertEqual(model.choices["reading"], "Alpha")
        XCTAssertTrue(model.canRedoLast, "the menu can redo what the button took back")
        await model.redoLast()
        XCTAssertEqual(model.choices["reading"], "Beta")
    }

    // MARK: The keyboard walkthrough

    /// Launch, choose Display, choose Text, set the scale with the dial's keys, export CSS: the same functions the
    /// key presses and menu items call, in order, with no pointer.
    func testKeyboardOnlyWalkthrough() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let options = LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--scan-folders", dir], environment: [:])
        let model = AppModel(options: options, defaults: suite())
        await model.bootstrap()                                       // launch: opens the library and scans the fixture
        XCTAssertTrue(model.rescanDone)
        await model.createBrand("Acme")

        // Display: command-1, an arrow key to select, Return to use.
        model.screen = .display
        let families = model.displayGridFamilies
        let cols = GridNav.columns(width: 900, minimum: 220, spacing: 14)
        let first = try XCTUnwrap(GridNav.move(count: families.count, from: nil, .right, columns: cols))
        model.selectedFamily = families[first].name
        XCTAssertEqual(model.keyJob, "display")
        XCTAssertTrue(model.canUseSelected)
        await model.useSelected()                                     // Return
        XCTAssertEqual(model.choices["display"], families[first].name)

        // Text: command-2, the Text list loads, the arrow key selects the first row, Return uses it.
        model.screen = .reading
        await model.loadCandidates()
        let rows = ReadingRows.rows(current: model.currentReadingCandidate, shown: model.readingResult.shown, search: model.search)
        let row = try XCTUnwrap(ListNav.move(rows.map(\.id), from: model.selectedCandidate, by: 1))
        model.selectedCandidate = row
        XCTAssertEqual(model.keyJob, "reading")
        await model.useSelected()                                     // Return
        let text = try XCTUnwrap(model.choices["reading"])
        XCTAssertNotEqual(text, model.choices["display"])

        // Space on the Text list: a large preview of the selected face, Escape closes it.
        model.togglePreview()
        XCTAssertEqual(model.preview, FacePreviewState(job: "reading", family: model.selectedFaceName ?? ""))
        model.closePreview()
        XCTAssertNil(model.preview)

        // Set: command-3, the dial's arrow key steps one stop (right arrow = next ratio), which locks the scale.
        model.screen = .set
        XCTAssertFalse(model.scale.locked)
        let reading = try XCTUnwrap(model.readingFamily)
        // Touching Body while on Auto takes the scale out of Auto and sets the size.
        model.setBody(17, reading: reading.name, fallbackPath: reading.filePath)
        XCTAssertTrue(model.scale.locked)
        XCTAssertEqual(model.scale.body, 17)
        model.returnToAuto()
        XCTAssertFalse(model.scale.locked)
        let stop = DialMath.step(from: DialMath.stopIndex(nearestToRatio: model.scale.ratio), by: 1)
        model.setRatio(DialMath.stops[stop], reading: reading.name, fallbackPath: reading.filePath)
        XCTAssertTrue(model.scale.locked)
        XCTAssertEqual(model.scale.ratio, DialMath.stops[stop])
        // A typed number in the Body field.
        model.updateScale { $0.body = NumberFieldMath.parse("18 pt", range: TypeScale.bodyRange) ?? 0 }
        XCTAssertEqual(model.scale.body, 18)

        // Export CSS: shift-command-C.
        XCTAssertTrue(model.canExport)
        let cssOut = await model.exportText(.css)
        let css = try XCTUnwrap(cssOut)
        XCTAssertTrue(css.contains("--font-display:"), css)
        XCTAssertTrue(css.contains("--font-text:"), css)

        // Command-Z takes the Text choice back, shift-command-Z does it again.
        await model.undoLast()
        XCTAssertNil(model.choices["reading"])
        await model.redoLast()
        XCTAssertEqual(model.choices["reading"], text)
    }

    func testReturnDoesNothingOnSetOrWithNothingSelected() async {
        let model = await makeModel()
        model.screen = .set
        XCTAssertFalse(model.canUseSelected)
        model.screen = .display
        model.selectedFamily = nil
        XCTAssertFalse(model.canUseSelected)
        model.togglePreview()
        XCTAssertNil(model.preview, "nothing to preview")
    }

    // MARK: First launch safety

    func testClassifiesALibraryFromANewerBuild() {
        XCTAssertEqual(LibraryOpenProblem.classify(error: "database error: Invalid parameter name: newer-library:99:30", dbPath: "/tmp/x/fontdrop.db"), .newer)
    }

    func testClassifiesAReadOnlyLocation() throws {
        let dir = NSTemporaryDirectory() + "fontdrop-readonly-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir)
            try? FileManager.default.removeItem(atPath: dir)
        }
        let db = dir + "/lib/fontdrop.db"
        let problem = LibraryOpenProblem.classify(error: "database error: unable to open database file", dbPath: db)
        XCTAssertEqual(problem, .readOnly(folder: dir + "/lib"))
        XCTAssertTrue(problem.message.contains("read-only"))
        XCTAssertFalse(problem.message.contains("Optional"), problem.message)
    }

    func testAnUnknownErrorStillGetsPlainWordsAndTheFile() {
        let problem = LibraryOpenProblem.classify(error: "database error: something odd", dbPath: "/tmp/fontdrop.db")
        guard case .other(let file, let detail) = problem else { return XCTFail("\(problem)") }
        XCTAssertEqual(file, "/tmp/fontdrop.db")
        XCTAssertTrue(detail.contains("something odd"))
        XCTAssertTrue(problem.message.contains("/tmp/fontdrop.db"))
    }

    /// A DB stamped by a newer build is refused with a message, the model reports a failed phase, and the file is untouched.
    func testALibraryFromANewerBuildOpensAsAPlainMessageAndIsLeftAlone() async throws {
        let path = tempDB()
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE marker (x INTEGER); PRAGMA user_version = 999;", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--bench"], environment: [:]), defaults: suite())
        await model.bootstrap()
        guard case .failed(let message) = model.phase else { return XCTFail("a newer library must not open: \(model.phase)") }
        let problem = LibraryOpenProblem.classify(error: message, dbPath: path)
        XCTAssertEqual(problem, .newer)
        XCTAssertEqual(problem.title, "This library is from a newer FontDrop")

        var check: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(path, &check, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(check, "PRAGMA user_version", -1, &stmt, nil)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(stmt, 0), 999, "an older build never lowers the version")
        sqlite3_finalize(stmt); sqlite3_close(check)
    }

    func testAReadOnlyLibraryFolderOpensAsAPlainMessage() async throws {
        let dir = NSTemporaryDirectory() + "fontdrop-ro-lib-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir)
            try? FileManager.default.removeItem(atPath: dir)
        }
        let path = dir + "/fontdrop.db"
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--bench"], environment: [:]), defaults: suite())
        await model.bootstrap()
        guard case .failed(let message) = model.phase else { return XCTFail("a read-only folder cannot hold a library: \(model.phase)") }
        XCTAssertEqual(LibraryOpenProblem.classify(error: message, dbPath: path), .readOnly(folder: dir))
    }

    func testAMissingFontFolderIsAnEmptyLibraryNotACrash() async {
        let missing = NSTemporaryDirectory() + "fontdrop-no-such-folder-\(UUID().uuidString)"
        let options = LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--scan-folders", missing], environment: [:])
        let model = AppModel(options: options, defaults: suite())
        await model.bootstrap()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.rescanDone)
        XCTAssertEqual(model.scanState, .idle, "no folder is not a failed scan")
        XCTAssertTrue(model.families.isEmpty)
        XCTAssertTrue(model.libraryIsEmpty, "the screen says so, with a way to Font Book")
        XCTAssertNil(model.errorMessage)
    }

    func testAnEmptyLibraryOpensAndShowsTheEmptyState() async {
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--scan-folders", NSTemporaryDirectory() + "fontdrop-empty-\(UUID().uuidString)"], environment: [:]), defaults: suite())
        await model.bootstrap()
        XCTAssertTrue(model.libraryIsEmpty)
        XCTAssertTrue(model.hidesInspector)
        XCTAssertFalse(model.canFind)
    }

    // MARK: About

    func testAboutReadsTheBundleAndNamesTheCredits() {
        let facts = AboutPanel.bundleFacts()
        XCTAssertEqual(facts.name, "FontDrop")
        XCTAssertFalse(facts.version.isEmpty)
        XCTAssertFalse(facts.build.isEmpty)
        let credits = AboutPanel.credits().string
        for name in ["Doto", "Geist Mono", "SIL Open Font License", "Typewolf", "Practical Typography"] {
            XCTAssertTrue(credits.contains(name), "credits name \(name)")
        }
        XCTAssertFalse(credits.contains("\u{2014}"), "no em dash")
        let links = AboutPanel.credits().attributes(at: credits.range(of: "Typewolf").map { credits.distance(from: credits.startIndex, to: $0.lowerBound) } ?? 0, effectiveRange: nil)
        XCTAssertNotNil(links[.link])
    }

    func testTheAppIconIsOneReplaceableAsset() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile"),
                        "the bundle names an icon (AppIcon, from the asset catalog)")
    }

    // MARK: The command line

    func testStrayArgumentsAreNotFilesToOpen() {
        // The registration lives in memory only, and the real app sets the same value in main.swift.
        LaunchArguments.stopTreatingStrayArgumentsAsFiles()
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        XCTAssertEqual(registered[LaunchArguments.defaultsKey] as? Bool, false)
    }

    /// The real thing: start the built app with each developer flag, the way a screenshot run does (the flag is followed
    /// by another dash argument, which is what used to stall launch), and see it write its screenshot and quit.
    func testEachDeveloperFlagLaunchesTheApp() throws {
        let exe = try XCTUnwrap(Bundle.main.executablePath)
        let folder = NSTemporaryDirectory() + "fontdrop-flags-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let flags: [[String]] = [["--lock"], ["--inspector"], ["--compare"], ["--scan-folders", folder, "--bg-refresh"]]
        for flag in flags {
            let png = NSTemporaryDirectory() + "fontdrop-flag-\(UUID().uuidString).png"
            defer { try? FileManager.default.removeItem(atPath: png) }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = ["--db", tempDB(), "--screenshot", png, "--screen", "display"] + flag + ["--appearance", "dark", "-ApplePersistenceIgnoreState", "YES"]
            p.environment = ["HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]     // not a test host: a clean environment
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run()
            let deadline = Date().addingTimeInterval(60)
            while p.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
            if p.isRunning { p.terminate(); XCTFail("\(flag.joined(separator: " ")) stalled the launch") ; continue }
            XCTAssertEqual(p.terminationStatus, 0, "\(flag.joined(separator: " ")) exit status")
            XCTAssertTrue(FileManager.default.fileExists(atPath: png), "\(flag.joined(separator: " ")) wrote its screenshot")
        }
    }
}
