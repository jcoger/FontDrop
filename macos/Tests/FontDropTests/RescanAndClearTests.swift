import FontDropCore
import XCTest
@testable import FontDrop

/// Two things the designer hit on a real launch: Reading stayed empty after the background rescan, and a chosen
/// face could not be taken off a job. Both run against a throwaway DB, never the live one.
@MainActor
final class RescanAndClearTests: XCTestCase {
    private func makeModel() async -> AppModel {
        let path = NSTemporaryDirectory() + "fontdrop-test-\(UUID().uuidString).db"
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--bench"], environment: [:]))
        await model.bootstrap()
        await model.createBrand("Test brand")
        return model
    }

    private func family(_ name: String, id: String) -> FamilySummary {
        FamilySummary(name: name, filePath: "/nonexistent/\(name).otf", fontId: id, styleCount: 1, skeleton: "geometric",
                      serif: false, isTrial: false, foundryUrl: nil, vendor: nil)
    }

    // MARK: Reading after a rescan

    /// The list was ranked against the old library. After a rescan on Reading it is ranked again.
    func testRescanOnReadingLoadsTheListAgain() async {
        let model = await makeModel()
        model.screen = .reading
        await model.loadCandidates()
        XCTAssertNil(model.candidatesError)
        let first = model.candidateLoadsStarted
        XCTAssertEqual(first, 1)
        await model.loadCandidates()
        XCTAssertEqual(model.candidateLoadsStarted, first, "same answer is cached")
        await model.applyRescan([family("Alpha", id: "a1")], [])
        XCTAssertEqual(model.candidateLoadsStarted, first + 1, "the rescan threw the cached list away and loaded again")
    }

    /// Off Reading the rescan only drops the list. Opening Reading loads it.
    func testRescanOffReadingLoadsOnNextVisit() async {
        let model = await makeModel()
        model.screen = .reading
        await model.loadCandidates()
        model.screen = .display
        await model.applyRescan([family("Alpha", id: "a1")], [])
        XCTAssertEqual(model.candidateLoadsStarted, 1)
        XCTAssertTrue(model.readingIsLoading, "no answer yet, so Reading shows its spinner, not an empty list")
        model.screen = .reading
        await model.loadCandidates()
        XCTAssertEqual(model.candidateLoadsStarted, 2)
        XCTAssertFalse(model.readingIsLoading)
    }

    /// A load that a reset overtakes must not leave the spinner on.
    func testSupersededLoadNeverLeavesTheSpinnerOn() async {
        let model = await makeModel()
        model.installLibrary([family("Alpha", id: "a1")], [])
        await model.choose("display", family: "Alpha")
        XCTAssertNotNil(model.displayFamily)
        async let load: Void = model.loadCandidates()
        await model.clear("display")        // resets the list while the load is in flight
        await load
        XCTAssertFalse(model.candidatesLoading)
    }

    /// An error ends the loading state too, and it is something Reading can show.
    func testFailedLoadShowsAnErrorNotAnEndlessSpinner() async {
        let model = await makeModel()
        model.installLibrary([family("Alpha", id: "a1")], [])
        await model.choose("display", family: "Alpha")      // "a1" is not in the DB, so the core cannot rank partners
        await model.loadCandidates()
        XCTAssertFalse(model.candidatesLoading)
        XCTAssertFalse(model.readingIsLoading)
        XCTAssertTrue(model.candidatesError != nil || model.candidatesKey_forTests != nil)
    }

    func testReadingIsLoadingBeforeTheFirstAnswer() async {
        let model = await makeModel()
        XCTAssertTrue(model.readingIsLoading, "before any load, never a blank")
    }

    func testSelectionFollowsTheFamilyWhenIdsChange() {
        let list = [(id: "new-1", family: "Alpha"), (id: "new-2", family: "Beta")]
        XCTAssertEqual(CandidateSelection.pick(list, current: "old-2", keeping: "Beta", preferred: nil, first: "new-1"), "new-2")
        XCTAssertEqual(CandidateSelection.pick(list, current: "new-1", keeping: nil, preferred: nil, first: "new-2"), "new-1")
        XCTAssertEqual(CandidateSelection.pick(list, current: "gone", keeping: "Gone", preferred: nil, first: "new-1"), "new-1")
        XCTAssertEqual(CandidateSelection.pick(list, current: nil, keeping: nil, preferred: "new-2", first: "new-1"), "new-2")
        XCTAssertNil(CandidateSelection.pick([], current: "x", keeping: "X", preferred: nil, first: nil))
    }

    /// A rescan replaces the family list. Choices and the shortlist are keyed by name and carry over.
    func testChoicesAndShortlistSurviveARescan() async {
        let model = await makeModel()
        model.installLibrary([family("Alpha", id: "a1"), family("Beta", id: "b1")], [])
        await model.choose("display", family: "Alpha")
        await model.setShortlist("reading", family: "Beta", on: true)
        await model.applyRescan([family("Alpha", id: "a2"), family("Beta", id: "b2")], [])
        XCTAssertEqual(model.choices["display"], "Alpha")
        XCTAssertEqual(model.displayFamily?.fontId, "a2", "the family resolves to its new file")
        XCTAssertEqual(model.shortlist("reading"), ["Beta"])
    }

    // MARK: Failed fonts

    func testFailedFontLoadsAreRetriedAfterARescan() async {
        let path = "/nonexistent/\(UUID().uuidString).otf"
        FontLoader.shared.load(path: path)
        guard case .failure? = FontLoader.shared.cached(path) else { return XCTFail("expected a cached failure") }
        await FontLoader.shared.preload(paths: [path])
        XCTAssertNotNil(FontLoader.shared.cached(path), "preload skips what is cached, failures included")
        FontLoader.shared.forgetFailures()
        XCTAssertNil(FontLoader.shared.cached(path), "the failure is forgotten, so the next preload tries again")
    }

    // MARK: Clear a face

    func testClearDisplayTakesTheFaceOffAndUndoPutsItBack() async {
        let model = await makeModel()
        model.installLibrary([family("Alpha", id: "a1")], [])
        await model.choose("display", family: "Alpha")
        XCTAssertTrue(model.canClear("display"))
        await model.clear("display")
        XCTAssertNil(model.choices["display"])
        XCTAssertNil(model.chosen(.display))
        XCTAssertNil(model.displayFamily)
        XCTAssertFalse(model.canClear("display"))
        XCTAssertTrue(model.canUndo("display"))
        await model.undo("display")
        XCTAssertEqual(model.choices["display"], "Alpha")
        XCTAssertNotNil(model.displayFamily)
    }

    func testClearPersistsInTheCore() async {
        let model = await makeModel()
        await model.choose("reading", family: "Beta")
        await model.clear("reading")
        guard let id = model.brandID, let core = model.core else { return XCTFail("no brand") }
        let rows = (try? core.choices(brand: id)) ?? []
        XCTAssertFalse(rows.contains { $0.job == "reading" }, "choice_clear removed the row")
    }

    func testClearReadingKeepsDisplayAndTheShortlist() async {
        let model = await makeModel()
        await model.choose("display", family: "Alpha")
        await model.choose("reading", family: "Beta")
        await model.setShortlist("reading", family: "Beta", on: true)
        await model.clear("reading")
        XCTAssertEqual(model.choices["display"], "Alpha")
        XCTAssertNil(model.choices["reading"])
        XCTAssertEqual(model.shortlist("reading"), ["Beta"])
    }

    /// With the Display face cleared, Reading goes to "on its own": no pairing questions, no reasons.
    func testClearingDisplayPutsReadingOnItsOwn() async {
        let model = await makeModel()
        model.installLibrary([family("Alpha", id: "a1")], [])
        await model.choose("display", family: "Alpha")
        model.lenses.contrast = .strong
        model.lenses.foundry = .sameOnly
        XCTAssertEqual(model.effectiveLenses.contrast, .strong)
        await model.clear("display")
        XCTAssertEqual(model.effectiveLenses.contrast, .any)
        XCTAssertEqual(model.effectiveLenses.foundry, .any)
        XCTAssertNotNil(model.pairContext(reading: "Alpha", fallbackPath: "/nonexistent/Alpha.otf"), "the stage still draws")
    }

    func testClearWithNothingChosenDoesNothing() async {
        let model = await makeModel()
        await model.clear("display")
        XCTAssertFalse(model.canUndo("display"))
        XCTAssertNil(model.errorMessage)
    }

    func testLexiconClearStrings() {
        XCTAssertEqual(Lexicon.clearFace("display"), "Clear Display face")
        XCTAssertEqual(Lexicon.clearFace("reading"), "Clear Reading face")
        XCTAssertFalse(Lexicon.clearFace("display").contains("\u{2014}"))
    }
}
