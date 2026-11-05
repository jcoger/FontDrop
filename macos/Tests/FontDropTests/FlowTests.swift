import CoreText
import FontDropCore
import XCTest
@testable import FontDrop

/// The choose flow against a throwaway DB, and the playground's settings -> font step.
@MainActor
final class FlowTests: XCTestCase {
    private func makeModel() async -> AppModel {
        let path = NSTemporaryDirectory() + "fontdrop-test-\(UUID().uuidString).db"
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--bench"], environment: [:]))
        await model.bootstrap()
        return model
    }

    func testChoosingWithNoBrandAsksForANameThenApplies() async {
        let model = await makeModel()
        XCTAssertNil(model.brandID)
        await model.choose("display", family: "Acme Serif")
        XCTAssertEqual(model.pending, .choose(job: "display", family: "Acme Serif"))
        XCTAssertNil(model.errorMessage, "never an error")
        await model.createBrandAndApplyPending("Untitled brand")
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.brand?.name, "Untitled brand")
        XCTAssertEqual(model.choices["display"], "Acme Serif")
    }

    func testUndoRestoresThePreviousFaceOrClears() async {
        let model = await makeModel()
        await model.createBrand("Test brand")
        await model.choose("reading", family: "One")
        XCTAssertTrue(model.canUndo("reading"))
        await model.undo("reading")
        XCTAssertNil(model.choices["reading"], "first choice: undo clears")
        await model.choose("reading", family: "One")
        await model.choose("reading", family: "Two")
        await model.undo("reading")
        XCTAssertEqual(model.choices["reading"], "One", "later choice: undo restores the previous face")
    }

    func testPlaygroundAppliesVariationAndFeatures() throws {
        // SF Pro is a variable font on every Mac: wght, wdth, opsz.
        let path = "/System/Library/Fonts/SFNS.ttf"
        guard case .success(let loaded) = FontLoader.shared.load(path: path) else { return XCTFail("could not load SFNS") }
        let info = FaceInspector.read(loaded)
        XCTAssertTrue(info.axes.contains { $0.tag == "wght" })
        XCTAssertFalse(info.axes.contains { $0.hidden }, "hidden axes are not offered")
        XCTAssertFalse(info.features.isEmpty)

        var s = TypeSettings.defaults(job: "display")
        s.axes["wght"] = 700
        let font = s.font(from: loaded, axisInfo: info.axes)
        let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
        let wght = info.axes.first { $0.tag == "wght" }!
        XCTAssertEqual(variation[NSNumber(value: wght.identifier)]?.doubleValue ?? 0, 700, accuracy: 0.5)
    }

    func testFeatureChoicesBecomeCoreTextSettings() {
        var s = TypeSettings.defaults(job: "reading")
        s.features["35.10"] = 1        // ss05 on
        s.features["36.0"] = 0         // contextual alternates off
        s.features["21"] = 0           // old-style figures
        let pairs = s.featureAttribute.map { ($0[kCTFontFeatureTypeIdentifierKey as String]!, $0[kCTFontFeatureSelectorIdentifierKey as String]!) }
        XCTAssertTrue(pairs.contains { $0 == (35, 10) })
        XCTAssertTrue(pairs.contains { $0 == (36, 1) })
        XCTAssertTrue(pairs.contains { $0 == (21, 0) })
    }
}
