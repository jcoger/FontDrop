import SwiftUI

/// An empty state. On a stage or a page: a large specimen, one title, one line, one action. The specimen is the brand's
/// own Display face when there is one, and the app's dot-matrix mark when there is not. In a panel (`compact`) it is one
/// quiet line. No container: the room it sits in is the frame.
///
/// React: a flex-centred column with an optional specimen, a heading, a paragraph and one button.
struct EmptyScreen: View {
    @Environment(\.theme) private var theme
    let label: String
    let line: String
    var actionTitle: String?
    var actionHint: String?
    var actionHelp: String?
    var action: (() -> Void)?
    var specimen: FaceSpec?
    var tick = 0
    var compact = false

    var body: some View {
        Group { if compact { small } else { large } }
            .padding(Metrics.lane)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
    }

    private var small: some View {
        VStack(spacing: 10) {
            Text(line).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            button
        }
        .frame(maxWidth: 240)
    }

    private var large: some View {
        VStack(spacing: 0) {
            mark.padding(.bottom, 20).accessibilityHidden(true)
            Text(label).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.textPrimary.color)
                .multilineTextAlignment(.center)
            Text(line).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            button.padding(.top, 18)
        }
        .frame(maxWidth: 320)
    }

    @ViewBuilder private var mark: some View {
        if let specimen {
            FaceText(face: specimen, text: "Aa", ratio: 120 / max(CGFloat(specimen.settings.size), 1), tick: tick, useLineHeight: false)
                .lineLimit(1).fixedSize()
                .foregroundStyle(theme.textPrimary.color)
        } else {
            Text("Aa").font(InstrumentFonts.doto(112)).foregroundStyle(theme.textSecondary.color.opacity(0.55))
        }
    }

    @ViewBuilder private var button: some View {
        if let actionTitle, let action {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(actionTitle)
                    if let actionHint { Text(actionHint).foregroundStyle(theme.textSecondary.color) }
                }
            }
            .buttonStyle(GlassButtonStyle())
            .help(actionHelp ?? "")
        }
    }
}
