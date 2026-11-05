import SwiftUI

/// Hero A, Statement. Tests: display type at 88px, tracked tight, beside 14px nav and buttons.
struct HeroStatement: View {
    let ctx: PairContext

    /// 88px on the board, 2 lines in a 520 column (as drawn for PP Museum), never taller than 380.
    static let headline = HeadlineSpec(text: TemplateCopy.statementHeadline, px: 88, track: -0.04, lh: 0.91, width: 520,
                                       lines: 2...2, maxHeight: 380)
    private var p: TemplatePalette { ctx.palette }

    var body: some View {
        Board(background: p.background.color, height: 640) {
            VStack(alignment: .leading, spacing: 0) {
                nav
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 28) {
                    ctx.headline(Self.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Side by side as drawn. When the buttons of a wide face leave the line too little room, they drop under it.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 0) {
                            sub
                            Spacer(minLength: 24)
                            buttons
                        }
                        VStack(alignment: .leading, spacing: 20) {
                            sub
                            buttons
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
        }
    }

    /// 260 wide as drawn. A wide face keeps 18 characters a line by widening it, up to 320.
    private var sub: some View {
        ctx.reading(TemplateCopy.statementSub, 16, lh: 1.5, color: p.secondary, measure: 260, maxMeasure: 320)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            ctx.button(TemplateCopy.statementPrimary, filled: true)
            ctx.button(TemplateCopy.statementSecondary, filled: false)
        }
        .fixedSize()
    }

    private var nav: some View {
        HStack {
            ctx.display(ctx.brand, 20, track: -0.01, lh: 1.2).lineLimit(1).minimumScaleFactor(0.15)
            Spacer()
            HStack(spacing: 24) {
                ForEach(Array(TemplateCopy.nav.enumerated()), id: \.offset) { i, item in
                    ctx.reading(item, 14, lh: 1.29, color: i == TemplateCopy.nav.count - 1 ? p.text : p.secondary)
                }
            }
        }
    }
}
