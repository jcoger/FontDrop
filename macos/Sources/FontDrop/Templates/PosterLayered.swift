import SwiftUI

/// Poster E, Layered. Tests: very large display type as a ghost, with a tabular list of times set over it.
/// On the Night preset this is the Paper board.
struct PosterLayered: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    var body: some View {
        Board(background: p.background.color, height: 750) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(TemplateCopy.layeredWord, id: \.self) { word in
                        ctx.display(word, 212, track: -0.05, lh: 0.86, color: p.ghost)
                            .lineLimit(1).fixedSize()
                            .frame(height: ctx.points(212, display: true) * 0.86, alignment: .leading)
                    }
                }
                .offset(x: -8, y: 40)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(TemplateCopy.layeredList.enumerated()), id: \.offset) { _, row in
                        ctx.reading("\(row.0) / \(row.1)", 13, lh: 1.31, weight: 600, figures: .tabular)
                            .lineLimit(1)
                    }
                }
                .offset(x: 250, y: 96)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        ctx.display(TemplateCopy.layeredFoot, 30, lh: 1.07, italic: true)
                        Spacer()
                        ctx.label(TemplateCopy.layeredStation, color: p.accent, weight: 400)
                    }
                    .padding(.top, 12)
                    .overlay(alignment: .top) { Hairline(color: p.ghost) }
                    .padding(.horizontal, 28).padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
    }
}
