import SwiftUI

/// Developer switch for screenshots: draws the big numbers with tabular figures, to show what the default avoids.
/// Off in the app. `--tabular-display-figures` turns it on.
enum TemplateDebug {
    nonisolated(unsafe) static var tabularDisplayFigures = false
}

/// Hero B, Product. Tests: centered display at 64px, a badge, and big numbers in the Display face.
///
/// The numbers use proportional figures. With tabular figures on, PP Museum spaces its comma and
/// point as wide as a digit ("48 , 210", "4 . 9"). Display numbers stay proportional; tables and times
/// elsewhere in the templates use tabular.
struct HeroProduct: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }
    private var numberFigures: Figures { TemplateDebug.tabularDisplayFigures ? .tabular : .proportional }

    var body: some View {
        Board(background: p.ground.color, height: 640) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 22) {
                    badge
                    ctx.display(TemplateCopy.productHeadline, 64, track: -0.035, lh: 0.97, width: 520, align: .center, maxHeight: 240)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                    ctx.reading(TemplateCopy.productSub, 16, lh: 1.5, color: p.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    HStack(spacing: 8) {
                        ctx.button(TemplateCopy.productPrimary, filled: true, radius: 10, horizontal: 22)
                        ctx.button(TemplateCopy.productSecondary, filled: false, soft: true, radius: 10, horizontal: 22)
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 52)
                Spacer(minLength: 0)
                stats
            }
            .padding(.horizontal, 40).padding(.top, 28)
        }
    }

    private var badge: some View {
        HStack(spacing: 8) {
            Circle().fill(p.accent.color).frame(width: 6, height: 6)
            ctx.reading(TemplateCopy.productBadge, 13, lh: 1.23)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(p.background.color))
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(TemplateCopy.productStats.enumerated()), id: \.offset) { i, stat in
                HStack(spacing: 0) {
                    if i > 0 { VLine(color: p.rule).padding(.trailing, 20) }
                    VStack(alignment: .leading, spacing: 4) {
                        ctx.display(stat.0, 34, track: -0.02, lh: 1.24, figures: numberFigures).lineLimit(1)
                        ctx.reading(stat.1, 13, lh: 1.23, color: p.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 20).padding(.bottom, 24)
        .overlay(alignment: .top) { Hairline(color: p.rule) }
    }
}
