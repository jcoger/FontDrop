import XCTest
@testable import FontDrop

/// The fit rule for fixed-size boards: however big the type gets (a locked scale with a big body and ratio, or Trim
/// at its top), the display type shrinks instead of running off the sheet.
final class PosterFitTests: XCTestCase {
    func testScaleNeverGrowsAndNeverVanishes() {
        XCTAssertEqual(PosterFit.scale(height: 800, fixed: 100, display: 300), 1)          // already fits
        XCTAssertLessThan(PosterFit.scale(height: 800, fixed: 100, display: 1400), 1)
        XCTAssertEqual(PosterFit.scale(height: 800, fixed: 100, display: 1_000_000), PosterFit.floor)
        XCTAssertEqual(PosterFit.scale(height: 800, fixed: 900, display: 100), PosterFit.floor, "no room at all still keeps a floor")
        XCTAssertEqual(PosterFit.scale(height: 800, fixed: 100, display: 0), 1)
    }

    /// A locked scale: `body` and `ratio` set every size. Trim is the Display face's.
    private func context(body: Double = 15, ratio: Double = 1.333, trim: Double = 1) -> PairContext {
        var display = TypeSettings.defaults(job: "display")
        display.trim = trim
        let path = "/System/Library/Fonts/SFNS.ttf"
        FontLoader.shared.load(path: path)
        return PairContext(brand: "Acme", display: FaceSpec(path: path, settings: display),
                           body: FaceSpec(path: path, settings: TypeSettings.defaults(job: "reading")), tick: 0,
                           scale: TypeScale(body: body, ratio: ratio, locked: true))
    }

    func testEventShrinksAtLargeSizesAndOnlyThen() {
        // Small to large locked scales: the event poster's display type is 232 / 30 / 64 px on the board.
        let scales: [(Double, Double)] = [(9, 1.2), (12, 1.25), (15, 1.333), (20, 1.5), (24, 1.618)]
        let fits = scales.map { PosterEvent(ctx: context(body: $0.0, ratio: $0.1)).ctx.fit }
        XCTAssertEqual(fits[0], 1, "a small scale is left alone")
        XCTAssertLessThan(fits[4], 1, "the biggest scale used to run off the sheet")
        for i in 1..<fits.count { XCTAssertLessThanOrEqual(fits[i], fits[i - 1], "a bigger scale never shrinks less") }
        XCTAssertGreaterThan(fits[4], PosterFit.floor)
    }

    /// The type that remains, in board px, must fit the sheet: its drawn size x fit x the stacked line heights.
    func testEventDisplayHeightFitsTheSheet() {
        for (body, ratio) in [(20.0, 1.5), (24, 1.618)] {
            let c = PosterEvent(ctx: context(body: body, ratio: ratio)).ctx
            let title = 2 * 232 * 0.82 * c.displayScale(232)
            let line = 30 * 1.13 * c.displayScale(30)
            let date = 64 * 0.88 * c.displayScale(64)
            let stacked = (title + line + date) * c.fit
            XCTAssertLessThanOrEqual(stacked, 800 - 68, "body \(body) ratio \(ratio)")
        }
    }

    func testEveryPosterFitsAtTheLimits() {
        for (body, ratio, trim) in [(9.0, 1.2, 0.75), (15, 1.333, 1.0), (24, 1.618, 1.35)] {
            let c = context(body: body, ratio: ratio, trim: trim)
            let fits = [PosterEvent(ctx: c).ctx.fit, PosterSpecimen(ctx: c).ctx.fit, PosterReadout(ctx: c).ctx.fit,
                        PosterBlocks(ctx: c).ctx.fit, PosterLayered(ctx: c).ctx.fit]
            for f in fits {
                XCTAssertLessThanOrEqual(f, 1); XCTAssertGreaterThanOrEqual(f, PosterFit.floor)
            }
            if body >= 24 { XCTAssertTrue(fits.allSatisfy { $0 < 1 }, "every poster shrinks at the biggest scale") }
        }
    }
}
