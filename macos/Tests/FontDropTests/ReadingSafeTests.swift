import FontDropCore
import XCTest
@testable import FontDrop

/// Reading puts dependable text faces first. The core orders the two groups; the app keeps that order for Best match
/// and for "More character first", and reloads when the sort flips.
final class ReadingSafeTests: XCTestCase {
    private func cand(_ id: String, order: Int, workhorse: Bool) -> Candidate {
        Candidate(id: id, family: id, pairType: "contrast", evidence: [], order: order, workhorse: workhorse)
    }

    func testBestMatchAndMoreCharacterKeepTheCoresOrder() {
        // The core already put the workhorses first: a, b are workhorses; c, d are not.
        let list = [cand("a", order: 0, workhorse: true), cand("b", order: 1, workhorse: true),
                    cand("c", order: 2, workhorse: false), cand("d", order: 3, workhorse: false)]
        var l = Lenses()
        l.contrast = .any
        l.sort = .bestMatch
        XCTAssertEqual(LensEngine.apply(list, lenses: l).shown.map(\.id), ["a", "b", "c", "d"])
        // Flipped by the core: c, d first. The app does not re-sort them.
        let flipped = [cand("c", order: 0, workhorse: false), cand("d", order: 1, workhorse: false),
                       cand("a", order: 2, workhorse: true), cand("b", order: 3, workhorse: true)]
        l.sort = .characterFirst
        XCTAssertEqual(LensEngine.apply(flipped, lenses: l).shown.map(\.id), ["c", "d", "a", "b"])
    }

    func testTheNewSortHasItsWordsFromTheLexicon() {
        XCTAssertEqual(ReadingSort.characterFirst.rawValue, Lexicon.Finder.moreCharacter)
        XCTAssertEqual(Lexicon.Finder.moreCharacter, "More character first")
        for s in [Lexicon.Finder.moreCharacter, Lexicon.Finder.moreCharacterHelp] {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), s)
        }
        XCTAssertTrue(ReadingSort.allCases.contains(.characterFirst))
        XCTAssertFalse(ReadingSort.withoutDisplay.contains(.characterFirst), "nothing to rank against before a Display face")
    }

    func testTheRecommendedForTextRowReadsLikeTheOtherEvidence() {
        let e = Evidence(lens: "Recommended for text", detail: "2 sources", source: "TYW; BPT", strength: "guideline", effect: 1)
        XCTAssertEqual(Lexicon.chip(e), "Recommended for text \u{00B7} 2 sources")
        XCTAssertEqual(Lexicon.whyTitle(e), "Type guides")
        XCTAssertEqual(Lexicon.whyDetail(e), "Recommended for text \u{00B7} 2 sources")
        XCTAssertEqual(Lexicon.sources(e.source), "Typewolf, Butterick's Practical Typography")
        XCTAssertEqual(Lexicon.strength(e.strength), "Common advice")
        XCTAssertEqual(Lexicon.recommendedBy("Typewolf"), "Recommended for body text by Typewolf")
        for s in [Lexicon.chip(e), Lexicon.whyTitle(e), Lexicon.recommendedBy("Typewolf")] {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), s)
        }
    }

    /// The list keeps the vibe: the recommendation shows on the card only.
    func testTheRecommendationIsNotAListRowReason() {
        let rec = Evidence(lens: "Recommended for text", detail: "1 source", source: "TYW", strength: "shortcut", effect: 1)
        let xh = Evidence(lens: "x-height", detail: "within 2%", source: "LAT", strength: "guideline", effect: 1)
        let c = Candidate(id: "a", family: "A", pairType: "contrast", evidence: [rec, xh], order: 0, workhorse: true)
        let reasons = ReadingRows.reasons(c, xHeightNote: nil)
        XCTAssertFalse(reasons.contains { $0.contains("Recommended") }, "\(reasons)")
        XCTAssertTrue(reasons.contains { $0.contains("x-height") }, "\(reasons)")
    }

    /// With no Display face the sort falls back to Name, as before.
    @MainActor
    func testWithoutADisplayFaceTheSortStaysNameOrLessCommon() {
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop"], environment: ["XCTestConfigurationFilePath": "x"]))
        model.lenses.sort = .characterFirst
        XCTAssertEqual(model.effectiveLenses.sort, .name)
    }
}
