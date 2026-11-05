import CoreText
import FontDropCore
import XCTest
@testable import FontDrop

/// Round R4: the one-row bars, the Display inspector's modules, no auto-select, the sample line.
@MainActor
final class SimplifyTests: XCTestCase {
    private func makeModel() async -> AppModel {
        let path = NSTemporaryDirectory() + "fontdrop-r4-\(UUID().uuidString).db"
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--bench"], environment: [:]))
        await model.bootstrap()
        return model
    }

    // MARK: the source menu and the Filters count

    func testSourceMenuNamesWhatItShows() {
        XCTAssertEqual(Lexicon.Finder.sourceMenuValue([.yours, .google], savedOnly: false), "Your fonts + Google")
        XCTAssertEqual(Lexicon.Finder.sourceMenuValue([.yours], savedOnly: false), "Your fonts")
        XCTAssertEqual(Lexicon.Finder.sourceMenuValue([.yours, .google, .system], savedOnly: false), "All fonts")
        XCTAssertEqual(Lexicon.Finder.sourceMenuValue([.yours, .google], savedOnly: true), "Saved", "Saved narrows every source")
    }

    func testTheDisplayKindIsCalledDecorative() {
        XCTAssertEqual(Lexicon.Finder.kindLabel(.display), "Decorative")
        XCTAssertFalse(Kind.all.map(Lexicon.Finder.kindLabel).contains("Display"), "Display is a job, not a kind")
    }

    func testFiltersCountsOnlyWhatNarrowsTheList() {
        var lenses = Lenses()
        lenses.contrast = .any
        XCTAssertEqual(ReadingFilterCount.active(sources: [.yours, .google], lenses: lenses, hasDisplay: true), 0)
        lenses.structure = .same
        XCTAssertEqual(ReadingFilterCount.active(sources: [.yours, .google], lenses: lenses, hasDisplay: true), 1)
        XCTAssertEqual(ReadingFilterCount.active(sources: [.yours], lenses: lenses, hasDisplay: true), 2)
        // Before a Display face exists the list has no Difference, Structure or Foundry questions.
        XCTAssertEqual(ReadingFilterCount.active(sources: [.yours, .google], lenses: lenses, hasDisplay: false), 0)
        XCTAssertEqual(Lexicon.R4.filters(0), "Filters")
        XCTAssertEqual(Lexicon.R4.filters(2), "Filters \u{00B7} 2")
    }

    // MARK: no auto-select

    func testAFirstRunSelectsNothing() async {
        let model = await makeModel()
        XCTAssertNil(model.selectedFamily, "nothing is selected before the designer picks")
    }

    func testABrandWithNoChoiceSelectsNothing() async {
        let model = await makeModel()
        await model.createBrand("Acme")
        XCTAssertNil(model.chosen(.display))
        XCTAssertNil(model.selectedFamily)
    }

    // MARK: the sample line

    func testTheSampleIsTheBrandNameUntilTheDesignerTypesOne() async {
        let model = await makeModel()
        await model.createBrand("Acme")
        XCTAssertEqual(model.sampleText, "Acme")
        model.setSample("Rooms that remember you")
        XCTAssertEqual(model.sampleText, "Rooms that remember you")
        model.setSample("   ")
        XCTAssertEqual(model.sampleText, "Acme", "an empty line puts the brand name back")
    }

    func testTheSampleIsKeptPerBrand() async {
        let model = await makeModel()
        await model.createBrand("Acme")
        model.setSample("One")
        await model.createBrand("Beta")
        XCTAssertEqual(model.sampleText, "Beta", "a new brand starts on its own name")
    }

    // MARK: Tuned

    func testAFaceIsTunedOnceItsSettingsChange() async {
        let model = await makeModel()
        await model.createBrand("Acme")
        let key = model.settingsKey("display", "Some Family")
        XCTAssertFalse(model.typeSettings.isModified(key, job: "display"))
        model.typeSettings.update(key, job: "display") { $0.tracking = 0.05 }
        XCTAssertTrue(model.typeSettings.isModified(key, job: "display"))
    }

    // MARK: Alternates

    private var geistMono: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FontDrop/Resources/Fonts/GeistMono.ttf").path
    }

    func testStylisticSetsBecomeTilesOfChangedLetters() async throws {
        await FontLoader.shared.preload(paths: [geistMono])
        let alternates = Alternates.read(path: geistMono)
        XCTAssertFalse(alternates.isEmpty, "Geist Mono ships stylistic sets that change letters")
        for alt in alternates {
            XCTAssertFalse(alt.letters.isEmpty)
            XCTAssertEqual(alt.code, String(format: "ss%02d", alt.number))
            XCTAssertEqual(alt.featureKey, "35.\(alt.onSelector)")
        }
        XCTAssertEqual(alternates.map(\.number), alternates.map(\.number).sorted())
    }

    func testAFontWithoutSetsHasNoTiles() async {
        let path = "/System/Library/Fonts/Supplemental/Arial.ttf"
        guard FileManager.default.fileExists(atPath: path) else { return }
        await FontLoader.shared.preload(paths: [path])
        XCTAssertTrue(Alternates.read(path: path).isEmpty)
    }

    func testAlternateWordsAreCodesOnHoverNotLabels() {
        XCTAssertEqual(Lexicon.R4.alternateHelp(name: "Alt a", code: "ss01"), "Alt a \u{00B7} ss01")
        XCTAssertEqual(Lexicon.R4.alternateHelp(name: "", code: "ss03"), "ss03")
        XCTAssertEqual(Lexicon.R4.alternateAccessibility(set: 3, letters: ["a", "g"], name: ""), "Stylistic set 3, changes a, g")
    }

    func testNewStringsHaveNoEmDashes() {
        let strings = [Lexicon.R4.sample, Lexicon.R4.alternates, Lexicon.R4.samplePlaceholder, Lexicon.R4.sampleClear,
                       Lexicon.R4.alternatesHint, Lexicon.R4.noAlternates, Lexicon.R4.showFewer, Lexicon.R4.tuned, Lexicon.R4.tunedHelp,
                       Lexicon.R4.filtersHelp, Lexicon.R4.noSelection, Lexicon.R4.noSelectionHelp, Lexicon.R4.familiesLine(brand: "Acme", count: 3),
                       Lexicon.Finder.sourceMenuHelp, Lexicon.Finder.kindAll, Lexicon.Finder.sourceMenuValue([.yours, .google], savedOnly: false)]
        for s in strings {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), "dash in: \(s)")
        }
    }
}
