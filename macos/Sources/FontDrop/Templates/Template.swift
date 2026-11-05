import CoreText
import SwiftUI

/// What a template receives: the brand name, the two faces with their playground settings, the
/// brand's three colors and which variant is showing. A template draws only from this, so it works
/// on Reading cards today and on Set later.
///
/// Sizes in templates are Paper pixels on a 600-wide board, as drawn for PP Museum over Timeless Sans.
/// `display(_:_:)` and `reading(_:_:)` turn a board size into the size to draw: Fit solves it from the font's own
/// metrics (TypeFit.swift), or, when the brand's scale is locked, `body x ratio^step` (TypeScale.swift). The face's
/// Trim then nudges it. Nothing multiplies a saved point size any more.
struct PairContext {
    let brand: String
    let display: FaceSpec
    let body: FaceSpec
    let tick: Int
    var palette: TemplatePalette = .paper
    var variant: String = ""

    /// The brand's scale. Unlocked (the default) templates fit their type to the font.
    var scale = TypeScale()
    /// Tests only: keeps every size a view solves, so a test can check them without reading pixels.
    var recorder: FitRecorder?

    /// The share of its full "fill the width" size that a poster's fill words keep, after the height the rest of the
    /// board leaves them (PosterFit.swift). 1 when they fit at full size.
    var fillFit: CGFloat = 1

    /// The shrink factor a fixed-size board sets so its display type fits (PosterFit.swift). 1 when nothing needs to shrink.
    var fit: CGFloat = 1

    private static let displayBase = CGFloat(TypeSettings.defaults(job: "display").size)
    private static let readingBase = CGFloat(TypeSettings.defaults(job: "reading").size)
    static var displayBaseSize: CGFloat { displayBase }
    static var readingBaseSize: CGFloat { readingBase }

    /// Text in the Display face. `px` is the size on the board; `track` is the role's tracking in em,
    /// added to the playground's; `lh` is the role's line height as a multiple of the size (raised, never lowered,
    /// until the lines of the real text clear each other).
    /// `width` is the width the text is laid out in (board pixels). Give it for display type tighter than the font's
    /// own spacing, so the lines can be set one by one. `align` is how those lines sit in that width.
    /// With `width` the type also shrinks, to a floor, until its longest word fits, so no word is ever split;
    /// `maxHeight` shrinks it until the lines fit that height too (a hero headline on a fixed board).
    /// `lines` (with `width`) makes it a headline: Fit picks the largest size that sets in that many lines and fills the
    /// column. Without it, Fit matches the board's cap height. `step` is the role's place on the scale when it is
    /// locked (label -1, body 0, deck +1, headline about +5); left out, it comes from `px`.
    /// `weight` and `italic` ask for a style (a label in semibold, a standfirst in italic). Left alone,
    /// the playground's weight is what you see. `italic` is only real: no italic in the family, no slant.
    func display(_ text: String, _ px: CGFloat, track: Double = 0, lh: Double? = nil, weight: Double? = nil,
                 italic: Bool = false, figures: Figures = .inherit, face: FaceSpec? = nil, color: HexColor? = nil,
                 width: CGFloat? = nil, align: HorizontalAlignment = .leading, maxHeight: CGFloat? = nil,
                 lines: ClosedRange<Int>? = nil, step: Int? = nil, exactSize: CGFloat? = nil) -> some View {
        let spec = Self.styled(face ?? display, weight: weight, italic: italic, figures: figures)
        // `exactSize` is a size the caller solved itself (a poster word that fills its width).
        let size = exactSize ?? solve(text, spec, px: px, isDisplay: true, track: track, lh: lh, step: step,
                                      width: width, lines: lines, maxHeight: maxHeight)
        return FaceText(face: spec, text: text, ratio: size / CGFloat(spec.settings.size), tick: tick, trackBias: track, leading: lh,
                        wrapWidth: width, lineAlignment: align, maxHeight: maxHeight, exactLines: lines != nil)
            .foregroundStyle((color ?? palette.text).color)
    }

    /// A template's main headline, from its declared spec (see `HeadlineSpec`).
    func headline(_ spec: HeadlineSpec, figures: Figures = .inherit, color: HexColor? = nil, align: HorizontalAlignment = .leading) -> some View {
        display(spec.text, spec.px, track: spec.track, lh: spec.lh, figures: figures, color: color, width: spec.width, align: align,
                maxHeight: spec.maxHeight, lines: spec.width == nil ? nil : spec.lines)
    }

    /// Text in the Reading face. Same arguments as `display`; Fit matches the board's x-height.
    @ViewBuilder
    func reading(_ text: String, _ px: CGFloat, track: Double = 0, lh: Double? = nil, weight: Double? = nil,
                 italic: Bool = false, figures: Figures = .inherit, face: FaceSpec? = nil, color: HexColor? = nil,
                 width: CGFloat? = nil, align: HorizontalAlignment = .leading, step: Int? = nil,
                 measure: CGFloat? = nil, maxMeasure: CGFloat? = nil) -> some View {
        let spec = Self.styled(face ?? body, weight: weight, italic: italic, figures: figures)
        let size = solve(text, spec, px: px, isDisplay: false, track: track, lh: lh, step: step,
                         width: width, lines: nil, maxHeight: nil, measure: measure, maxMeasure: maxMeasure)
        // `measure` is the column the text sits in. In a wide face the column may widen, up to `maxMeasure`, to keep a readable line.
        let column = measure.map { m in
            TypeFit.measure(text, face: spec, size: size, floorSize: size, locked: true, column: m, maxColumn: maxMeasure ?? m)?.column ?? m
        }
        let drawn = FaceText(face: spec, text: text, ratio: size / CGFloat(spec.settings.size), tick: tick, trackBias: track, leading: lh,
                             wrapWidth: width, lineAlignment: align)
            .foregroundStyle((color ?? palette.text).color)
        if let column { drawn.frame(width: column, alignment: .leading) } else { drawn }
    }

    /// A Reading paragraph with an italic word, a bold phrase or a link inside it.
    func rich(_ pieces: [Piece], _ px: CGFloat, lh: Double? = nil, color: HexColor? = nil, step: Int? = nil) -> some View {
        let italicFace = body.italic() ?? body
        let boldFace = body.weighted(max(700, body.weightValue + 300))
        let runs = pieces.map { piece -> TextRun in
            switch piece {
            case .plain(let t): TextRun(text: t, face: body)
            case .italic(let t): TextRun(text: t, face: italicFace)
            case .bold(let t): TextRun(text: t, face: boldFace)
            case .link(let t): TextRun(text: t, face: body, color: palette.accent, underline: true)
            }
        }
        let size = solve(runs.map(\.text).joined(), body, px: px, isDisplay: false, track: 0, lh: lh, step: step,
                         width: nil, lines: nil, maxHeight: nil)
        return FaceParagraph(runs: runs, ratio: size / CGFloat(body.settings.size), base: color ?? palette.text,
                             leading: lh ?? body.settings.lineHeight)
    }

    enum Piece { case plain(String), italic(String), bold(String), link(String) }

    /// The size a board size becomes, in points: for hanging punctuation, line boxes and the like.
    /// Same answer as `display`/`reading` give a single line with no width.
    func points(_ px: CGFloat, display isDisplay: Bool, italic: Bool = false, step: Int? = nil) -> CGFloat {
        let spec = isDisplay ? Self.styled(display, weight: nil, italic: italic, figures: .inherit) : body
        return roleSize(spec, px: px, isDisplay: isDisplay, step: step).size * CGFloat(spec.settings.trim) * (isDisplay ? fit : 1)
    }

    /// What a board size becomes as a multiple of itself, before the board's own shrink. Boards use it to size their
    /// boxes: the poster fit counts lines at the size a role really draws at.
    func displayFactor(_ px: CGFloat, step: Int? = nil) -> CGFloat {
        px > 0 ? roleSize(display, px: px, isDisplay: true, step: step).size * CGFloat(display.settings.trim) / px : 1
    }

    func readingFactor(_ px: CGFloat, step: Int? = nil) -> CGFloat {
        px > 0 ? roleSize(body, px: px, isDisplay: false, step: step).size * CGFloat(body.settings.trim) / px : 1
    }

    // MARK: Poster words

    /// The size, in points, at which the widest of `fill.words` sets `fill.share` of `fill.width` on one line. A locked
    /// scale sets it by step instead. Includes Trim; never past a third of the board size above or below.
    func fillSize(_ fill: FillSpec, px: CGFloat, track: Double, italic: Bool) -> CGFloat {
        let face = Self.styled(display, weight: nil, italic: italic, figures: .inherit)
        let trim = CGFloat(face.settings.trim)
        if scale.locked { return roleSize(face, px: px, isDisplay: true, step: nil).size * trim }
        guard let font = FontLoader.shared.styledFont(face, ratio: 100 / CGFloat(face.settings.size)) else { return px * trim }
        let tracking = CGFloat(face.settings.tracking + track) * 100
        let widest = fill.words.map { TypeFit.lineWidth($0, font: font, tracking: tracking) }.max() ?? 0
        guard widest > 0 else { return px * trim }
        return min(max(fill.width * fill.share / widest * 100, px * 0.4), px * 3) * trim
    }

    /// One poster word, set to fill its width, on one line that is never scaled down by SwiftUI (a speck or a clipped
    /// edge in place of the word). The board has already shrunk `fillFit` and `fit` to the height it has.
    @ViewBuilder
    func posterWord(_ text: String, _ px: CGFloat, track: Double, lh: Double, fill: FillSpec, italic: Bool = false,
                    color: HexColor? = nil) -> some View {
        let spec = Self.styled(display, weight: nil, italic: italic, figures: .inherit)
        let size = scale.locked
            ? roleSize(spec, px: px, isDisplay: true, step: nil).size * CGFloat(spec.settings.trim) * fit
            : fillSize(fill, px: px, track: track, italic: italic) * fillFit * fit
        // The word's box is its ink: the top of the tallest letter at the box's top, the bottom of the deepest descender at
        // its bottom (or the line height, when that is more). So a descender never reaches the line under it, and the
        // top never reaches the bars above it, whatever line box SwiftUI gives the text.
        let ink = inkBox(text, spec, size: size, track: track)
        let frameHeight = max(size * CGFloat(lh), ink.above + ink.below)
        let _ = recordFill(text, spec, px: px, size: size, track: track, fill: fill, ink: ink, frameHeight: frameHeight)
        display(text, px, track: track, italic: italic, color: color, exactSize: size)
            .lineLimit(1).fixedSize()
            .alignmentGuide(.top) { d in d[.firstTextBaseline] - ink.above }
            .frame(maxWidth: .infinity, minHeight: frameHeight, maxHeight: frameHeight, alignment: .topLeading)
    }

    /// How far the word's ink reaches above and below its baseline, in points.
    func inkBox(_ text: String, _ face: FaceSpec, size: CGFloat, track: Double) -> (above: CGFloat, below: CGFloat) {
        guard let font = FontLoader.shared.styledFont(face, ratio: size / CGFloat(face.settings.size)) else { return (size * 0.75, size * 0.25) }
        return TypeFit.ink(text, font: font, tracking: CGFloat(face.settings.tracking + track) * size)
    }

    private func recordFill(_ text: String, _ face: FaceSpec, px: CGFloat, size: CGFloat, track: Double, fill: FillSpec,
                            ink: (above: CGFloat, below: CGFloat), frameHeight: CGFloat) {
        guard let recorder, let font = FontLoader.shared.styledFont(face, ratio: size / CGFloat(face.settings.size)) else { return }
        let w = TypeFit.lineWidth(text, font: font, tracking: CGFloat(face.settings.tracking + track) * size)
        recorder.add(FitRecord(kind: .display, text: text, px: px, size: size, clamped: false, width: fill.width, lines: [text],
                               lineWidths: [w], fill: w / fill.width, heightLimited: fillFit < 0.999, capped: false,
                               xTarget: nil, xActual: nil, tracking: face.settings.tracking + track, pitch: nil, need: nil,
                               charsPerLine: nil, fillWord: true, inkHeight: ink.above + ink.below, frameHeight: frameHeight))
    }

    // MARK: Solving

    /// Fit or locked size of a role with no column, in board points, before Trim and the board's shrink.
    private func roleSize(_ face: FaceSpec, px: CGFloat, isDisplay: Bool, step: Int?) -> TypeFit.Solved {
        if scale.locked { return .init(size: CGFloat(scale.size(step: step ?? TypeScale.defaultStep(px: px)))) }
        return isDisplay ? TypeFit.displaySize(face, px: px) : TypeFit.readingSize(face, px: px)
    }

    /// The size to draw `text` at, in points. Also records what it solved, when a test asked for that.
    private func solve(_ text: String, _ face: FaceSpec, px: CGFloat, isDisplay: Bool, track: Double, lh: Double?, step: Int?,
                       width: CGFloat?, lines: ClosedRange<Int>?, maxHeight: CGFloat?,
                       measure: CGFloat? = nil, maxMeasure: CGFloat? = nil) -> CGFloat {
        let trim = CGFloat(face.settings.trim)
        let shrink = isDisplay ? fit : 1
        let tracking = face.settings.tracking + track
        // A headline: the largest size that sets in its line range and fills the column.
        if let width, let lines, isDisplay {
            let leading = lh ?? face.settings.lineHeight
            let solved: (size: CGFloat, clamped: Bool, result: TypeFit.Headline?)
            if scale.locked {
                // Locked: the scale sets the size. A word wider than the column or lines taller than maxHeight still shrink it.
                var size = CGFloat(scale.size(step: step ?? TypeScale.defaultStep(px: px)))
                if let base = FontLoader.shared.styledFont(face, ratio: 1) {
                    size *= FitWords.scale(text: text, font: CTFontCreateCopyWithAttributes(base, size, nil, nil), trackingEm: tracking,
                                           width: width, leading: leading, maxHeight: maxHeight)
                }
                solved = (size, false, nil)
            } else if let h = TypeFit.fitHeadline(text, face: face, px: px, trackingEm: tracking, lh: leading, width: width,
                                                  lines: lines, maxHeight: maxHeight) {
                solved = (h.size, false, h)
            } else {
                solved = (px, false, nil)
            }
            let size = solved.size * trim * shrink
            if let recorder {
                let set = TypeFit.set(text, face: face, size: size, trackingEm: tracking, width: width, lh: leading)
                recorder.add(FitRecord(kind: .headline, text: text, px: px, size: size, clamped: false, width: width,
                                       lines: set?.lines ?? [], lineWidths: set?.lineWidths ?? [], fill: set?.fill,
                                       heightLimited: solved.result?.heightLimited ?? false, capped: solved.result?.capped ?? false,
                                       xTarget: nil, xActual: nil, tracking: tracking, pitch: set?.pitch, need: set?.need))
            }
            return size
        }
        var r = roleSize(face, px: px, isDisplay: isDisplay, step: step)
        var size = r.size * trim * shrink
        // Reading text in a narrow column needs a readable line: at least 18 characters. Smaller type (to 0.65x) first.
        var chars: CGFloat?
        if let measure, !isDisplay,
           let m = TypeFit.measure(text, face: face, size: size, floorSize: px * TypeFit.measureFloor * trim, locked: scale.locked,
                                   column: measure, maxColumn: maxMeasure ?? measure) {
            if m.size < size - 0.001 { r.clamped = true }
            size = m.size
            chars = m.chars
        }
        if let recorder {
            let m = TypeFit.metrics(face)
            let set = width.flatMap { TypeFit.set(text, face: face, size: size, trackingEm: tracking, width: $0, lh: lh ?? face.settings.lineHeight) }
            recorder.add(FitRecord(kind: isDisplay ? .display : .reading, text: text, px: px, size: size, clamped: r.clamped,
                                   width: width, lines: set?.lines ?? [], lineWidths: set?.lineWidths ?? [], fill: set?.fill,
                                   heightLimited: false, capped: false,
                                   xTarget: isDisplay ? nil : px * TypeFit.refXHeight * trim,
                                   xActual: isDisplay ? nil : size * (m?.xHeight ?? 0),
                                   tracking: tracking, pitch: set?.pitch, need: set?.need, charsPerLine: chars))
        }
        return size
    }

    private static func styled(_ face: FaceSpec, weight: Double?, italic: Bool, figures: Figures) -> FaceSpec {
        var f = face
        if let weight { f = f.weighted(weight) }
        if italic, let i = f.italic() { f = i }
        return f.figures(figures)
    }
}

/// One way to lay a template out: Essay and Feature for Article, and so on.
struct TemplateVariant: Identifiable, Hashable {
    let id: String
    let title: String
}

/// One presentation template: a name, its variants and a function from context to a view.
///
/// To add a template: create one file per variant in this folder, a small `View` that takes a
/// `PairContext`. Then one file for the template itself with a `static let descriptor` that switches on
/// `ctx.variant`, and add that descriptor to `Templates.all`.
/// React: a registry of `{ id, label, variants, render }` entries.
struct TemplateDescriptor: Identifiable {
    let id: String
    let title: String
    let variants: [TemplateVariant]
    let make: (PairContext) -> AnyView

    /// The same template with the brand's colors and the chosen variant filled in.
    func configured(palette: TemplatePalette, variant: String) -> TemplateDescriptor {
        let inner = make
        return TemplateDescriptor(id: id, title: title, variants: variants) { ctx in
            var c = ctx
            c.palette = palette
            c.variant = variant
            return inner(c)
        }
    }
}

enum Templates {
    static let all: [TemplateDescriptor] = [
        ArticleTemplate.descriptor,
        HeroTemplate.descriptor,
        AppUITemplate.descriptor,
        PosterTemplate.descriptor,
    ]

    static func descriptor(_ id: String) -> TemplateDescriptor { all.first { $0.id == id } ?? all[0] }
}

/// Short sample copy for playground previews and the Set placeholder. Neutral on purpose.
enum SampleCopy {
    static let paragraphs = [
        "Book a table for four and we hold it until you arrive. Your name is on the list, the kitchen knows, and the first round is already poured.",
        "They know the window seat is yours and the music stays low. Nothing to confirm, nothing to repeat.",
    ]
    static let displayHeadline = "Good things, held warm."
    /// What a Reading list row sets in each candidate's face.
    static let rowText = "Good typography works the way good service does. You notice it when it is missing."

}

extension PairContext {
    /// What the template on stage solves to, in board points: its main headline and its body text, with Trim.
    /// `headlineStep` is where the headline sits on the scale. The Scale readout and the lock start from these.
    func solvedSizes(_ anchor: TemplateAnchors.Anchor) -> (headline: Double, body: Double, headlineStep: Int) {
        let spec = anchor.headline
        let step = TypeScale.defaultStep(px: spec.px)
        var head: CGFloat
        if scale.locked {
            head = CGFloat(scale.size(step: step))
        } else if let width = spec.width,
                  let h = TypeFit.fitHeadline(spec.text, face: display, px: spec.px, trackingEm: display.settings.tracking + spec.track,
                                              lh: spec.lh, width: width, lines: spec.lines, maxHeight: spec.maxHeight) {
            head = h.size
        } else {
            head = roleSize(display, px: spec.px, isDisplay: true, step: nil).size
        }
        head *= CGFloat(display.settings.trim)
        let bodySize = roleSize(body, px: anchor.bodyPx, isDisplay: false, step: nil).size * CGFloat(body.settings.trim)
        return (Double(head), Double(bodySize), step)
    }
}
