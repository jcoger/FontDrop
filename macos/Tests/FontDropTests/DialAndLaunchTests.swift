import XCTest
@testable import FontDrop

/// Round R2b: the ratio dial's maths, and what the app remembers per brand at launch.
final class DialMathTests: XCTestCase {
    func testStopsAreEvenlySpacedWithTheFourthStraightUp() {
        XCTAssertEqual(DialMath.stops, [1.2, 1.25, 1.333, 1.5, 1.618])
        XCTAssertEqual(DialMath.angle(ofStop: 2), 0, "1.333 points straight up")
        XCTAssertEqual(DialMath.angle(ofStop: 0), -2 * DialMath.spread)
        XCTAssertEqual(DialMath.angle(ofStop: 4), 2 * DialMath.spread)
        let gaps = (1..<5).map { DialMath.angle(ofStop: $0) - DialMath.angle(ofStop: $0 - 1) }
        XCTAssertTrue(gaps.allSatisfy { $0 == DialMath.spread })
    }

    func testAnAngleSnapsToTheNearestStop() {
        let s = DialMath.spread
        XCTAssertEqual(DialMath.stopIndex(nearestToAngle: 0), 2)
        XCTAssertEqual(DialMath.stopIndex(nearestToAngle: s * 0.4), 2)
        XCTAssertEqual(DialMath.stopIndex(nearestToAngle: s * 0.6), 3, "past halfway goes to the next stop")
        XCTAssertEqual(DialMath.stopIndex(nearestToAngle: -s * 1.4), 1)
        XCTAssertEqual(DialMath.stopIndex(nearestToAngle: -500), 0, "far past the end holds at the first stop")
        XCTAssertEqual(DialMath.stopIndex(nearestToAngle: 500), 4)
    }

    func testAPointAroundThePivotBecomesAnAngle() {
        XCTAssertEqual(DialMath.angle(dx: 0, dy: -50), 0, accuracy: 1e-9, "straight above")
        XCTAssertEqual(DialMath.angle(dx: 50, dy: -50), 45, accuracy: 1e-9)
        XCTAssertEqual(DialMath.angle(dx: -50, dy: 0), -DialMath.reach, "level to the left clamps to the reach")
        XCTAssertEqual(DialMath.stopIndex(nearestToAngle: DialMath.angle(dx: 30, dy: -50)), 3, "31 degrees snaps to the 1.5 stop")
    }

    func testStepsStayInsideTheArc() {
        XCTAssertEqual(DialMath.step(from: 2, by: 1), 3)
        XCTAssertEqual(DialMath.step(from: 4, by: 1), 4)
        XCTAssertEqual(DialMath.step(from: 0, by: -1), 0)
    }

    func testARatioMapsToItsStopAngleAndAutoSitsBetween() {
        for (i, r) in DialMath.stops.enumerated() {
            XCTAssertEqual(DialMath.angle(ofRatio: r), DialMath.angle(ofStop: i), accuracy: 1e-9)
        }
        let between = DialMath.angle(ofRatio: 1.32)
        XCTAssertLessThan(between, 0)
        XCTAssertGreaterThan(between, DialMath.angle(ofStop: 1))
        XCTAssertEqual(DialMath.stopIndex(nearestToRatio: 1.32), 2)
    }

    func testTheAutoRatioIsTheHeadlineMultipleOverItsSteps() {
        // 84 pt headline on a 15 pt body, six steps up: 5.6 ^ (1/6) = 1.3325, between 1.25 and 1.333 and almost the Fourth.
        let r = try! XCTUnwrap(DialMath.autoRatio(headline: 84, body: 15, steps: 6))
        XCTAssertEqual(r, 1.3325, accuracy: 0.0005)
        XCTAssertEqual(DialMath.autoRatio(headline: 15 * pow(1.5, 4), body: 15, steps: 4)!, 1.5, accuracy: 1e-9)
        XCTAssertNil(DialMath.autoRatio(headline: 84, body: 0, steps: 6))
        XCTAssertNil(DialMath.autoRatio(headline: 84, body: 15, steps: 0))
    }

    func testReadoutNamesTheIntervalAndPrintsTheValue() {
        XCTAssertEqual(DialMath.intervalName(1.2), "Minor third")
        XCTAssertEqual(DialMath.intervalName(1.25), "Major third")
        XCTAssertEqual(DialMath.intervalName(1.333), "Fourth")
        XCTAssertEqual(DialMath.intervalName(1.5), "Fifth")
        XCTAssertEqual(DialMath.intervalName(1.618), "Golden")
        XCTAssertEqual(DialMath.valueLabel(1.333), "1.333")
        XCTAssertEqual(DialMath.valueLabel(1.5), "1.5")
        XCTAssertEqual(DialMath.valueLabel(1.3249), "1.32", "Auto between stops prints two places")
    }

    func testVoiceOverReadsTheState() {
        var scale = TypeScale()
        XCTAssertEqual(Lexicon.Dial.label, "Ratio")
        XCTAssertEqual(Lexicon.Dial.accessibilityValue(scale, autoRatio: 1.32), "Auto")
        scale.locked = true; scale.ratio = 1.333
        XCTAssertEqual(Lexicon.Dial.accessibilityValue(scale, autoRatio: nil), "1.333, locked")
    }

    func testDialStringsHaveNoDashes() {
        let strings = [Lexicon.Dial.betweenStops, Lexicon.Dial.pressForAuto, Lexicon.Dial.turnToLock, Lexicon.Dial.hint,
                       Lexicon.Launch.headline, Lexicon.Launch.body, Lexicon.Launch.emptyBody, Lexicon.Launch.notInstalled]
        for s in strings {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), s)
        }
    }
}

@MainActor
final class LaunchMemoryTests: XCTestCase {
    private func tempDB() -> String { NSTemporaryDirectory() + "fontdrop-memory-\(UUID().uuidString).db" }
    private func suite() -> UserDefaults { UserDefaults(suiteName: "fontdrop-memory-tests-\(UUID().uuidString)")! }

    func testSetWithNoFacesFallsBackToDisplay() {
        XCTAssertEqual(LaunchMemory.landingScreen(stored: .set, hasDisplay: false, hasText: false), .display)
        XCTAssertEqual(LaunchMemory.landingScreen(stored: .set, hasDisplay: true, hasText: false), .set)
        XCTAssertEqual(LaunchMemory.landingScreen(stored: .set, hasDisplay: false, hasText: true), .set)
        XCTAssertEqual(LaunchMemory.landingScreen(stored: .reading, hasDisplay: false, hasText: false), .reading)
        XCTAssertEqual(LaunchMemory.landingScreen(stored: nil, hasDisplay: true, hasText: true), .display, "nothing stored opens on Display")
        XCTAssertEqual(LaunchMemory.landingScreen(stored: .colors, hasDisplay: true, hasText: true), .display, "screens off the sidebar are not landed on")
    }

    func testEachBrandReturnsToItsOwnLastScreenAndTemplate() async {
        let defaults = suite()
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench"], environment: [:]), defaults: defaults)
        await model.bootstrap()
        let a = await model.createBrand("Alpha")!
        model.screen = .reading
        model.templateID = "poster"
        let b = await model.createBrand("Beta")!
        model.screen = .display
        model.templateID = "hero"

        await model.selectBrand(a)
        XCTAssertEqual(model.screen, .reading, "Alpha lands on its own last screen")
        XCTAssertEqual(model.templateID, "poster")
        await model.selectBrand(b)
        XCTAssertEqual(model.screen, .display)
        XCTAssertEqual(model.templateID, "hero")

        // A fresh model on the same preferences restores from storage, not from memory in the process.
        let again = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", model.dbPath, "--bench"], environment: [:]), defaults: defaults)
        await again.bootstrap()
        XCTAssertEqual(again.brandID, b, "the last brand is restored")
        XCTAssertEqual(again.screen, .display)
        await again.selectBrand(a)
        XCTAssertEqual(again.screen, .reading)
        XCTAssertEqual(LaunchMemory.load(defaults, brand: a)?.template, "poster")
    }

    func testAStoredSetScreenWithNoFacesOpensOnDisplay() async {
        let defaults = suite()
        let db = tempDB()
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", db, "--bench"], environment: [:]), defaults: defaults)
        await model.bootstrap()
        let a = await model.createBrand("Alpha")!
        model.screen = .set
        XCTAssertEqual(LaunchMemory.load(defaults, brand: a)?.screen, "set")
        let again = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", db, "--bench"], environment: [:]), defaults: defaults)
        await again.bootstrap()
        XCTAssertEqual(again.screen, .display, "no faces chosen, so Set has nothing to show")
    }

    func testAChosenFaceThatIsNotInstalledIsMissing() async {
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench"], environment: [:]), defaults: suite())
        await model.bootstrap()
        _ = await model.createBrand("Alpha")
        await model.choose("display", family: "Ghost Family")
        // An empty library has nothing to compare with, so nothing is flagged yet.
        XCTAssertFalse(model.isMissing(.display))
    }

    func testTheScanScreenShowsOnlyForANewInstallWhileScanning() async {
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", tempDB(), "--bench"], environment: [:]), defaults: suite())
        XCTAssertFalse(model.showsScanScreen, "not before the library is open")
        await model.bootstrap()
        XCTAssertFalse(model.showsScanScreen, "no scan is running in a bench run")
        XCTAssertTrue(model.libraryIsEmpty, "a bench run never scans, so the empty library it opened is final")
        XCTAssertTrue(model.hidesInspector, "no inspector with no fonts")
    }
}
