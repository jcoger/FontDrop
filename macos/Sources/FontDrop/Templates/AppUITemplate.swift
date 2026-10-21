import SwiftUI

/// App interface: a card with title, body and meta, a list of three rows, buttons and a labelled text field.
struct AppUITemplate: View {
    let ctx: PairContext

    static let descriptor = TemplateDescriptor(id: "appui", title: "App UI") { AnyView(AppUITemplate(ctx: $0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ctx.headline(TemplateCopy.cardTitle, 0.6).lineLimit(1).minimumScaleFactor(0.5)
                ctx.text(TemplateCopy.cardBody)
                ctx.text(TemplateCopy.cardMeta, 0.8).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))

            VStack(spacing: 0) {
                ForEach(Array(TemplateCopy.rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider() }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            ctx.text(row.0)
                            ctx.text(row.1, 0.8).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ctx.text(row.2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ctx.text(TemplateCopy.field, 0.8).foregroundStyle(.secondary)
                ctx.text(TemplateCopy.fieldValue)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.5)))
            }

            HStack(spacing: 8) {
                ctx.text("Save", 0.95)
                    .foregroundStyle(.background)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.primary))
                ctx.text("Cancel", 0.95)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.5)))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
