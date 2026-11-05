import SwiftUI

/// Poster. A is an event, B a specimen, C a readout of the playground values, D colored blocks, E layered type.
/// Posters are fixed-size boards, like a printed sheet.
struct PosterTemplate: View {
    let ctx: PairContext

    static let descriptor = TemplateDescriptor(
        id: "poster", title: "Poster",
        variants: [
            TemplateVariant(id: "event", title: "Event"),
            TemplateVariant(id: "specimen", title: "Specimen"),
            TemplateVariant(id: "readout", title: "Readout"),
            TemplateVariant(id: "blocks", title: "Blocks"),
            TemplateVariant(id: "layered", title: "Layered"),
        ]
    ) { AnyView(PosterTemplate(ctx: $0)) }

    var body: some View {
        switch ctx.variant {
        case "specimen": PosterSpecimen(ctx: ctx)
        case "readout": PosterReadout(ctx: ctx)
        case "blocks": PosterBlocks(ctx: ctx)
        case "layered": PosterLayered(ctx: ctx)
        default: PosterEvent(ctx: ctx)
        }
    }
}

extension PairContext {
    /// One line of poster type, fitted to the width, with its own line box. Poster lines are tighter than
    /// the font's natural spacing, so each line is its own view with a fixed height.
    func posterLine(_ text: String, _ px: CGFloat, track: Double, lh: Double, italic: Bool = false,
                    color: HexColor? = nil) -> some View {
        display(text, px, track: track, italic: italic, color: color)
            .lineLimit(1).minimumScaleFactor(0.08)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: points(px, display: true) * lh)
    }
}
