import SwiftUI

/// App UI B, Dashboard. Tests: sidebar labels, a big figure in Display type, and a table of amounts.
/// The big figure is proportional. The table is tabular and right-aligned, so the amounts line up.
struct AppDashboard: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    var body: some View {
        Board(background: p.background.color) {
            HStack(alignment: .top, spacing: 0) {
                sidebar
                main
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ctx.display(ctx.brand, 18, lh: 1.22).lineLimit(1)
                .padding(.horizontal, 8).padding(.bottom, 16)
            ForEach(Array(TemplateCopy.sidebarItems.enumerated()), id: \.offset) { i, item in
                let active = i == 0
                ctx.reading(item, 13, lh: 1.23, weight: active ? 500 : nil, color: active ? p.text : p.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(active ? p.background.color : .clear))
                    .overlay(alignment: .leading) {
                        if active { Rectangle().fill(p.accent.color).frame(width: 2).clipShape(RoundedRectangle(cornerRadius: 1)) }
                    }
            }
            ctx.label(TemplateCopy.sidebarGroup, 11, color: p.secondary)
                .padding(.horizontal, 8).padding(.top, 18).padding(.bottom, 6)
            ForEach(TemplateCopy.sidebarHouses, id: \.self) { house in
                ctx.reading(house, 13, lh: 1.23, color: p.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24).padding(.horizontal, 12)
        .frame(width: 150)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(p.ground.color)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                ctx.reading(TemplateCopy.dashboardTitle, 15, lh: 1.2, weight: 600)
                Spacer()
                ctx.reading(TemplateCopy.dashboardMonth, 13, lh: 1.23)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.rule.color))
            }
            VStack(alignment: .leading, spacing: 4) {
                ctx.reading(TemplateCopy.dashboardLabel, 13, lh: 1.23, color: p.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ctx.display(TemplateCopy.dashboardRevenue, 48, track: -0.03, lh: 1.04, figures: .proportional)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    ctx.reading(TemplateCopy.dashboardDelta, 13, lh: 1.23, weight: 500, figures: .tabular)
                }
            }
            table
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var table: some View {
        VStack(spacing: 0) {
            row(TemplateCopy.dashboardHeaders[0], TemplateCopy.dashboardHeaders[1], TemplateCopy.dashboardHeaders[2],
                px: 12, color: p.secondary).padding(.bottom, 8)
            ForEach(Array(TemplateCopy.dashboardRows.enumerated()), id: \.offset) { _, r in
                row(r.0, r.1, r.2, px: 13, color: p.text).padding(.vertical, 9)
                    .overlay(alignment: .top) { Hairline(color: p.rule) }
            }
        }
    }

    private func row(_ a: String, _ b: String, _ c: String, px: CGFloat, color: HexColor) -> some View {
        HStack(spacing: 0) {
            ctx.reading(a, px, lh: 1.23, figures: .tabular, color: color).frame(maxWidth: .infinity, alignment: .leading)
            ctx.reading(b, px, lh: 1.23, figures: .tabular, color: color).frame(width: 50, alignment: .trailing)
            ctx.reading(c, px, lh: 1.23, figures: .tabular, color: color).frame(width: 80, alignment: .trailing)
        }
    }
}
