import CoreText
import FontDropCore
import SQLite3
import XCTest
@testable import FontDrop

/// Wave 5a: the Reading list and stage rules, the style names, and the no-mid-word rule.
@MainActor
final class ReadingStageTests: XCTestCase {
    private func ev(_ lens: String, _ detail: String = "", effect: Int8 = 1) -> Evidence {
        Evidence(lens: lens, detail: detail, source: "STO", strength: "shortcut", effect: effect)
    }

    private func cand(_ id: String, _ family: String, pairType: String = "contrast", evidence: [Evidence] = [], order: Int = 0) -> Candidate {
        Candidate(id: id, family: family, pairType: pairType, evidence: evidence, order: order)
    }

    // MARK: Keyboard selection

    func testArrowsMoveTheSelectionAndStopAtTheEnds() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(ListNav.move(ids, from: "a", by: 1), "b")
        XCTAssertEqual(ListNav.move(ids, from: "b", by: -1), "a")
        XCTAssertEqual(ListNav.move(ids, from: "a", by: -1), "a", "stops at the top")
        XCTAssertEqual(ListNav.move(ids, from: "c", by: 1), "c", "stops at the bottom")
        XCTAssertEqual(ListNav.move(ids, from: nil, by: 1), "a", "nothing selected: the first row")
        XCTAssertEqual(ListNav.move(ids, from: "gone", by: -1), "a")
        XCTAssertNil(ListNav.move([], from: nil, by: 1))
    }

    // MARK: Zoom

    func testZoomStaysInItsBoundsAndFitResets() {
        var z = StageZoom()
        XCTAssertTrue(z.isFit)
        XCTAssertEqual(z.label, "Fit")
        for _ in 0..<30 { z.zoomIn() }
        XCTAssertEqual(z.factor, StageZoom.range.upperBound, accuracy: 0.0001)
        XCTAssertFalse(z.canZoomIn)
        XCTAssertEqual(z.label, "400%")
        for _ in 0..<30 { z.zoomOut() }
        XCTAssertEqual(z.factor, StageZoom.range.lowerBound, accuracy: 0.0001)
        XCTAssertFalse(z.canZoomOut)
        z.fit()
        XCTAssertTrue(z.isFit)
        z.zoomIn()
        XCTAssertGreaterThan(z.factor, 1)
        XCTAssertEqual(StageZoom.clamp(99), 4)
        XCTAssertEqual(StageZoom.clamp(0), 0.5)
    }

    // MARK: Compare

    func testCompareNeedsTwoAndShowsAtMostThreeWithTheSelectedFirst() {
        XCTAssertFalse(Compare.isAvailable(shortlistCount: 1))
        XCTAssertTrue(Compare.isAvailable(shortlistCount: 2))
        XCTAssertEqual(Compare.families(shortlist: ["A", "B"], selected: nil), ["A", "B"])
        XCTAssertEqual(Compare.families(shortlist: ["A", "B", "C", "D"], selected: nil), ["A", "B", "C"])
        XCTAssertEqual(Compare.families(shortlist: ["A", "B", "C", "D"], selected: "C"), ["C", "A", "B"])
        XCTAssertEqual(Compare.families(shortlist: ["A", "B", "C"], selected: "Z"), ["A", "B", "C"], "not on the shortlist: unchanged")
    }

    func testCompareModeOnlyCountsWithTwoShortlisted() async throws {
        let model = try await makeModel()
        await model.createBrand("Test brand")
        model.compareMode = true
        XCTAssertTrue(model.comparedFamilies.isEmpty)
        await model.setShortlist("reading", family: "Acme Text", on: true)
        XCTAssertTrue(model.comparedFamilies.isEmpty, "one is not a comparison")
        await model.setShortlist("reading", family: "Acme Sans", on: true)
        XCTAssertEqual(Set(model.comparedFamilies), ["Acme Text", "Acme Sans"])
        await model.setShortlist("reading", family: "Acme Sans", on: false)
        XCTAssertTrue(model.comparedFamilies.isEmpty, "back under two: Compare ends by itself")
    }

    // MARK: The list's rows and reasons

    func testCurrentFacePinsToTheTopWithoutADuplicate() {
        let a = cand("1", "Alpha"), b = cand("2", "Beta"), c = cand("3", "Gamma")
        XCTAssertEqual(ReadingRows.rows(current: b, shown: [a, c], search: "").map(\.family), ["Beta", "Alpha", "Gamma"])
        XCTAssertEqual(ReadingRows.rows(current: b, shown: [a, b, c], search: "").map(\.family), ["Beta", "Alpha", "Gamma"], "not listed twice")
        XCTAssertEqual(ReadingRows.rows(current: nil, shown: [a], search: "").map(\.family), ["Alpha"])
        XCTAssertEqual(ReadingRows.rows(current: b, shown: [a], search: "alp").map(\.family), ["Alpha"], "a search that misses it leaves it out")
    }

    func testRowsShowAtMostTwoReasonsInLexiconWords() {
        let c = cand("1", "Alpha", evidence: [ev("Clear contrast", "serif + sans"), ev("x-height", "within 4%"), ev("Foundry", "Acme Type")])
        let reasons = ReadingRows.reasons(c, xHeightNote: "Same x-height")
        XCTAssertEqual(reasons, ["Serif with sans", "Same x-height"])
        XCTAssertEqual(ReadingRows.reasons(c, xHeightNote: nil, limit: 3).count, 3)
    }

    func testDesignerNameIsNotAlsoShownAsFoundry() {
        let both = cand("1", "Alpha", pairType: "uniform", evidence: [ev("Foundry", "A. Designer"), ev("Designer", "A. Designer")])
        XCTAssertEqual(ReadingRows.reasons(both, xHeightNote: nil), ["Same designer"])
        let real = cand("2", "Beta", pairType: "uniform", evidence: [ev("Foundry", "Acme Type"), ev("Designer", "A. Designer")])
        XCTAssertEqual(ReadingRows.reasons(real, xHeightNote: nil), ["Same foundry", "Same designer"], "a real foundry match stays")
    }

    func testNoEvidenceMeansNoReasons() {
        XCTAssertTrue(ReadingRows.reasons(cand("1", "Alpha", pairType: ""), xHeightNote: nil).isEmpty)
    }

    func testDifferenceLensSaysDistinctNotClear() {
        XCTAssertEqual(ContrastLens.allCases.map(\.rawValue), ["Close", "Distinct", "Strong", "Any"])
        XCTAssertEqual(Lenses().contrast, .distinct)
    }

    func testSourceScopeMapsTheDisplayFilter() {
        XCTAssertEqual(SourceScope([.yours]), .yours)
        XCTAssertEqual(SourceScope([.yours, .google]), .yoursAndGoogle)
        XCTAssertEqual(SourceScope([.yours, .google, .system]), .all)
        XCTAssertEqual(SourceScope([.google]), .custom)
        XCTAssertEqual(SourceScope.yoursAndGoogle.sources, [.yours, .google])
    }

    func testInspectorRuleFollowsTheWindowWidth() {
        XCTAssertFalse(ReadingLayout.inspectorFits(windowWidth: 1000))
        XCTAssertTrue(ReadingLayout.inspectorFits(windowWidth: 1360))
        XCTAssertTrue(ReadingLayout.inspectorFits(windowWidth: 1728))
        XCTAssertEqual(ReadingLayout.listWidth(for: 1000), 320)
        XCTAssertLessThan(ReadingLayout.listWidth(for: 500), 320)
        XCTAssertGreaterThanOrEqual(ReadingLayout.listWidth(for: 300), 220)
    }

    // MARK: Style names (B3, B4)

    private func file(_ path: String, weight: UInt16 = 400, style: String = "") -> FontFile {
        FontFile(fontId: path, family: "Fam", name: "", filePath: path, weight: weight, styleName: style)
    }

    func testStyleNameComesFromTheFontsOwnNameTable() {
        XCTAssertEqual(StyleNames.label(file("/x/GrandHeavy.otf", style: "Grand Heavy"), family: "Grand"), "Grand Heavy")
    }

    func testStyleNameFallsBackToACleanedFileName() {
        XCTAssertEqual(StyleNames.fallback(path: "/x/GrandHeavy.otf", family: "Agrandir", weight: 800), "Grand Heavy")
        XCTAssertEqual(StyleNames.fallback(path: "/x/ABCReproMono-Regular.otf", family: "ABC Repro Mono", weight: 400), "Regular")
        XCTAssertEqual(StyleNames.fallback(path: "/x/TimelessSerif-TextThin.otf", family: "Timeless Serif", weight: 100), "Text Thin")
        XCTAssertEqual(StyleNames.fallback(path: "/x/psz].ttf", family: "Whatever", weight: 700), "Bold", "junk file name: the weight word")
        XCTAssertEqual(StyleNames.fallback(path: "/x/Fam.otf", family: "Fam", weight: 400), "Regular")
    }

    func testStyleListsGoLightToHeavyUprightBeforeItalicThenByName() {
        let list = [
            file("/x/b.otf", weight: 700, style: "Bold"),
            file("/x/ri.otf", weight: 400, style: "Italic"),
            file("/x/r.otf", weight: 400, style: "Regular"),
            file("/x/ul.otf", weight: 250, style: "UltraLight"),
            file("/x/t.otf", weight: 250, style: "Thin"),
        ]
        XCTAssertEqual(StyleNames.sorted(list, family: "Fam").map { $0.styleName },
                       ["Thin", "UltraLight", "Regular", "Italic", "Bold"])
    }

    func testPickerNeverShowsBlank() {
        let list = [file("/x/Fam-Light.otf", weight: 300, style: "Light"), file("/x/Fam-Bold.otf", weight: 700, style: "Bold")]
        XCTAssertEqual(StyleNames.nearest(to: "/x/Fam-Bold.otf", in: list, family: "Fam", weight: 700)?.styleName, "Bold", "listed: itself")
        XCTAssertEqual(StyleNames.nearest(to: "/y/fam-light.ttf", in: list, family: "Fam", weight: nil)?.styleName, "Light", "same name, other format")
        XCTAssertEqual(StyleNames.nearest(to: "/z/Other.otf", in: list, family: "Fam", weight: 650)?.styleName, "Bold", "nearest weight")
        XCTAssertEqual(StyleNames.nearest(to: "/z/Other.otf", in: list, family: "Fam", weight: nil)?.styleName, "Light", "default 400 is nearer 300")
        XCTAssertNil(StyleNames.nearest(to: "/z/Other.otf", in: [], family: "Fam", weight: nil))
    }

    // MARK: No mid-word breaks (B2)

    /// Sizes 14 to 120 on the Display playground, every headline the templates set in a column.
    func testNoWordIsBrokenAtAnyDisplaySizeOrColumnWidth() throws {
        let path = "/System/Library/Fonts/SFNS.ttf"
        guard case .success(let loaded) = FontLoader.shared.load(path: path) else { return XCTFail("could not load SFNS") }
        let headlines: [(String, CGFloat, CGFloat)] = [   // text, board size in px, column width in px
            (TemplateCopy.essayHeadline, 44, 472), (TemplateCopy.essayStandfirst, 20, 472),
            (TemplateCopy.featureHeadline, 76, 520), (TemplateCopy.statementHeadline, 88, 520),
            (TemplateCopy.productHeadline, 64, 520), (TemplateCopy.eventLine, 30, 420),
            (TemplateCopy.readoutLine, 72, 552), (TemplateCopy.detailTitle, 34, 300),
            (TemplateCopy.featureClosing, 18, 246),
        ]
        for size in stride(from: 14.0, through: 120.0, by: 2) {
            for (text, px, width) in headlines {
                var s = TypeSettings.defaults(job: "display")
                s.size = size
                let base = s.font(from: loaded, axisInfo: [], ratio: px / 40)
                let scale = FitWords.scale(text: text, font: base, trackingEm: -0.02, width: width, leading: 1.0, maxHeight: nil)
                let font = scale < 0.999 ? CTFontCreateCopyWithAttributes(base, CTFontGetSize(base) * scale, nil, nil) : base
                let lines = TightLines.lines(text, font: font, tracking: CGFloat(-0.02) * CTFontGetSize(font), width: width)
                let words = text.split(separator: " ").map(String.init)
                XCTAssertEqual(lines.joined(separator: " ").split(separator: " ").map(String.init), words,
                               "a word was split: \"\(text)\" at size \(size)")
                if scale > FitWords.floor + 0.01 {
                    XCTAssertLessThanOrEqual(FitWords.widestWord(text, font: font, trackingEm: -0.02), width + 0.5)
                }
            }
        }
    }

    func testHeightLimitShrinksAHeadlineUntilItFits() throws {
        let path = "/System/Library/Fonts/SFNS.ttf"
        guard case .success(let loaded) = FontLoader.shared.load(path: path) else { return XCTFail("could not load SFNS") }
        var s = TypeSettings.defaults(job: "display")
        s.size = 120
        let base = s.font(from: loaded, axisInfo: [], ratio: 88 / 40)
        let free = FitWords.scale(text: TemplateCopy.statementHeadline, font: base, trackingEm: -0.04, width: 520, leading: 0.91, maxHeight: nil)
        let limited = FitWords.scale(text: TemplateCopy.statementHeadline, font: base, trackingEm: -0.04, width: 520, leading: 0.91, maxHeight: 380)
        XCTAssertLessThan(limited, free)
        XCTAssertGreaterThanOrEqual(limited, FitWords.floor)
    }

    // MARK: The app against a throwaway DB (Reading before a Display face)

    private func makeModel() async throws -> AppModel {
        let path = NSTemporaryDirectory() + "fontdrop-reading-\(UUID().uuidString).db"
        _ = try Library.open(path: path)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        // "Acme Text" ships regular, italic, bold and bold italic: fit for long text. "Acme Sans" has one file: not fit.
        let rows: [(String, String, String, Int)] = [
            ("t0", "Acme Text", "Text-Regular.otf", 400), ("t1", "Acme Text", "Text-Italic.otf", 400),
            ("t2", "Acme Text", "Text-Bold.otf", 700), ("t3", "Acme Text", "Text-BoldItalic.otf", 700),
            ("s0", "Acme Sans", "Sans-Regular.otf", 400),
        ]
        for (id, family, file, weight) in rows {
            let sql = """
            INSERT INTO fonts (font_id, name, file_path, file_name, source, font_family, weight, created_at, updated_at)
            VALUES ('\(id)', '\(family)', '/System/Library/Fonts/SFNS.ttf', '\(file)', 'user', '\(family)', \(weight), 'x', 'x')
            """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--bench"], environment: [:]))
        await model.bootstrap()
        return model
    }

    func testReadingWorksBeforeAnyDisplayFace() async throws {
        let model = try await makeModel()
        await model.createBrand("Test brand")
        XCTAssertNil(model.displayFamily)
        await model.loadCandidates()
        XCTAssertNil(model.candidatesError)
        let shown = model.readingResult.shown
        XCTAssertFalse(shown.isEmpty, "the list is not empty without a Display face")
        XCTAssertEqual(shown.map(\.family), ["Acme Text"], "faces fit for long text only")
        XCTAssertEqual(model.notForLongText, 1, "the one-file family is counted, with Show them to add it")
        XCTAssertTrue(shown.allSatisfy { $0.evidence.isEmpty }, "nothing to pair against")
        XCTAssertTrue(ReadingRows.reasons(shown[0], xHeightNote: nil).isEmpty, "no reasons")
        XCTAssertEqual(model.effectiveLenses.sort, .name, "sorted by name until there is something to rank against")

        await model.setIncludeUnfit(true)
        XCTAssertEqual(Set(model.readingResult.shown.map(\.family)), ["Acme Text", "Acme Sans"], "Show them adds the rest")

        // Use for Reading works, and the stage can draw the face on its own.
        let pick = try XCTUnwrap(shown.first)
        model.selectedCandidate = pick.id
        await model.choose("reading", family: pick.family)
        XCTAssertEqual(model.choices["reading"], "Acme Text")
        XCTAssertEqual(model.currentReadingCandidate?.family, "Acme Text")
        let ctx = try XCTUnwrap(model.pairContext(reading: "Acme Text"))
        XCTAssertEqual(ctx.display.path, ctx.body.path, "the candidate sets the headline too")
    }
}
