import SwiftUI

/// Article: a long read. A is an essay (one column, a pull quote, a figure). B is a magazine feature
/// (reversed opener, drop cap, two columns, a timetable).
struct ArticleTemplate: View {
    let ctx: PairContext

    static let descriptor = TemplateDescriptor(
        id: "article", title: "Article",
        variants: [TemplateVariant(id: "essay", title: "Essay"), TemplateVariant(id: "feature", title: "Feature")]
    ) { AnyView(ArticleTemplate(ctx: $0)) }

    var body: some View {
        switch ctx.variant {
        case "feature": ArticleFeature(ctx: ctx)
        default: ArticleEssay(ctx: ctx)
        }
    }
}
