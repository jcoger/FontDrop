import SwiftUI

/// A landing hero: brand, big headline, subhead, primary and secondary buttons, small print.
struct HeroTemplate: View {
    let ctx: PairContext

    static let descriptor = TemplateDescriptor(id: "hero", title: "Landing hero") { AnyView(HeroTemplate(ctx: $0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ctx.text(ctx.brand, 0.85).foregroundStyle(.secondary)
            ctx.headline(TemplateCopy.heroHeadline, 1.3)
                .lineLimit(4).minimumScaleFactor(0.5)
            ctx.text(TemplateCopy.heroSub, 1.1).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ctx.text(TemplateCopy.heroPrimary, 0.95)
                    .foregroundStyle(.background)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(.primary))
                ctx.text(TemplateCopy.heroSecondary, 0.95)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.5)))
            }
            ctx.text(TemplateCopy.heroSmall, 0.75).foregroundStyle(.tertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
