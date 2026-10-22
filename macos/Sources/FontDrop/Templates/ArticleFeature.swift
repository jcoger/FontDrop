import SwiftUI

/// Article B, Feature. Tests: a reversed opener, a drop cap, two narrow columns, and a timetable in tabular figures.
struct ArticleFeature: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }
    /// Deck text on the dark opener: the background pulled a quarter of the way back toward the text color.
    private var deckColor: HexColor { p.text.mixed(with: p.background, amount: 0.73) }

    var body: some View {
        Board(background: p.background.color) {
            VStack(alignment: .leading, spacing: 0) {
                opener
                columns
            }
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var opener: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                ctx.label(TemplateCopy.featureKicker, color: p.background, weight: 400)
                Spacer()
                ctx.label(TemplateCopy.featureIssue, color: p.accent, weight: 400)
            }
            ctx.display(TemplateCopy.featureHeadline, 76, track: -0.035, lh: 0.92, color: p.background, width: 520)
            ctx.reading(TemplateCopy.featureDeck, 15, lh: 1.47, color: deckColor)
                .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.text.color)
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    ctx.display(TemplateCopy.featureDropCap, 64, lh: 0.875, color: p.accent)
                    ctx.reading(TemplateCopy.featureOpening, 15, lh: 1.53)
                }
                ctx.reading(TemplateCopy.featureSecond, 15, lh: 1.53)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
                ctx.reading(TemplateCopy.featureColumn, 15, lh: 1.53)
                timetable
                ctx.display(TemplateCopy.featureClosing, 18, lh: 1.33, italic: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40).padding(.top, 32)
    }

    /// Place left, time right. Tabular figures, so 06:40, 07:15 and 08:05 stand in one column.
    private var timetable: some View {
        VStack(spacing: 6) {
            ForEach(Array(TemplateCopy.timetable.enumerated()), id: \.offset) { _, row in
                HStack {
                    ctx.reading(row.0, 14, lh: 1.29, figures: .tabular)
                    Spacer()
                    ctx.reading(row.1, 14, lh: 1.29, figures: .tabular)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Hairline(color: p.text) }
        .overlay(alignment: .bottom) { Hairline(color: p.rule) }
    }
}
