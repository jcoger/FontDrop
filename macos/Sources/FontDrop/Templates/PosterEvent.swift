import SwiftUI

/// Poster A, Event. Tests: the Display face at 232px on a color field, and a date as display type.
/// On the Signal preset this is the Paper board: a red field, black type.
struct PosterEvent: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    /// The fit rule (PosterFit.swift): at a large Display size the whole board's display type shrinks until it fits.
    init(ctx base: PairContext) {
        var items = TemplateCopy.eventTitle.map { FitItem(text: $0, px: 232, lh: 0.82, tracking: -0.05) }
        items.append(FitItem(text: TemplateCopy.eventLine, px: 30, lh: 1.13, width: 420))
        items.append(FitItem(text: TemplateCopy.eventDate, px: 64, lh: 0.88, tracking: -0.03))
        // Padding 68, the two top lines, the gap above the date row, its rule, and a little air between the groups.
        let fixed = 68 + 36.4 * base.readingScale + 18 + 18 + 24
        ctx = base.fitted(height: 800, fixed: fixed, items: items)
    }

    var body: some View {
        Board(background: p.background.color, height: 800) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    lines(TemplateCopy.eventLeft, alignment: .leading)
                    Spacer()
                    lines(TemplateCopy.eventRight, alignment: .trailing)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(TemplateCopy.eventTitle, id: \.self) { ctx.posterLine($0, 232, track: -0.05, lh: 0.82) }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 18) {
                    ctx.display(TemplateCopy.eventLine, 30, lh: 1.13, italic: true, width: 420)
                        .frame(maxWidth: 420, alignment: .leading)
                    HStack(alignment: .bottom) {
                        ctx.display(TemplateCopy.eventDate, 64, track: -0.03, lh: 0.88, figures: .proportional)
                            .lineLimit(1).minimumScaleFactor(0.12)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(TemplateCopy.eventPlace, id: \.self) { ctx.reading($0, 13, lh: 1.4) }
                        }
                    }
                    .padding(.top, 16)
                    .overlay(alignment: .top) { Hairline(color: p.text, weight: 2) }
                }
            }
            .padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 36)
        }
    }

    private func lines(_ list: [String], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            ForEach(list, id: \.self) { ctx.reading($0, 13, lh: 1.4, weight: 500) }
        }
    }
}
