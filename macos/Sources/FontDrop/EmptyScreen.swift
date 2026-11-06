import SwiftUI

/// An empty state in the Instrument look: a recessed screen, a short Geist Mono label, and one plain line that says
/// what to do. No system ContentUnavailableView anywhere. Centred in whatever room it is given.
///
/// React: a flex-centred `<Well>` with a mono label, one paragraph and an optional link button.
struct EmptyScreen: View {
    @Environment(\.theme) private var theme
    let label: String
    let line: String
    var actionTitle: String?
    var actionHint: String?
    var actionHelp: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).moduleLabel()
            Text(line)
                .font(.system(size: 13)).foregroundStyle(theme.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                HStack(spacing: 8) {
                    Button(action: action) { Text(actionTitle) }
                        .buttonStyle(.themeLink).font(.system(size: 13))
                        .help(actionHelp ?? "")
                    if let actionHint { Text(actionHint).moduleLabel() }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: 280, alignment: .leading)
        .recessed(radius: 14)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
