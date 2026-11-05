import FontDropCore
import XCTest
@testable import FontDrop

/// Either way in (R3): a Text face first, then the Display grid ranked against it. And D7: a plain sans passes
/// Difference: Distinct under a sans Display face with character.
@MainActor
final class EitherWayInTests: XCTestCase {
    // MARK: D7 in the lenses

    private func candidate(_ family: String, _ pairType: String, evidence: [Evidence] = []) -> Candidate {
        Candidate(id: family, family: family, pairType: pairType, evidence: evidence, order: 0)
    }

    private func plainEvidence() -> [Evidence] {
        [Evidence(lens: "Plain text face", detail: "a dependable text face under a headline with character",
                  source: "", strength: "shortcut", effect: 1)]
    }

    func testAPlainPairPassesDistinctButNotCloseOrStrong() {
        let plain = candidate("General Sans", "plain", evidence: plainEvidence())
        var l = Lenses()
        l.contrast = .distinct
        XCTAssertTrue(LensEngine.passes(plain, l), "a plain sans is a clear difference under a sans with character")
        l.contrast = .close
        XCTAssertFalse(LensEngine.passes(plain, l))
        l.contrast = .strong
        XCTAssertFalse(LensEngine.passes(plain, l), "same form, so it is not the far end")
        l.contrast = .any
        XCTAssertTrue(LensEngine.passes(plain, l))
    }

    func testStructureMixedKeepsAPlainPairThatCrossesHands() {
        let plain = candidate("Satoshi", "plain", evidence: plainEvidence())
        var l = Lenses()
        l.contrast = .any
        l.structure = .mixed
        XCTAssertTrue(LensEngine.passes(plain, l), "no shared skeleton, so the hands are crossed")
        l.structure = .same
        XCTAssertFalse(LensEngine.passes(plain, l))
    }

    func testAPlainPairSaysClearDifferenceAndWhy() {
        XCTAssertEqual(Lexicon.pairGroup("plain"), "Clear difference")
        let e = plainEvidence()[0]
        XCTAssertEqual(Lexicon.chip(e), "Plain text face")
        XCTAssertEqual(Lexicon.whyTitle(e), "Clear difference")
        XCTAssertEqual(Lexicon.whyDetail(e), Lexicon.Pairs.plainWhy)
        XCTAssertNotNil(Lexicon.term(forLens: "Plain text face"))
    }

    // MARK: Words

    func testTheReasonLineIsRoleWordedAndHasNoEmDash() {
        XCTAssertEqual(Lexicon.Pairs.reason(pairType: "contrast", text: "Timeless Sans"), "Clear contrast with Timeless Sans")
        XCTAssertEqual(Lexicon.Pairs.reason(pairType: "plain", text: "Timeless Sans"), "Character over plain Timeless Sans")
        XCTAssertEqual(Lexicon.Pairs.reason(pairType: "uniform", text: "Timeless Sans"), "Harmony with Timeless Sans")
        XCTAssertNil(Lexicon.Pairs.reason(pairType: "same_family", text: "Timeless Sans"))
        let all = ["contrast", "plain", "uniform", "superfamily", "middle", "uncertain"].compactMap { Lexicon.Pairs.reason(pairType: $0, text: "X") }
            + [Lexicon.Pairs.sortLibrary, Lexicon.Pairs.sortPairsWith("X"), Lexicon.Pairs.sortHelp, Lexicon.Pairs.plainChip,
               Lexicon.Pairs.plainWhy, Lexicon.Pairs.subtitle(brand: "B", count: 3, text: "X")]
        for s in all {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), s)
        }
    }

    // MARK: The card line says what sets the pair apart

    private func ev(_ lens: String, _ detail: String, strength: String = "guideline", effect: Int8 = 1) -> Evidence {
        Evidence(lens: lens, detail: detail, source: "", strength: strength, effect: effect)
    }

    func testEachCardShowsTheEvidenceFewOthersShare() {
        // Four cards: all contrast, all x-height within 2%; only one shares the foundry, one has a rarer skeleton.
        let common = [ev("Clear contrast", "serif + sans"), ev("x-height", "within 2%")]
        let entries = [
            DisplayReasons.Entry(family: "A", pairType: "contrast", evidence: common + [ev("Foundry", "Acme Foundry", strength: "shortcut")]),
            DisplayReasons.Entry(family: "B", pairType: "contrast", evidence: common + [ev("Skeleton", "both rational")]),
            DisplayReasons.Entry(family: "C", pairType: "contrast", evidence: common),
            DisplayReasons.Entry(family: "D", pairType: "contrast", evidence: common),
        ]
        let lines = DisplayReasons.lines(entries, text: "Timeless Sans")
        XCTAssertEqual(lines["A"], "Same foundry as Timeless Sans")
        XCTAssertEqual(lines["B"], "Rational, like Timeless Sans")
        XCTAssertEqual(lines["C"], "Clear contrast with Timeless Sans", "everything it has is common: the pair type's line")
        XCTAssertEqual(lines["D"], lines["C"])
        XCTAssertNotEqual(lines["A"], lines["B"])
    }

    func testAWarningIsNeverTheLineOfAHelpingReason() {
        let e = [DisplayReasons.Entry(family: "A", pairType: "middle", evidence: [ev("The middle", "x", effect: -1)])]
        XCTAssertEqual(DisplayReasons.lines(e, text: "T")["A"], "Too close to T")
    }

    // MARK: The Display grid, end to end

    private func fixtureFolder() throws -> String {
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial", "Georgia", "Verdana"].flatMap { f in ["", " Bold", " Italic", " Bold Italic"].map { "\(f)\($0).ttf" } }
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") { throw XCTSkip("no system \(f)") }
        let dir = NSTemporaryDirectory() + "fontdrop-eitherway-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(dir)/\(f)") }
        return dir
    }

    private func makeModel(folder: String) async -> AppModel {
        let path = NSTemporaryDirectory() + "fontdrop-eitherway-\(UUID().uuidString).db"
        let defaults = UserDefaults(suiteName: "fontdrop-eitherway-\(UUID().uuidString)")!
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--scan-folders", folder], environment: [:]), defaults: defaults)
        await model.bootstrap()
        await model.createBrand("Test brand")
        return model
    }

    func testATextFaceFirstRanksTheDisplayGridAgainstIt() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = await makeModel(folder: dir)
        XCTAssertEqual(model.displaySort, .library, "no Text face: nothing to pair against")
        XCTAssertNil(model.displayReason(for: "Arial"))

        await model.choose("reading", family: "Georgia")
        XCTAssertEqual(model.displaySort, .pairsWith, "a Text face and no Display face: Pairs with is the default")
        await model.loadDisplayPairs()
        XCTAssertTrue(model.displayPairsAreCurrent)
        XCTAssertNotNil(model.displayReason(for: "Arial"), "a sans headline over a serif Text face has a line")
        XCTAssertTrue(model.displayReason(for: "Arial")?.contains("Georgia") ?? false, "in the Text face's name")
        XCTAssertNil(model.displayReason(for: "Georgia"), "the Text face has no partner line for itself")
        let order = model.displayGridFamilies.map(\.name)
        XCTAssertEqual(order.last, "Georgia", "the Text face's own family has no rank and follows the ranked ones: \(order)")
    }

    func testChoosingADisplayFaceKeepsTheLibraryOrderUnlessAsked() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = await makeModel(folder: dir)
        await model.choose("reading", family: "Georgia")
        await model.choose("display", family: "Arial")
        XCTAssertEqual(model.displaySort, .library, "both faces chosen: the designer asks for Pairs with")
        model.displaySortChoice = .pairsWith
        XCTAssertEqual(model.displaySort, .pairsWith)
        await model.loadDisplayPairs()
        XCTAssertNotNil(model.displayReason(for: "Verdana"))
        await model.clear("reading")
        XCTAssertEqual(model.displaySort, .library, "no Text face: the sort has nothing to rank against, whatever was picked")
        XCTAssertNil(model.displayReason(for: "Verdana"))
    }

    func testChangingTheTextFaceDropsTheOldRanksUntilTheNewOnesArrive() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = await makeModel(folder: dir)
        await model.choose("reading", family: "Georgia")
        await model.loadDisplayPairs()
        XCTAssertTrue(model.displayPairsAreCurrent)
        await model.choose("reading", family: "Arial")
        XCTAssertFalse(model.displayPairsAreCurrent, "ranks are for Georgia, not Arial")
        XCTAssertNil(model.displayReason(for: "Verdana"), "no stale line in the new Text face's name")
        XCTAssertTrue(model.displayPairsLoading)
        await model.loadDisplayPairs()
        XCTAssertTrue(model.displayPairsAreCurrent)
        XCTAssertFalse(model.displayPairsLoading)
    }
}
