import SwiftUI

/// Article A, Essay. Tests: 17px body at a long measure, an italic standfirst, a pull quote with
/// hanging punctuation, a small-caps heading, figures in running text, and inline italic, bold and a link.
struct ArticleEssay: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    var body: some View {
        Board(background: p.background.color) {
            VStack(alignment: .leading, spacing: 0) {
                header
                paragraphs
                pullQuote
                section
            }
            .padding(.top, 56).padding(.horizontal, 64).padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            ctx.label(TemplateCopy.essayKicker, color: p.accent)
            ctx.display(TemplateCopy.essayHeadline, 44, track: -0.02, lh: 1.05)
            ctx.display(TemplateCopy.essayStandfirst, 20, lh: 1.4, italic: true, color: p.secondary)
            ctx.reading(TemplateCopy.essayByline, 13, lh: 1.4, color: p.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 28)
        .overlay(alignment: .bottom) { Hairline(color: p.rule) }
    }

    private var paragraphs: some View {
        VStack(alignment: .leading, spacing: 18) {
            ctx.rich([
                .plain("Good typography works the way good service does. You "), .italic("notice"),
                .plain(" it when it is missing. A line that breathes, "), .bold("a number that lines up"),
                .plain(", a heading that sits exactly where the eye expects it."),
            ], 17, lh: 1.6)
            ctx.rich([
                .plain("Start with one face you trust for long reading, then let a second face carry the headlines. "
                       + "The pair should feel decided, not accidental. Read more in "),
                .link("our notes on measure"), .plain("."),
            ], 17, lh: 1.6)
        }
        .padding(.top, 28)
    }

    /// The opening quote hangs in the margin: a zero-width slot that lets the mark sit left of the text edge.
    private var pullQuote: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ctx.display("\u{201C}", 30, track: -0.015, lh: 1.2)
                    .fixedSize().frame(width: 0, alignment: .trailing)
                    .accessibilityHidden(true)
                ctx.display(String(TemplateCopy.essayQuote.dropFirst()), 30, track: -0.015, lh: 1.2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TemplateCopy.essayQuote)
            ctx.label(TemplateCopy.essayQuoteBy, color: p.secondary, weight: 400)
        }
        .padding(.top, 32).padding(.bottom, 8)
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 12) {
            ctx.label(TemplateCopy.essayHeading, 13)
            ctx.reading(TemplateCopy.essayMeasure, 17, lh: 1.6)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ctx.reading(TemplateCopy.essayFigure, 14, lh: 1.43, italic: true, figures: .tabular, color: p.secondary)
                ctx.reading(TemplateCopy.essayFigureCaption, 14, lh: 1.43, italic: true, color: p.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.top, 24)
    }
}
