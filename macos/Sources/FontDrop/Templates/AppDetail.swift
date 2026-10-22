import SwiftUI

/// App UI A, Detail. Tests: a phone screen of 13 to 15px rows, with times and prices that must line up.
/// Times and prices use tabular figures. The title is Display type.
struct AppDetail: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    var body: some View {
        Board(background: p.ground.color) {
            phone
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
        }
    }

    private var phone: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                ctx.reading(TemplateCopy.phoneTime, 13, lh: 1.23, weight: 600, figures: .tabular)
                Spacer()
                ctx.reading(TemplateCopy.phoneTab, 13, lh: 1.23, figures: .tabular, color: p.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ctx.label(TemplateCopy.detailDates, color: p.secondary)
                ctx.display(TemplateCopy.detailTitle, 34, track: -0.02, lh: 1.06, width: 300)
                    .lineLimit(2).minimumScaleFactor(0.5)
            }
            VStack(spacing: 0) {
                ForEach(Array(TemplateCopy.detailRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            ctx.reading(row.title, 15, lh: 1.2, weight: 500)
                            ctx.reading(row.sub, 13, lh: 1.23, color: row.flagged ? p.accent : p.secondary)
                        }
                        Spacer(minLength: 8)
                        ctx.reading(row.value, 15, lh: 1.2, figures: .tabular)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Hairline(color: p.rule) }
                }
                HStack(alignment: .firstTextBaseline) {
                    ctx.label(TemplateCopy.detailTotal, 13)
                    Spacer()
                    ctx.reading(TemplateCopy.detailTotalValue, 17, lh: 1.3, weight: 600, figures: .tabular)
                }
                .padding(.top, 14)
                .overlay(alignment: .top) { Hairline(color: p.text) }
            }
            HStack(spacing: 8) {
                ctx.button(TemplateCopy.detailShare, px: 15, filled: true, radius: 12, vertical: 13)
                    .frame(maxWidth: .infinity)
                ctx.reading(TemplateCopy.detailEdit, 15, weight: 500)
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(p.ground.color))
            }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 32).fill(p.background.color))
        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 12)
    }
}
