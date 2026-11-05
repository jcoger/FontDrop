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

    /// With no Display face the sort falls back to Name, as before.
    @MainActor
    func testWithoutADisplayFaceTheSortStaysNameOrLessCommon() {
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop"], environment: ["XCTestConfigurationFilePath": "x"]))
        model.lenses.sort = .characterFirst
        XCTAssertEqual(model.effectiveLenses.sort, .name)
    }
}
