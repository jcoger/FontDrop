import SwiftUI

/// Headline, deck, byline, two paragraphs and a pull quote.
struct ArticleTemplate: View {
    let ctx: PairContext

    static let descriptor = TemplateDescriptor(id: "article", title: "Article") { AnyView(ArticleTemplate(ctx: $0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ctx.headline(TemplateCopy.articleHeadline)
                .lineLimit(3).minimumScaleFactor(0.5)
            ctx.text(TemplateCopy.articleDeck, 1.15)
                .foregroundStyle(.secondary)
            ctx.text(TemplateCopy.byline, 0.8)
                .foregroundStyle(.tertiary)
            Divider().padding(.vertical, 2)
            ForEach(TemplateCopy.paragraphs, id: \.self) { ctx.text($0) }
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(.primary).frame(width: 2)
                ctx.headline(TemplateCopy.pullQuote, 0.55)
                    .lineLimit(3).minimumScaleFactor(0.6)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
