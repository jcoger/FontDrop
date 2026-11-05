import CoreText
import Foundation

/// The rules for body text on Set: how many characters a line holds, and how tall a line is.
/// Plain numbers and pure functions, so tests can pin them.
///
/// The order matters (type size, then measure, then line height; change one and look at the next):
///  - Measure is counted in characters of the real text, not in the width of a zero. 45 to 75 is the range the
///    sources agree on (Bringhurst 45 to 75, Latin 55 to 75). The default sits in the middle of the overlap, at 66.
///  - Line height follows the measure. A short line wants tight leading, a long line wants loose: 1.30 at 45
///    characters, 1.50 at 75 (Brown), in between by a straight line. Rounded to 0.05 so it reads as a choice.
///  - Headings are set tighter than body, and tighter the bigger they get (`headingLeading`).
enum TextRules {
    /// What the Measure control can reach: a little past the comfortable band, both ways.
    static let measureRange = 35...90
    /// The band the readout calls comfortable.
    static let comfortableMeasure = 55...75
    static let defaultMeasure = 66
    /// What the Line height control can reach.
    static let lineHeightRange: ClosedRange<Double> = 1.1...1.8

    /// Body line height for a measure, when the designer has not set one.
    static func lineHeight(forMeasure measure: Int) -> Double {
        let t = min(max(Double(measure - 45) / 30, 0), 1)
        let raw = 1.30 + 0.20 * t
        return (raw / 0.05).rounded() * 0.05
    }

    /// What Set uses for this scale: the designer's choice, else the rule.
    static func measure(_ scale: TypeScale) -> Int { scale.measure ?? defaultMeasure }
    static func lineHeight(_ scale: TypeScale) -> Double { scale.lineHeight ?? lineHeight(forMeasure: measure(scale)) }

    /// Leading for a step above body: tighter as the size rises (1.05 for display down to 1.3 for the lead line).
    static func headingLeading(step: Int) -> Double {
        switch step {
        case ..<1: return 1.4
        case 1: return 1.3
        case 2: return 1.2
        case 3: return 1.15
        case 4: return 1.1
        default: return 1.05
        }
    }

    /// Whether `measure` sits in the comfortable band.
    static func isComfortable(_ measure: Int) -> Bool { comfortableMeasure.contains(measure) }

    // MARK: Measuring text

    /// The mean advance of a character of `text` in `font`, in points: the line's width over its character count.
    /// One zero is not one character, so the measure is counted with this.
    static func averageAdvance(of text: String, font: CTFont, trackingEm: Double = 0) -> Double {
        guard !text.isEmpty else { return 0 }
        let kern = trackingEm * Double(CTFontGetSize(font))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: kern]))
        return Double(CTLineGetTypographicBounds(line, nil, nil, nil)) / Double(text.count)
    }

    /// Width of one unbroken line of `text`, in points.
    static func lineWidth(_ text: String, font: CTFont, trackingEm: Double = 0) -> Double {
        let kern = trackingEm * Double(CTFontGetSize(font))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: kern]))
        return Double(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Column width for `measure` characters at this average advance.
    static func columnWidth(measure: Int, advance: Double) -> Double { Double(measure) * advance }

    /// The factor that brings a line of `width` into `available`: 1 when it fits. Only the preview shrinks; the sizes
    /// printed beside it never do.
    static func previewScale(width: Double, available: Double) -> Double {
        guard width > 0, available > 0 else { return 1 }
        return min(1, available / width)
    }
}

/// The steps Set shows, from the caption up to Display, on body x ratio^step (board 04).
enum ScaleStep: Int, CaseIterable, Identifiable {
    case caption = -1, body = 0, lead = 1, h3 = 2, h2 = 3, h1 = 4, display = 5
    var id: Int { rawValue }

    /// Display steps first, as the board lists them.
    static let stageOrder: [ScaleStep] = [.display, .h1, .h2, .h3, .lead, .body, .caption]

    /// Which face sets it: the Display face down to H3, the Text face from the lead line down.
    var isDisplayFace: Bool { rawValue >= ScaleStep.h3.rawValue }

    var label: String {
        switch self {
        case .display: Lexicon.SetScreen.stepDisplay
        case .h1: Lexicon.SetScreen.stepH1
        case .h2: Lexicon.SetScreen.stepH2
        case .h3: Lexicon.SetScreen.stepH3
        case .lead: Lexicon.SetScreen.stepLead
        case .body: Lexicon.SetScreen.stepBody
        case .caption: Lexicon.SetScreen.stepCaption
        }
    }
}
