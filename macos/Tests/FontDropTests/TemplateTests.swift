import CoreText
import XCTest
@testable import FontDrop

/// Figure settings, variants and the per-brand style store.
@MainActor
final class TemplateTests: XCTestCase {
    // MARK: Figures

    private func pairs(_ s: TypeSettings) -> [(Int, Int)] {
        s.featureAttribute.map { (Int($0[kCTFontFeatureTypeIdentifierKey as String]!), Int($0[kCTFontFeatureSelectorIdentifierKey as String]!)) }
    }

    func testTabularFiguresSetNumberSpacingSelectorZero() {
        let s = TypeSettings.defaults(job: "reading").figures(.tabular)
        XCTAssertTrue(pairs(s).contains { $0 == (kNumberSpacingType, kMonospacedNumbersSelector) })
        XCTAssertEqual(kNumberSpacingType, 6)
        XCTAssertEqual(kMonospacedNumbersSelector, 0)
    }

    func testProportionalFiguresSetNumberSpacingSelectorOne() {
        let s = TypeSettings.defaults(job: "display").figures(.proportional)
        XCTAssertTrue(pairs(s).contains { $0 == (kNumberSpacingType, kProportionalNumbersSelector) })
        XCTAssertEqual(kProportionalNumbersSelector, 1)
    }

    func testInheritLeavesTheDesignersChoice() {
        var base = TypeSettings.defaults(job: "reading")
        base.features["6"] = 0
        XCTAssertEqual(base.figures(.inherit), base)
        XCTAssertEqual(TypeSettings.defaults(job: "reading").figures(.inherit).features, [:])
    }

    func testFiguresKeepOtherSettings() {
        var base = TypeSettings.defaults(job: "reading")
        base.features["35.10"] = 1
        base.axes["wght"] = 600
        let tab = base.figures(.tabular)
        XCTAssertEqual(tab.features["35.10"], 1)
        XCTAssertEqual(tab.axes["wght"], 600)
    }

    func testTabularAndProportionalDrawDifferentWidthsInARealFont() throws {
        // SF Pro ships both. "1" is narrower than "0" in proportional figures and equal in tabular.
        let path = "/System/Library/Fonts/SFNS.ttf"
        guard case .success(let loaded) = FontLoader.shared.load(path: path) else { return XCTFail("could not load SFNS") }
        let info = FaceInspector.read(loaded)
        func width(of text: String, _ f: Figures) -> CGFloat {
            let font = TypeSettings.defaults(job: "display").figures(f).font(from: loaded, axisInfo: info.axes)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }
        XCTAssertEqual(width(of: "1", .tabular), width(of: "0", .tabular), accuracy: 0.01)
        XCTAssertLessThan(width(of: "1", .proportional), width(of: "0", .proportional))
    }

    // MARK: Weight and italic helpers

    func testWeightTraitMapsToCSSScale() {
        XCTAssertEqual(StyleTraits.cssWeight(fromTrait: 0), 400, accuracy: 0.5)
        XCTAssertEqual(StyleTraits.cssWeight(fromTrait: 0.4), 700, accuracy: 0.5)
        XCTAssertEqual(StyleTraits.cssWeight(fromTrait: -0.8), 100, accuracy: 0.5)
        XCTAssertGreaterThan(StyleTraits.cssWeight(fromTrait: 0.1), 400)
        XCTAssertLessThan(StyleTraits.cssWeight(fromTrait: 0.1), 500)
    }

    func testVariableFaceWeightedSetsTheAxisAndClamps() throws {
        let path = "/System/Library/Fonts/SFNS.ttf"
        FontLoader.shared.load(path: path)
        let face = FaceSpec(path: path, settings: .defaults(job: "display"))
        let heavy = face.weighted(700)
        XCTAssertEqual(heavy.settings.axes["wght"] ?? 0, 700, accuracy: 0.5)
        let absurd = face.weighted(5000)
        XCTAssertLessThanOrEqual(absurd.settings.axes["wght"] ?? 0, 1000)
        XCTAssertGreaterThan(face.weighted(900).weightPosition, face.weighted(200).weightPosition)
    }

    // MARK: Variants and the style store

    private func makeStore(_ suite: String, dbPath: String = NSTemporaryDirectory() + "style-\(UUID().uuidString).db") -> BrandStyleStore {
        let defaults = UserDefaults(suiteName: suite)!
        return BrandStyleStore(dbPath: dbPath, persist: true, defaults: defaults)
    }

    func testEveryTemplateListsItsVariants() {
        XCTAssertEqual(Templates.descriptor("article").variants.map(\.id), ["essay", "feature"])
        XCTAssertEqual(Templates.descriptor("hero").variants.map(\.id), ["statement", "product"])
        XCTAssertEqual(Templates.descriptor("appui").variants.map(\.id), ["detail", "dashboard"])
        XCTAssertEqual(Templates.descriptor("poster").variants.map(\.id), ["event", "specimen", "readout", "blocks", "layered"])
    }

    func testVariantDefaultsToTheFirstAndIsRememberedPerTemplate() {
        let suite = "fontdrop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let article = Templates.descriptor("article"), poster = Templates.descriptor("poster")
        let a = makeStore(suite)
        XCTAssertEqual(a.variant(article), "essay")
        XCTAssertEqual(a.variant(poster), "event")
        a.setVariant("feature", template: article)
        a.setVariant("readout", template: poster)
        // A new store, as after a relaunch.
        let b = makeStore(suite)
        XCTAssertEqual(b.variant(article), "feature")
        XCTAssertEqual(b.variant(poster), "readout")
        XCTAssertEqual(b.variant(Templates.descriptor("hero")), "statement", "other templates keep their own")
    }

    func testAStaleVariantFallsBackToTheFirst() {
        let suite = "fontdrop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let a = makeStore(suite)
        a.setVariant("gone", template: Templates.descriptor("hero"))
        XCTAssertEqual(a.variant(Templates.descriptor("hero")), "statement")
    }

    func testConfiguredTemplatePassesPaletteAndVariantToTheView() {
        // The descriptor wraps `make`. Check the wrapper hands the context on with the values set.
        var seen: PairContext?
        let probe = TemplateDescriptor(id: "x", title: "X", variants: []) { ctx in seen = ctx; return AnyView(EmptyView()) }
        let face = FaceSpec(path: "/none", settings: .defaults(job: "display"))
        _ = probe.configured(palette: .night, variant: "feature")
            .make(PairContext(brand: "Acme", display: face, body: face, tick: 0))
        XCTAssertEqual(seen?.palette, .night)
        XCTAssertEqual(seen?.variant, "feature")
    }

    func testPalettesAreSavedPerBrand() async throws {
        let suite = "fontdrop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let db = NSTemporaryDirectory() + "style-\(UUID().uuidString).db"
        let a = makeStore(suite, dbPath: db)
        a.setColor(.accent, try XCTUnwrap(HexColor(hex: "2B5C93")), brand: 1)
        a.setPalette(.night, brand: 2)
        XCTAssertEqual(a.palette(brand: 1).accent.hex, "#2B5C93")
        XCTAssertEqual(a.palette(brand: 1).background, TemplatePalette.paper.background, "only the accent changed")
        XCTAssertEqual(a.palette(brand: 2), .night)
        XCTAssertEqual(a.palette(brand: 3), .paper, "a brand with nothing saved reads Paper")
        try await Task.sleep(for: .milliseconds(900))        // the store writes after a short pause
        let b = makeStore(suite, dbPath: db)
        XCTAssertEqual(b.palette(brand: 1).accent.hex, "#2B5C93")
        XCTAssertEqual(b.palette(brand: 2), .night)
    }

    func testRecentColorsKeepTheLastEightNewestFirstWithoutRepeats() throws {
        let suite = "fontdrop.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let s = makeStore(suite)
        for i in 0..<10 { s.remember(HexColor(r: Double(i) / 10, g: 0, b: 0)) }
        XCTAssertEqual(s.recents.count, 8)
        XCTAssertEqual(s.recents.first, HexColor(r: 0.9, g: 0, b: 0))
        s.remember(HexColor(r: 0.5, g: 0, b: 0))
        XCTAssertEqual(s.recents.first, HexColor(r: 0.5, g: 0, b: 0))
        XCTAssertEqual(s.recents.filter { $0 == HexColor(r: 0.5, g: 0, b: 0) }.count, 1)
        XCTAssertEqual(makeStore(suite).recents.count, 8, "global and saved")
    }

    func testReadoutBarsMapValuesOntoTheirRanges() {
        XCTAssertEqual(PosterReadout.position(14, in: PosterReadout.displaySize), 0, accuracy: 0.0001)
        XCTAssertEqual(PosterReadout.position(120, in: PosterReadout.displaySize), 1, accuracy: 0.0001)
        XCTAssertEqual(PosterReadout.position(15, in: PosterReadout.readingSize), 6.0 / 31, accuracy: 0.0001)
        XCTAssertEqual(PosterReadout.position(0, in: PosterReadout.tracking), 0.08 / 0.38, accuracy: 0.0001)
        XCTAssertEqual(PosterReadout.position(999, in: PosterReadout.readingSize), 1, "clamped")
    }
}
