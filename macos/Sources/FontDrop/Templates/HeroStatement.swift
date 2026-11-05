import SwiftUI

/// Hero A, Statement. Tests: display type at 88px, tracked tight, beside 14px nav and buttons.
struct HeroStatement: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    var body: some View {
        Board(background: p.background.color, height: 640) {
            VStack(alignment: .leading, spacing: 0) {
                nav
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 28) {
                    ctx.display(TemplateCopy.statementHeadline, 88, track: -0.04, lh: 0.91, width: 520)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .bottom, spacing: 32) {
                        ctx.reading(TemplateCopy.statementSub, 16, lh: 1.5, color: p.secondary)
                            .frame(maxWidth: 260, alignment: .leading)
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            ctx.button(TemplateCopy.statementPrimary, filled: true)
                            ctx.button(TemplateCopy.statementSecondary, filled: false)
                        }
                        .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
        }
    }

    private var nav: some View {
        HStack {
            ctx.display(ctx.brand, 20, track: -0.01, lh: 1.2).lineLimit(1)
            Spacer()
            HStack(spacing: 24) {
                ForEach(Array(TemplateCopy.nav.enumerated()), id: \.offset) { i, item in
                    ctx.reading(item, 14, lh: 1.29, color: i == TemplateCopy.nav.count - 1 ? p.text : p.secondary)
                }
            }
        }
    }
}
