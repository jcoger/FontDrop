import SwiftUI

/// Landing hero. A is a statement (display type at 88px next to small nav and buttons).
/// B is a product page (centered display, a badge, big numbers).
struct HeroTemplate: View {
    let ctx: PairContext

    static let descriptor = TemplateDescriptor(
        id: "hero", title: "Landing hero",
        variants: [TemplateVariant(id: "statement", title: "Statement"), TemplateVariant(id: "product", title: "Product")]
    ) { AnyView(HeroTemplate(ctx: $0)) }

    var body: some View {
        switch ctx.variant {
        case "product": HeroProduct(ctx: ctx)
        default: HeroStatement(ctx: ctx)
        }
    }
}
