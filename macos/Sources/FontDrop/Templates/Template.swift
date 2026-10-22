import SwiftUI

/// What a template receives: the brand name, the two faces with their playground settings, the
/// brand's three colors and which variant is showing. A template draws only from this, so it works
/// on Reading cards today and on Set later.
///
/// Sizes in templates are Paper pixels on a 600-wide board. `display(_:_:)` and `reading(_:_:)` turn a
/// board size into a role size relative to the playground's size, so moving the Size slider scales the
/// whole template.
struct PairContext {
    let brand: String
    let display: FaceSpec
    let body: FaceSpec
    let tick: Int
    var palette: TemplatePalette = .paper
    var variant: String = ""

    private static let displayBase = CGFloat(TypeSettings.defaults(job: "display").size)
    private static let readingBase = CGFloat(TypeSettings.defaults(job: "reading").size)

    /// Text in the Display face. `px` is the size on the board; `track` is the role's tracking in em,
    /// added to the playground's; `lh` is the role's line height as a multiple of the size.
    /// `width` is the width the text is laid out in (board pixels). Give it for display type tighter than the font's
    /// own spacing, so the lines can be set one by one. `align` is how those lines sit in that width.
    /// With `width` the type also shrinks, to a floor, until its longest word fits, so no word is ever split;
    /// `maxHeight` shrinks it until the lines fit that height too (a hero headline on a fixed board).
    /// `weight` and `italic` ask for a style (a label in semibold, a standfirst in italic). Left alone,
    /// the playground's weight is what you see. `italic` is only real: no italic in the family, no slant.
    func display(_ text: String, _ px: CGFloat, track: Double = 0, lh: Double? = nil, weight: Double? = nil,
                 italic: Bool = false, figures: Figures = .inherit, face: FaceSpec? = nil, color: HexColor? = nil,
                 width: CGFloat? = nil, align: HorizontalAlignment = .leading, maxHeight: CGFloat? = nil) -> some View {
        FaceText(face: Self.styled(face ?? display, weight: weight, italic: italic, figures: figures), text: text,
                 ratio: px / Self.displayBase, tick: tick, trackBias: track, leading: lh,
                 wrapWidth: width, lineAlignment: align, maxHeight: maxHeight)
            .foregroundStyle((color ?? palette.text).color)
    }

    /// Text in the Reading face. Same arguments as `display`.
    func reading(_ text: String, _ px: CGFloat, track: Double = 0, lh: Double? = nil, weight: Double? = nil,
                 italic: Bool = false, figures: Figures = .inherit, face: FaceSpec? = nil, color: HexColor? = nil,
                 width: CGFloat? = nil, align: HorizontalAlignment = .leading) -> some View {
        FaceText(face: Self.styled(face ?? body, weight: weight, italic: italic, figures: figures), text: text,
                 ratio: px / Self.readingBase, tick: tick, trackBias: track, leading: lh,
                 wrapWidth: width, lineAlignment: align)
            .foregroundStyle((color ?? palette.text).color)
    }

    /// A Reading paragraph with an italic word, a bold phrase or a link inside it.
    func rich(_ pieces: [Piece], _ px: CGFloat, lh: Double? = nil, color: HexColor? = nil) -> some View {
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
        return FaceParagraph(runs: runs, ratio: px / Self.readingBase, base: color ?? palette.text,
                             leading: lh ?? body.settings.lineHeight)
    }

    enum Piece { case plain(String), italic(String), bold(String), link(String) }

    /// The size a board size becomes after the playground's Size slider, in points. For hanging punctuation and the like.
    func points(_ px: CGFloat, display isDisplay: Bool) -> CGFloat {
        px / (isDisplay ? Self.displayBase : Self.readingBase) * CGFloat((isDisplay ? display : body).settings.size)
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
