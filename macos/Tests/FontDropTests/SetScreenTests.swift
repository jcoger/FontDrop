import CoreText
import FontDropCore
import SQLite3
import XCTest
@testable import FontDrop

/// Round R5: the Set screen's numbers, the move of scale, colors and face settings into the database, and brand delete.
@MainActor
final class SetScreenTests: XCTestCase {
    private func tempDB() -> String { NSTemporaryDirectory() + "fontdrop-r5-\(UUID().uuidString).db" }

    // MARK: Measure and line height

    func testMeasureDefaultsToTheMiddleOfTheComfortableBand() {
        XCTAssertEqual(TextRules.defaultMeasure, 66)
        XCTAssertTrue(TextRules.isComfortable(TextRules.defaultMeasure))
        XCTAssertEqual(TextRules.measure(TypeScale()), 66)
        XCTAssertEqual(TextRules.measure(TypeScale(measure: 52)), 52, "the designer's value wins")
    }

    func testLineHeightFollowsTheMeasureTightToLooseAndRoundsToFiveHundredths() {
        XCTAssertEqual(TextRules.lineHeight(forMeasure: 45), 1.30, accuracy: 0.0001)
        XCTAssertEqual(TextRules.lineHeight(forMeasure: 75), 1.50, accuracy: 0.0001)
        XCTAssertEqual(TextRules.lineHeight(forMeasure: 30), 1.30, accuracy: 0.0001, "never tighter than the narrow end")
        XCTAssertEqual(TextRules.lineHeight(forMeasure: 90), 1.50, accuracy: 0.0001, "never looser than the wide end")
        XCTAssertEqual(TextRules.lineHeight(forMeasure: 66), 1.45, accuracy: 0.0001)
        var last = 0.0
        for m in stride(from: 35, through: 90, by: 1) {
            let lh = TextRules.lineHeight(forMeasure: m)
            XCTAssertGreaterThanOrEqual(lh, last, "a longer line is never set tighter")
            last = lh
        }
        // Tied to the measure until the designer sets a line height of their own.
        XCTAssertEqual(TextRules.lineHeight(TypeScale(measure: 45)), 1.30, accuracy: 0.0001)
        XCTAssertEqual(TextRules.lineHeight(TypeScale(measure: 45, lineHeight: 1.6)), 1.6, accuracy: 0.0001)
    }

    func testHeadingsAreSetTighterTheBiggerTheyGet() {
        let leads = ScaleStep.stageOrder.map { TextRules.headingLeading(step: $0.rawValue) }
        XCTAssertEqual(leads, leads.sorted(by: <), "stage order runs big to small, so leading runs tight to loose")
        XCTAssertLessThan(TextRules.headingLeading(step: ScaleStep.display.rawValue), TextRules.lineHeight(TypeScale()))
    }

    func testScaleStepsMatchBoardFour() {
        let sizes = SetSizes(body: 15, ratio: 1.333, measure: 66, lineHeight: 1.45)
        XCTAssertEqual(ScaleStep.stageOrder.map { Int(sizes.size($0).rounded()) }, [63, 47, 36, 27, 20, 15, 11])
        XCTAssertTrue(ScaleStep.h3.isDisplayFace)
        XCTAssertFalse(ScaleStep.lead.isDisplayFace)
    }

    func testStoreClampsMeasureAndLineHeight() {
        let store = ScaleStore(persist: false)
        store.update(brand: 1) { $0.measure = 500; $0.lineHeight = 9 }
        XCTAssertEqual(store.scale(brand: 1).measure, TextRules.measureRange.upperBound)
        XCTAssertEqual(store.scale(brand: 1).lineHeight, TextRules.lineHeightRange.upperBound)
        store.update(brand: 1) { $0.measure = nil; $0.lineHeight = nil }
        XCTAssertEqual(TextRules.measure(store.scale(brand: 1)), 66, "Back to Auto")
    }

    // MARK: No clipping

    /// At every window width the Set stage gets, no row's preview is wider than the room it is given, and the size
    /// printed in its label is still the true one.
    func testPreviewsFitTheirRoomAtEveryWindowWidth() throws {
        let path = "/System/Library/Fonts/SFNS.ttf"
        FontLoader.shared.load(path: path)
        let face = FaceSpec(path: path, settings: .defaults(job: "display"))
        let sizes = SetSizes(body: 15, ratio: 1.333, measure: 66, lineHeight: 1.45)
        // Stage widths for windows of 1000, 1360 and 1728 with the sidebar and inspector open, less the label column and padding.
        for spec in [180.0, 520.0, 900.0] {
            for step in ScaleStep.stageOrder {
                // A name far too long for the room, to prove the shrink never lets text spill.
                let text = step == .body ? SampleCopy.paragraphs.joined(separator: " ") : "Extraordinarily long headline for a very narrow stage"
                let plan = SetRowPlan.make(step: step, pt: sizes.size(step), face: face, text: text, specWidth: spec, sizes: sizes)
                XCTAssertLessThanOrEqual(plan.factor, 1)
                XCTAssertGreaterThan(plan.factor, 0)
                if step == .body {
                    XCTAssertLessThanOrEqual(try XCTUnwrap(plan.drawnWidth), spec + 0.5, "body column at \(spec)")
                } else if let font = FontLoader.shared.styledFont(face, ratio: CGFloat(plan.drawnPt / face.settings.size)) {
                    XCTAssertLessThanOrEqual(TextRules.lineWidth(text, font: font), spec, "\(step.label) at \(spec)")
                }
            }
        }
        XCTAssertEqual(TextRules.previewScale(width: 100, available: 400), 1, "a row that fits is not shrunk")
    }

    // MARK: The move into the database

    private let scaleJSON = #"{"1":{"body":17,"ratio":1.25,"locked":true},"0":{"body":12,"ratio":1.2,"locked":false}}"#
    private let colorsJSON = ##"{"1":{"background":"#101312","text":"#E8E8E4","accent":"#2B5C93"}}"##
    private let playJSON = #"{"1\/display\/Acme Serif":{"size":41.6,"axes":{"opsz":14,"STYL":30},"lineHeight":1.2,"tracking":0.015,"features":{"35.2":1},"stylePath":"\/F\/Heavy.otf","trim":1.1}}"#

    /// A DB with brand 1, and the three old JSON files next to it.
    private func legacyDB() throws -> (path: String, files: [String: Data]) {
        let path = tempDB()
        do {
            let lib = try Library.open(path: path)
            XCTAssertEqual(try lib.brandCreate(name: "Acme").id, 1)
        }
        // This DB was last opened by the build before R5: it has no import record, and the JSON files are beside it.
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "DELETE FROM meta WHERE key = 'brand_settings_json_import'", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        var files: [String: Data] = [:]
        for (suffix, body) in [("scale", scaleJSON), ("colors", colorsJSON), ("playground", playJSON)] {
            let data = Data(body.utf8)
            try data.write(to: URL(fileURLWithPath: path + ".\(suffix).json"))
            files[suffix] = data
        }
        return (path, files)
    }

    private func loadStores(_ lib: Library) -> (ScaleStore, TypeSettingsStore, BrandStyleStore) {
        let scale = ScaleStore(persist: true), faces = TypeSettingsStore(persist: true)
        let style = BrandStyleStore(persist: true, defaults: AppModel.throwawayDefaults())
        scale.attach(lib); faces.attach(lib); style.attach(lib)
        return (scale, faces, style)
    }

    func testFirstLaunchImportsTheJSONFilesAndLeavesThemAlone() throws {
        let (path, files) = try legacyDB()
        let lib = try Library.open(path: path)          // the first launch of this build
        let (scale, faces, style) = loadStores(lib)
        XCTAssertEqual(scale.scale(brand: 1).body, 17)
        XCTAssertEqual(scale.scale(brand: 1).ratio, 1.25)
        XCTAssertTrue(scale.scale(brand: 1).locked)
        XCTAssertEqual(style.palette(brand: 1).accent.hex, "#2B5C93")
        let s = faces.settings("1/display/Acme Serif", job: "display")
        XCTAssertEqual(s.stylePath, "/F/Heavy.otf")
        XCTAssertEqual(s.axes["opsz"], 14)
        XCTAssertEqual(s.axes["STYL"], 30)
        XCTAssertEqual(s.features["35.2"], 1)
        XCTAssertEqual(s.trim, 1.1, accuracy: 0.0001)
        XCTAssertEqual(s.size, 40, "size is the job's base size, never imported")
        XCTAssertEqual(try lib.scalesList().count, 1, "key 0 (no brand) has no row to hang on")
        for (suffix, data) in files {
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path + ".\(suffix).json")), data, "\(suffix).json untouched")
        }
    }

    /// A second launch reads the database only. A value changed after the import is still there, and the stale JSON
    /// does not come back over it.
    func testSecondLaunchReadsTheDatabaseAndNeverReimports() throws {
        let (path, files) = try legacyDB()
        let first = try Library.open(path: path)
        let (scale, faces, style) = loadStores(first)
        scale.update(brand: 1) { $0.body = 20; $0.measure = 58; $0.lineHeight = 1.4 }
        faces.update("1/display/Acme Serif", job: "display") { $0.axes["opsz"] = nil; $0.trim = 0.9 }
        style.setPalette(.night, brand: 1)
        scale.flush(); faces.flush(); style.flush()

        let second = try Library.open(path: path)
        let (scale2, faces2, style2) = loadStores(second)
        XCTAssertEqual(scale2.scale(brand: 1).body, 20, "the database, not the JSON's 17")
        XCTAssertEqual(scale2.scale(brand: 1).measure, 58)
        XCTAssertEqual(scale2.scale(brand: 1).lineHeight, 1.4)
        XCTAssertNil(faces2.settings("1/display/Acme Serif", job: "display").axes["opsz"], "Back to Auto survives a relaunch")
        XCTAssertEqual(faces2.settings("1/display/Acme Serif", job: "display").axes["STYL"], 30)
        XCTAssertEqual(faces2.settings("1/display/Acme Serif", job: "display").trim, 0.9, accuracy: 0.0001)
        XCTAssertEqual(style2.palette(brand: 1), .night)
        XCTAssertEqual(try second.scalesList().count, 1)
        XCTAssertEqual(try second.colorsList().count, 1)
        XCTAssertEqual(try second.facesList().count, 1)
        for (suffix, data) in files {
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path + ".\(suffix).json")), data, "\(suffix).json untouched")
        }
    }

    func testReturningColorsToPaperRemovesTheRow() throws {
        let lib = try Library.open(path: tempDB())
        let id = try lib.brandCreate(name: "Acme").id
        let style = BrandStyleStore(persist: true, defaults: AppModel.throwawayDefaults())
        style.attach(lib)
        style.setPalette(.bone, brand: id); style.flush()
        XCTAssertEqual(try lib.colorsList().count, 1)
        style.setPalette(.paper, brand: id); style.flush()
        XCTAssertTrue(try lib.colorsList().isEmpty)
    }

    // MARK: Brand delete

    private func makeModel() async -> AppModel {
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench"], environment: [:]))
        await model.bootstrap()
        return model
    }

    func testDeletingABrandRemovesEverythingSavedForItAndANewBrandStartsClean() async throws {
        let model = await makeModel()
        let keepMade = await model.createBrand("Keep")
        let keep = try XCTUnwrap(keepMade)
        let doomedMade = await model.createBrand("Doomed")
        let doomed = try XCTUnwrap(doomedMade)
        let lib = try XCTUnwrap(model.core)
        // Everything a brand can hold, written straight to the database and into the stores.
        try lib.scaleSet(scale: BrandScale(brandId: doomed, body: 18, ratio: 1.5, locked: true, measure: 60, lineHeight: 1.4))
        try lib.colorsSet(colors: BrandColors(brandId: doomed, background: "#101312", text: "#E8E8E4", accent: "#E5341D"))
        try lib.faceSet(face: FaceSettings(brandId: doomed, job: "display", family: "A", stylePath: nil, tracking: 0, lineHeight: 1.1, trim: 1, axesJson: "{}", featuresJson: "{}"))
        try lib.scaleSet(scale: BrandScale(brandId: keep, body: 16, ratio: 1.25, locked: false, measure: nil, lineHeight: nil))
        try lib.shortlistSet(brand: doomed, job: "reading", family: "Satoshi", on: true)
        try lib.choose(brand: doomed, job: "display", family: "A")
        model.scaleStore.attach(lib); model.typeSettings.attach(lib); model.brandStyle.attach(lib)
        XCTAssertEqual(model.scaleStore.scale(brand: doomed).body, 18)

        let brand = try XCTUnwrap(model.brands.first { $0.id == doomed })
        await model.deleteBrand(brand)

        XCTAssertEqual(model.brands.map(\.id), [keep])
        XCTAssertEqual(model.brandID, keep, "the next brand is selected")
        XCTAssertEqual(try lib.scalesList().map(\.brandId), [keep], "the other brand's scale stays")
        XCTAssertTrue(try lib.colorsList().isEmpty)
        XCTAssertTrue(try lib.facesList().isEmpty)
        XCTAssertTrue(try lib.shortlistGet(brand: doomed, job: "reading").isEmpty)
        XCTAssertTrue(try lib.choices(brand: doomed).isEmpty)
        XCTAssertEqual(model.scaleStore.scale(brand: doomed), TypeScale(), "memory forgot it too")
        XCTAssertEqual(model.brandStyle.palette(brand: doomed), .paper)
        XCTAssertNil(model.typeSettings.map.keys.first { TypeSettingsStore.split($0)?.0 == doomed })

        // Delete the last brand, then create another: it gets a new id and nothing of the old one.
        await model.deleteBrand(try XCTUnwrap(model.brands.first))
        XCTAssertNil(model.brandID)
        let freshMade = await model.createBrand("Fresh")
        let fresh = try XCTUnwrap(freshMade)
        XCTAssertGreaterThan(fresh, doomed, "an id is never reused")
        XCTAssertEqual(model.scaleStore.scale(brand: fresh), TypeScale())
        XCTAssertTrue(try lib.scalesList().isEmpty)
        XCTAssertTrue(model.choices.isEmpty && model.shortlists.values.allSatisfy(\.isEmpty))
    }
}
