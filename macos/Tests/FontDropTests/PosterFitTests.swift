import XCTest
@testable import FontDrop

/// The fit rule for fixed-size boards: at any playground Display size from 14 to 120, the display type shrinks
/// instead of running off the sheet.
final class PosterFitTests: XCTestCase {
    func testScaleNeverGrowsAndNeverVanishes() {
        XCTAssertEqual(PosterFit.scale(height: 800, fixed: 100, display: 300), 1)          // already fits
        XCTAssertLessThan(PosterFit.scale(height: 800, fixed: 100, display: 1400), 1)
        XCTAssertEqual(PosterFit.scale(height: 800, fixed: 100, display: 1_000_000), PosterFit.floor)
        XCTAssertEqual(PosterFit.scale(height: 800, fixed: 900, display: 100), PosterFit.floor, "no room at all still keeps a floor")
        XCTAssertEqual(PosterFit.scale(height: 800, fixed: 100, display: 0), 1)
    }

    private func context(size: Double) -> PairContext {
        var display = TypeSettings.defaults(job: "display")
        display.size = size
        let path = "/System/Library/Fonts/SFNS.ttf"
        FontLoader.shared.load(path: path)
        return PairContext(brand: "Acme", display: FaceSpec(path: path, settings: display),
                           body: FaceSpec(path: path, settings: TypeSettings.defaults(job: "reading")), tick: 0)
    }

    func testEventShrinksAtLargeSizesAndOnlyThen() {
        let sizes: [Double] = [14, 30, 40, 63, 90, 120]
        let fits = sizes.map { PosterEvent(ctx: context(size: $0)).ctx.fit }
        XCTAssertEqual(fits[0], 1); XCTAssertEqual(fits[1], 1); XCTAssertEqual(fits[2], 1)
        XCTAssertLessThan(fits[3], 1, "63 pt is where the Event poster used to clip")
        for i in 1..<fits.count { XCTAssertLessThanOrEqual(fits[i], fits[i - 1], "a bigger size never shrinks less") }
        XCTAssertGreaterThan(fits[5], PosterFit.floor)
    }

    /// The type that remains, in board px, must fit the sheet: size x fit x the stacked line heights.
    func testEventDisplayHeightFitsTheSheet() {
        for size in [63.0, 90, 120] {
            let c = PosterEvent(ctx: context(size: size)).ctx
            let k = c.displayScale * c.fit
            let stacked = (2 * 232 * 0.82 + 30 * 1.13 + 64 * 0.88) * k      // title lines, one line of the standfirst, date
            XCTAssertLessThanOrEqual(stacked, 800 - 68, "size \(size)")
        }
    }

    func testEveryPosterFitsAtTheLimits() {
        for size in [14.0, 63, 120] {
            let c = context(size: size)
            let fits = [PosterEvent(ctx: c).ctx.fit, PosterSpecimen(ctx: c).ctx.fit, PosterReadout(ctx: c).ctx.fit,
                        PosterBlocks(ctx: c).ctx.fit, PosterLayered(ctx: c).ctx.fit]
            for f in fits {
                XCTAssertLessThanOrEqual(f, 1); XCTAssertGreaterThanOrEqual(f, PosterFit.floor)
            }
            if size <= 14 { XCTAssertTrue(fits.allSatisfy { $0 == 1 }, "a small size is left alone") }
            if size >= 120 { XCTAssertTrue(fits.allSatisfy { $0 < 1 }, "every poster shrinks at 120") }
        }
    }
}
