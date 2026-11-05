import FontDropCore
import XCTest
@testable import FontDrop

/// Fixtures use neutral names only.
final class LensEngineTests: XCTestCase {
    private func ev(_ lens: String, _ detail: String = "", strength: String = "guideline", effect: Int8 = 1) -> Evidence {
        Evidence(lens: lens, detail: detail, source: "", strength: strength, effect: effect)
    }

    private lazy var cands: [Candidate] = [
        // 0: serif + sans, different skeleton, crossed hands
        Candidate(id: "a", family: "Acme Sans", pairType: "contrast",
                  evidence: [ev("Clear contrast", "serif + sans"), ev("x-height", "within 4%")], order: 0),
        // 1: contrast, same skeleton, shared foundry, textural contrast
        Candidate(id: "b", family: "Acme Grotesk", pairType: "contrast",
                  evidence: [ev("Clear contrast"), ev("Skeleton", "both rational", strength: "shortcut"),
                             ev("Foundry", "Acme Type", strength: "shortcut"), ev("Texture", "high vs low"),
                             ev("x-height", "within 9%")], order: 1),
        // 2: uniform pair
        Candidate(id: "c", family: "Acme Serif", pairType: "uniform",
                  evidence: [ev("Uniform", "Both dynamic")], order: 2),
        // 3: the middle, no x-height evidence
        Candidate(id: "d", family: "Acme Mono Text", pairType: "middle",
                  evidence: [ev("The middle", "", effect: -1)], order: 3),
    ]

    func testDefaultLensKeepsOnlyClearContrast() {
        let r = LensEngine.apply(cands, lenses: Lenses())
        XCTAssertEqual(Set(r.shown.map(\.id)), ["a", "b"])
        XCTAssertEqual(r.hidden, 2)
    }

    func testAnyShowsEverythingAndHidesNothing() {
        var l = Lenses(); l.contrast = .any
        let r = LensEngine.apply(cands, lenses: l)
        XCTAssertEqual(r.shown.count, 4)
        XCTAssertEqual(r.hidden, 0)
    }

    func testCloseIsUniform() {
        var l = Lenses(); l.contrast = .close
        XCTAssertEqual(LensEngine.apply(cands, lenses: l).shown.map(\.id), ["c"])
    }

    func testSameAndCrossedHand() {
        var l = Lenses(); l.contrast = .any; l.structure = .same
        XCTAssertEqual(Set(LensEngine.apply(cands, lenses: l).shown.map(\.id)), ["b", "c"])
        l.structure = .mixed
        XCTAssertEqual(Set(LensEngine.apply(cands, lenses: l).shown.map(\.id)), ["a", "d"])
    }

    func testSameFoundry() {
        var l = Lenses(); l.contrast = .any; l.foundry = .sameOnly
        XCTAssertEqual(LensEngine.apply(cands, lenses: l).shown.map(\.id), ["b"])
    }

    func testExtremeNeedsTextureOrCrossedHands() {
        var l = Lenses(); l.contrast = .strong
        XCTAssertEqual(Set(LensEngine.apply(cands, lenses: l).shown.map(\.id)), ["a", "b"])
    }

    func testBestMatchKeepsTheEnginesOrder() {
        var l = Lenses(); l.contrast = .any
        XCTAssertEqual(LensEngine.apply(cands, lenses: l).shown.map(\.id), ["a", "b", "c", "d"])
    }

    func testContrastStepsAreOrderedForAFutureSlider() {
        XCTAssertEqual(ContrastLens.steps, [.close, .clear, .strong])
        XCTAssertNil(ContrastLens.any.stepIndex)
    }

    func testLexiconUsesDesignerWords() {
        func e(_ lens: String, _ detail: String) -> Evidence {
            Evidence(lens: lens, detail: detail, source: "", strength: "guideline", effect: 1)
        }
        XCTAssertEqual(Lexicon.chip(e("Skeleton", "both dynamic")), "Both humanist")
        XCTAssertEqual(Lexicon.chip(e("Clear contrast", "serif + sans")), "Serif with sans")
        XCTAssertEqual(Lexicon.chip(e("x-height", "within 0%")), "Same x-height")
        XCTAssertEqual(Lexicon.chip(e("Near-duplicate", "x-height 1%")), "Too close to Display")
        XCTAssertEqual(Lexicon.chip(e("Texture", "contrasting vs linear")), "Even stroke vs high-contrast Display")
        XCTAssertEqual(Lexicon.chip(e("Foundry", "Acme Type")), "Same foundry")
        XCTAssertEqual(Lexicon.strength("shortcut"), "Rule of thumb")
        XCTAssertEqual(Lexicon.sources("LAT ch.5; TWC 69-70; BON p.145; MAY"), "Better Web Typography, Typewolf checklist, Smashing (Bonneville), Smashing (Mayer)")
    }

    func testXHeightSortAndNameSort() {
        var l = Lenses(); l.contrast = .any; l.sort = .xHeight
        XCTAssertEqual(LensEngine.apply(cands, lenses: l).shown.map(\.id), ["a", "b", "c", "d"])
        l.sort = .name
        XCTAssertEqual(LensEngine.apply(cands, lenses: l).shown.first?.family, "Acme Grotesk")
    }

    func testSearchNarrowsButDoesNotCountAsHiddenByLenses() {
        var l = Lenses(); l.contrast = .any
        let r = LensEngine.apply(cands, lenses: l, search: "serif")
        XCTAssertEqual(r.shown.map(\.id), ["c"])
        XCTAssertEqual(r.hidden, 0)
    }

    func testTierOrdersUserInstalledFirst() {
        XCTAssertLessThan(AppModel.tier("/Users/x/Library/Fonts/a.otf", home: "/Users/x"),
                          AppModel.tier("/Library/Fonts/a.otf", home: "/Users/x"))
        XCTAssertLessThan(AppModel.tier("/Library/Fonts/a.otf", home: "/Users/x"),
                          AppModel.tier("/System/Library/Fonts/a.otf", home: "/Users/x"))
    }
}
