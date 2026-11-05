import FontDropCore
import XCTest
@testable import FontDrop

/// Same family: the Display family offered as its own partner. Fixtures use neutral names.
@MainActor
final class SameFamilyTests: XCTestCase {
    private func same(order: Int = 0) -> Candidate {
        Candidate(id: "s", family: "Acme Display", pairType: "same_family",
                  evidence: [Evidence(lens: "Same family", detail: "5 widths, 16 styles, text cut",
                                      source: "", strength: "guideline", effect: 1)],
                  order: order, bodyStyle: BodyStyle(fontId: "s", filePath: "/x/Acme-Regular.otf", label: "Regular"))
    }

    private func contrast(_ id: String, order: Int) -> Candidate {
        Candidate(id: id, family: "Acme \(id)", pairType: "contrast", evidence: [], order: order)
    }

    func testSameFamilyShowsUnderEveryLens() {
        var l = Lenses()
        for contrast in ContrastLens.allCases {
            for structure in StructureLens.allCases {
                l.contrast = contrast; l.structure = structure; l.foundry = .sameOnly
                XCTAssertTrue(LensEngine.passes(same(), l), "\(contrast) \(structure)")
            }
        }
    }

    func testSameFamilyLeadsTheEnginesOrder() {
        let r = LensEngine.apply([contrast("a", order: 1), same(order: 0), contrast("b", order: 2)], lenses: Lenses())
        XCTAssertEqual(r.shown.first?.id, "s")
    }

    func testWordsForTheGroupAndEvidence() {
        XCTAssertEqual(Lexicon.pairGroup("same_family"), "Same family")
        XCTAssertEqual(Lexicon.sameFamilyHelp, "Use this family for both. Pick a different width or weight for the body.")
        XCTAssertEqual(Lexicon.chip(same().evidence[0]), "Same family: 5 widths, 16 styles, text cut")
        XCTAssertEqual(Lexicon.bodyIn("Regular"), "Body in Regular")
        let weak = Evidence(lens: "Long text", detail: "No bold italic", source: "", strength: "guideline", effect: -1)
        XCTAssertEqual(Lexicon.chip(weak), "May be weak for long text")
    }

    func testBodyStyleStartsTheStylePickerAndIsKeptOnChoice() {
        let store = TypeSettingsStore(dbPath: NSTemporaryDirectory() + "same-family-test.db", persist: false)
        let key = TypeSettingsStore.key(brand: 1, job: "reading", family: "Acme Display")
        XCTAssertNil(store.settings(key, job: "reading").stylePath)
        store.setSuggestedStyles([key: "/x/Acme-Regular.otf"])
        XCTAssertEqual(store.settings(key, job: "reading").stylePath, "/x/Acme-Regular.otf", "the picker starts on the suggestion")
        XCTAssertFalse(store.isModified(key, job: "reading"), "a suggestion is not the designer's edit")
        store.adoptSuggestion(key, job: "reading")
        XCTAssertEqual(store.map[key]?.stylePath, "/x/Acme-Regular.otf", "choosing keeps it")
        // The designer's own pick wins over a later suggestion.
        store.update(key, job: "reading") { $0.stylePath = "/x/Acme-Text.otf" }
        store.setSuggestedStyles([key: "/x/Acme-Regular.otf"])
        XCTAssertEqual(store.settings(key, job: "reading").stylePath, "/x/Acme-Text.otf")
    }
}
