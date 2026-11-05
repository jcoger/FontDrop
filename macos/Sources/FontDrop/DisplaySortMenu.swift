import SwiftUI

/// The Sort menu in the Display top row, beside Search. It exists once a Text face is chosen: Your fonts first, or Pairs with that face.
struct DisplaySortMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        if model.screen == .display, let text = model.readingFamily {
            Menu {
                Picker(Lexicon.sortLabel, selection: Binding(get: { model.displaySort }, set: { model.displaySortChoice = $0 })) {
                    Text(Lexicon.Pairs.sortPairsWith(text.name)).tag(AppModel.DisplaySort.pairsWith)
                    Text(Lexicon.Pairs.sortLibrary).tag(AppModel.DisplaySort.library)
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    (Text("\(Lexicon.sortLabel) \u{00B7} ").foregroundStyle(theme.textSecondary.color)
                     + Text(model.displaySort == .pairsWith ? Lexicon.Pairs.sortPairsWith(text.name) : Lexicon.Pairs.sortLibrary)
                        .foregroundStyle(theme.textPrimary.color))
                        .font(.system(size: 13)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textSecondary.color)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .pill()
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .fixedSize()
            .help(Lexicon.Pairs.sortHelp)
        }
    }
}
