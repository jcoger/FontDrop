import SwiftUI

/// The Sort menu on the Display filter bar. It exists once a Text face is chosen: Your fonts first, or Pairs with that face.
struct DisplaySortMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.screen == .display, let text = model.readingFamily {
            Menu {
                Picker(Lexicon.sortLabel, selection: Binding(get: { model.displaySort }, set: { model.displaySortChoice = $0 })) {
                    Text(Lexicon.Pairs.sortPairsWith(text.name)).tag(AppModel.DisplaySort.pairsWith)
                    Text(Lexicon.Pairs.sortLibrary).tag(AppModel.DisplaySort.library)
                }
                .pickerStyle(.inline)
            } label: {
                Text("\(Lexicon.sortLabel) \u{00B7} " + (model.displaySort == .pairsWith ? Lexicon.Pairs.sortPairsWith(text.name) : Lexicon.Pairs.sortLibrary))
                    .font(.callout).lineLimit(1)
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help(Lexicon.Pairs.sortHelp)
        }
    }
}
