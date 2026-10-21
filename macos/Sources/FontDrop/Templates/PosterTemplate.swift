import SwiftUI

/// Poster or editorial cover: very large display, a caption and numbers.
struct PosterTemplate: View {
    let ctx: PairContext

    static let descriptor = TemplateDescriptor(id: "poster", title: "Poster") { AnyView(PosterTemplate(ctx: $0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ctx.text(TemplateCopy.posterCaption, 0.8).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            ctx.headline(ctx.brand, 2.2)
                .lineLimit(2).minimumScaleFactor(0.25)
            Spacer(minLength: 8)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                ctx.headline("24", 1.2)
                Spacer()
                ctx.text(TemplateCopy.posterNumbers, 0.85).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 330, maxHeight: 330, alignment: .leading)
    }
}
