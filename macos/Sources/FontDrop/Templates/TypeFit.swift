import CoreText
import SwiftUI

/// Sizes a template's type from the real font instead of from a fixed number.
///
/// The Paper boards were drawn for one pair (PP Museum over Timeless Sans). The same pixel size is wrong for a
/// wide, heavy or small-x-height face. So a template says what each piece of text is for, and this file solves the
/// size from the styled font's own metrics (Core Text):
///
///   headline   the size, nearest the board's, at which the text sets in the template's line count and fills its column
///   display    a small display role (wordmark, drop cap, quote): the board's cap height, whatever the face
///   reading    a Reading role: the board's x-height, kept within a quarter of the board size
///
/// Line height is then raised, never lowered, until the lines of the real text clear each other.
///
/// React: a layout hook that measures the font once and returns the `font-size` and `line-height` to use,
/// memoised by face + text + column.
enum TypeFit {
    // MARK: Reference

    /// The pair the boards were drawn for. A face with these metrics gets the board's pixel sizes unchanged.
    /// Measured with Core Text at 100 pt: PP Museum Regular cap height 0.700 em, Timeless Sans Regular x-height 0.518 em
    /// (the Display and the Reading face on the Paper boards). `TemplateFitTests.testReferenceMetricsMatch` re-measures them.
    static let refCapHeight: CGFloat = 0.700
    static let refXHeight: CGFloat = 0.518

    /// A solved Reading size stays within a quarter of the board size, so an odd face cannot run away.
    static let readingClamp: ClosedRange<CGFloat> = 0.75...1.25
    /// A small display role gets a little more room, since some display faces have unusual caps.
    static let displayClamp: ClosedRange<CGFloat> = 0.65...1.45
    /// A headline never grows past this multiple of its board size, even when the column would take more.
    static let headlineCeiling: CGFloat = 1.75
    /// The shortest longest-line a headline accepts, as a share of its column.
    static let minFill: CGFloat = 0.8
    /// Air kept between the ink of one line and the next, in em.
    static let lineGap: CGFloat = 0.02

    // MARK: Metrics

    struct Metrics: Sendable {
        let cap: CGFloat        // cap height, as a fraction of the em
        let xHeight: CGFloat    // x-height, as a fraction of the em
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var metricsMemo: [String: Metrics] = [:]
    nonisolated(unsafe) private static var headlineMemo: [String: Headline] = [:]

    /// Cap height and x-height of the styled face (its weight, axes and features), per em. Nil until the file is loaded.
    static func metrics(_ face: FaceSpec) -> Metrics? {
        var plain = face.settings
        plain.trim = 1
        let key = "\(face.resolvedPath)|\(plain.hashValue)"
        lock.lock(); let hit = metricsMemo[key]; lock.unlock()
        if let hit { return hit }
        guard let font = FontLoader.shared.styledFont(face, ratio: 100 / CGFloat(face.settings.size)) else { return nil }
        let size = CTFontGetSize(font)
        let cap = CTFontGetCapHeight(font) / size
        var x = CTFontGetXHeight(font) / size
        if x <= 0.05 { x = (cap > 0 ? cap * 0.72 : refXHeight) }      // an all-caps face reports no x-height
        let m = Metrics(cap: cap > 0.05 ? cap : refCapHeight, xHeight: x)
        lock.lock(); metricsMemo[key] = m; lock.unlock()
        return m
    }

    // MARK: Sizes of one role

    struct Solved {
        var size: CGFloat
        /// The solved size hit the clamp, so the target metric is not matched exactly.
        var clamped = false
    }

    /// A small display role: the size whose cap height equals the board size's, in PP Museum.
    static func displaySize(_ face: FaceSpec, px: CGFloat) -> Solved {
        guard let m = metrics(face) else { return Solved(size: px) }
        return clamp(px * refCapHeight / m.cap, px: px, to: displayClamp)
    }

    /// A Reading role: the size whose x-height equals the board size's, in the reference Reading face.
    static func readingSize(_ face: FaceSpec, px: CGFloat) -> Solved {
        guard let m = metrics(face) else { return Solved(size: px) }
        return clamp(px * refXHeight / m.xHeight, px: px, to: readingClamp)
    }

    private static func clamp(_ size: CGFloat, px: CGFloat, to range: ClosedRange<CGFloat>) -> Solved {
        let low = px * range.lowerBound, high = px * range.upperBound
        return Solved(size: min(max(size, low), high), clamped: size < low - 0.001 || size > high + 0.001)
    }

    // MARK: Line height

    /// How far the ink of a line reaches above and below its baseline, in points, for these glyphs.
    static func ink(_ text: String, font: CTFont, tracking: CGFloat) -> (above: CGFloat, below: CGFloat) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: tracking]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return (max(bounds.maxY, 0), max(-bounds.minY, 0))
    }

    /// The line pitch (distance between baselines) these lines need so their ink does not touch, plus a small gap.
    /// Counts the real letters: a line with no descenders over a line with no ascenders needs very little.
    static func pitchNeed(lines: [String], font: CTFont, tracking: CGFloat) -> CGFloat {
        guard lines.count > 1 else { return 0 }
        let inks = lines.map { ink($0, font: font, tracking: tracking) }
        var need: CGFloat = 0
        for i in 0..<(inks.count - 1) { need = max(need, inks[i].below + inks[i + 1].above) }
        return need + lineGap * CTFontGetSize(font)
    }

    /// The pitch to use: the template's own when the ink clears, else just enough. Never tighter than asked.
    static func pitch(lines: [String], font: CTFont, tracking: CGFloat, wanted: CGFloat) -> CGFloat {
        max(wanted, pitchNeed(lines: lines, font: font, tracking: tracking))
    }

    /// For text that wraps wherever its container says (a paragraph): the pitch if every line were as tall
    /// as the tallest letters in the whole text. A little stricter than the real lines, never looser.
    static func pitchNeed(wrapped text: String, font: CTFont, tracking: CGFloat) -> CGFloat {
        let i = ink(text, font: font, tracking: tracking)
        return i.above + i.below + lineGap * CTFontGetSize(font)
    }

    // MARK: Headlines

    struct Headline {
        var size: CGFloat
        var lines: [String]
        var lineWidths: [CGFloat]
        var pitch: CGFloat
        /// The pitch the ink of these lines needs, before the template's own line height is considered.
        var need: CGFloat = 0
        /// The longest line as a share of the column.
        var fill: CGFloat
        /// The maxHeight limit set the size, so the column is not filled.
        var heightLimited = false
        /// The size hit the ceiling (a short headline in a narrow face).
        var capped = false
    }

    private static func lineWidth(_ text: String, font: CTFont, tracking: CGFloat) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: tracking]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Measures `text` set at `size`: its lines, their widths and the pitch they get.
    static func set(_ text: String, face: FaceSpec, size: CGFloat, trackingEm: Double, width: CGFloat, lh: Double) -> Headline? {
        guard let base = FontLoader.shared.styledFont(face, ratio: 1) else { return nil }
        let font = abs(CTFontGetSize(base) - size) < 0.001 ? base : CTFontCreateCopyWithAttributes(base, size, nil, nil)
        let tracking = CGFloat(trackingEm) * size
        let lines = TightLines.lines(text, font: font, tracking: tracking, width: width)
        let widths = lines.map { lineWidth($0, font: font, tracking: tracking) }
        let need = pitchNeed(lines: lines, font: font, tracking: tracking)
        let p = max(CGFloat(lh) * size, need)
        return Headline(size: size, lines: lines, lineWidths: widths, pitch: p, need: need, fill: (widths.max() ?? 0) / max(width, 1))
    }

    /// The size nearest the board size at which `text` sets in `lines` lines inside `width`, its longest line at least 80% of
    /// the column, and (with `maxHeight`) no taller than that. A word is never split: the widest word must fit.
    /// When no size fills the column, the one that fills it most. Memoised.
    static func fitHeadline(_ text: String, face: FaceSpec, px: CGFloat, trackingEm: Double, lh: Double, width: CGFloat,
                            lines range: ClosedRange<Int>, maxHeight: CGFloat?) -> Headline? {
        var plain = face.settings
        plain.trim = 1
        let key = "\(face.resolvedPath)|\(plain.hashValue)|\(text)|\(px)|\(trackingEm)|\(lh)|\(width)|\(range)|\(maxHeight ?? 0)"
        lock.lock(); let hit = headlineMemo[key]; lock.unlock()
        if let hit { return hit }
        guard let base = FontLoader.shared.styledFont(face, ratio: 1) else { return nil }

        let ceiling = px * headlineCeiling
        var best: Headline?            // best fill so far among sizes that satisfy the hard rules
        var chosen: Headline?
        var size = ceiling
        var heightLimited = false
        while size >= px * FitWords.floor {
            let font = CTFontCreateCopyWithAttributes(base, size, nil, nil)
            let widest = FitWords.widestWord(text, font: font, trackingEm: trackingEm)
            if widest <= width, let h = set(text, face: face, size: size, trackingEm: trackingEm, width: width, lh: lh),
               h.fill <= 1,
               h.lines.count <= range.upperBound {
                if let maxHeight, CGFloat(h.lines.count) * h.pitch > maxHeight {
                    heightLimited = true      // fits the column but not the board: keep shrinking
                } else {
                    // Among the sizes that fill the column in the line range, the one nearest the board size: a face that
                    // already fits keeps the board's look, a wide one shrinks, a narrow one grows only as far as it must.
                    if h.fill >= minFill, h.lines.count >= range.lowerBound,
                       chosen == nil || abs(log(size / px)) < abs(log(chosen!.size / px)) { chosen = h }
                    if best == nil || h.fill > best!.fill { best = h }
                }
            }
            if let c = chosen, size < min(px, c.size) * 0.9 { break }      // only farther from the board size from here
            size *= 0.99
        }
        var out = chosen ?? best
        if var o = out {
            o.heightLimited = heightLimited && o.fill < minFill
            o.capped = abs(o.size - ceiling) < ceiling * 0.011 && o.fill < minFill
            out = o
        }
        if out == nil { out = set(text, face: face, size: px * FitWords.floor, trackingEm: trackingEm, width: width, lh: lh) }
        if let out {
            lock.lock()
            if headlineMemo.count > 2000 { headlineMemo.removeAll() }
            headlineMemo[key] = out
            lock.unlock()
        }
        return out
    }
}

/// A template's main headline, declared once: the text, the board size it was drawn at, how it sets and how many
/// lines it may take. The template draws it with `ctx.headline`; the Scale readout and the lock use the same numbers.
struct HeadlineSpec {
    let text: String
    /// Size on the 600-wide board, in PP Museum.
    let px: CGFloat
    var track: Double = 0
    var lh: Double
    /// The column. Nil for a single poster word that is sized by its board, not by a column.
    var width: CGFloat?
    var lines: ClosedRange<Int> = 1...1
    var maxHeight: CGFloat?
}

/// One solved piece of text, kept by a `FitRecorder` so a test can check what a template asked for.
struct FitRecord {
    enum Kind { case headline, display, reading }
    let kind: Kind
    let text: String
    let px: CGFloat
    /// Size in points on the board, after Fit or the lock, before trim.
    let size: CGFloat
    let clamped: Bool
    let width: CGFloat?
    let lines: [String]
    let lineWidths: [CGFloat]
    let fill: CGFloat?
    let heightLimited: Bool
    let capped: Bool
    /// Reading only: the x-height asked for and the one drawn, in points.
    let xTarget: CGFloat?
    let xActual: CGFloat?
    let tracking: Double
    let pitch: CGFloat?
    let need: CGFloat?
}

/// Collects every `FitRecord` a template's views solve while they render. Tests only; nil in the app.
final class FitRecorder {
    private(set) var records: [FitRecord] = []
    func add(_ r: FitRecord) { records.append(r) }
}

/// The main headline of each template variant and the Reading size it sits next to. The Scale section reads these
/// to show the solved sizes and to pick a ratio when the designer locks the scale.
enum TemplateAnchors {
    struct Anchor {
        let headline: HeadlineSpec
        /// The template's body text, on the board.
        let bodyPx: CGFloat
    }

    static func anchor(template: String, variant: String) -> Anchor? {
        switch (template, variant) {
        case ("article", "feature"): Anchor(headline: ArticleFeature.headline, bodyPx: 15)
        case ("article", _): Anchor(headline: ArticleEssay.headline, bodyPx: 17)
        case ("hero", "product"): Anchor(headline: HeroProduct.headline, bodyPx: 16)
        case ("hero", _): Anchor(headline: HeroStatement.headline, bodyPx: 16)
        case ("appui", "dashboard"): Anchor(headline: AppDashboard.headline, bodyPx: 13)
        case ("appui", _): Anchor(headline: AppDetail.headline, bodyPx: 15)
        case ("poster", "specimen"): Anchor(headline: HeadlineSpec(text: TemplateCopy.specimenGlyphs, px: 320, lh: 0.78), bodyPx: 13)
        case ("poster", "readout"): Anchor(headline: HeadlineSpec(text: TemplateCopy.readoutWord, px: 320, lh: 0.82), bodyPx: 15)
        case ("poster", "blocks"): Anchor(headline: HeadlineSpec(text: TemplateCopy.blocksWord, px: 158, lh: 0.99), bodyPx: 12)
        case ("poster", "layered"): Anchor(headline: HeadlineSpec(text: TemplateCopy.layeredWord[0], px: 212, lh: 0.86), bodyPx: 13)
        case ("poster", _): Anchor(headline: HeadlineSpec(text: TemplateCopy.eventTitle[0], px: 232, lh: 0.82), bodyPx: 13)
        default: nil
        }
    }
}
