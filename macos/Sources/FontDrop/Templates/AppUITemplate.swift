import SwiftUI

/// App interface. A is a phone detail screen (rows of times and prices). B is a dashboard
/// (sidebar, a big figure, a table of amounts).
struct AppUITemplate: View {
    let ctx: PairContext

    static let descriptor = TemplateDescriptor(
        id: "appui", title: "App UI",
        variants: [TemplateVariant(id: "detail", title: "Detail"), TemplateVariant(id: "dashboard", title: "Dashboard")]
    ) { AnyView(AppUITemplate(ctx: $0)) }

    var body: some View {
        switch ctx.variant {
        case "dashboard": AppDashboard(ctx: ctx)
        default: AppDetail(ctx: ctx)
        }
    }
}
