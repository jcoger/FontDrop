import FontDropCore
import SwiftUI

/// Above the Display grid, on one row: where the fonts come from, what kind they are, and a More menu for the rest.
/// The counts come from the core and already include every other filter, so they read as "what you would get".
/// They sit in the menu items and the segments' hover help, not on the surface (UX audit C4). Search and Sort sit
/// in the row above (DisplayTopRow).
struct FilterBar: View {
    var body: some View {
        // One row at any width: the kinds are a segmented control when there is room, a menu when the column is narrow
        // (the inspector open in a 1000 pt window leaves the grid about 400 pt).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                SourceMenu()
                KindControl()
                MoreMenu()
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                SourceMenu()
                KindMenu()
                MoreMenu()
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The narrow form of the kind control: the same choice, in a menu.
struct KindMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        let kinds = model.filter.kinds
        let value = kinds.count == 1 ? Lexicon.Finder.kindLabel(kinds.first!) : kinds.isEmpty ? Lexicon.Finder.kindAll : "\(kinds.count) kinds"
        Menu {
            Picker("Kind", selection: Binding(get: { kinds.count == 1 ? kinds.first : nil }, set: { model.filter.kinds = $0.map { [$0] } ?? [] })) {
                Text(Lexicon.Finder.kindAll).tag(Kind?.none)
                ForEach(Kind.all, id: \.self) { Text(Lexicon.Finder.kindLabel($0)).tag(Kind?.some($0)) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Text(value).font(.system(size: 13)).foregroundStyle(theme.textPrimary.color)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textSecondary.color)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .pill()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Kind").accessibilityValue(value)
    }
}

/// The scope menu: your fonts, Google Fonts, Mac system, and Saved. One pill that names what it shows.
struct SourceMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var model = model
        let counts = model.finderResults?.counts
        Menu {
            ForEach(Source.all, id: \.self) { source in
                Toggle(isOn: Binding(get: { model.filter.sources.contains(source) }, set: { on in
                    if on { model.filter.sources.insert(source) } else { model.filter.sources.remove(source) }
                })) {
                    Text(label(Lexicon.Finder.sourceLabel(source), counts?.sources.first { $0.source == source }.map { Int($0.count) }))
                }
            }
            Divider()
            Toggle(isOn: $model.filter.savedOnly) {
                Label(label(Lexicon.Finder.saved, counts.map { Int($0.saved) }), systemImage: "star")
            }
        } label: {
            HStack(spacing: 4) {
                Text(Lexicon.Finder.sourceMenuValue(model.filter.sources, savedOnly: model.filter.savedOnly))
                    .font(.system(size: 13)).foregroundStyle(theme.textPrimary.color)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textSecondary.color)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .pill()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(Lexicon.Finder.sourceMenuHelp)
        .accessibilityLabel(Lexicon.Reading.sourceLabel)
        .accessibilityValue(Lexicon.Finder.sourceMenuValue(model.filter.sources, savedOnly: model.filter.savedOnly))
    }

    private func label(_ title: String, _ count: Int?) -> String { count.map { "\(title)  \($0.formatted())" } ?? title }
}

/// One kind at a time, or All. A segmented control on the control ground (the selected segment is the one filled
/// capsule). Writes at most one kind into the filter. An older saved filter with several kinds shows no segment on.
struct KindControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        let counts = model.finderResults?.counts
        let kinds = model.filter.kinds
        HStack(spacing: 0) {
            segment(Lexicon.Finder.kindAll, help: Lexicon.Finder.kindAll, on: kinds.isEmpty) { model.filter.kinds = [] }
            ForEach(Kind.all, id: \.self) { kind in
                let n = counts?.kinds.first { $0.kind == kind }.map { Int($0.count) }
                segment(Lexicon.Finder.kindLabel(kind), help: Lexicon.Finder.kindHelp(Lexicon.Finder.kindLabel(kind), count: n),
                        on: kinds == [kind]) { model.filter.kinds = [kind] }
            }
        }
        .padding(2)
        .pill()
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kind")
    }

    private func segment(_ title: String, help: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13)).lineLimit(1)
                .padding(.horizontal, 11).padding(.vertical, 4)
                .background(Capsule().fill(on ? theme.textPrimary.color : .clear))
                .foregroundStyle(on ? theme.onPrimaryButton.color : theme.textSecondary.color)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// Style traits, Show hidden, and a way back to the standard filter.
struct MoreMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var model = model
        let counts = model.finderResults?.counts
        let active = model.filter.traits.count
        Menu {
            Section(Lexicon.Finder.traitsHeader) {
                ForEach(Trait.all, id: \.self) { trait in
                    Toggle(isOn: Binding(get: { model.filter.traits.contains(trait) }, set: { on in
                        if on { model.filter.traits.insert(trait) } else { model.filter.traits.remove(trait) }
                    })) {
                        Text(label(Lexicon.Finder.traitLabel(trait), counts?.traits.first { $0.tr == trait }?.count))
                    }
                }
            }
            Divider()
            Toggle(isOn: $model.filter.showHidden) {
                Text(label(Lexicon.Finder.showHidden, counts?.hidden))
            }
            if !model.filter.isStandard {
                Divider()
                Button(Lexicon.clearFilters) { model.filter = .standard }
            }
        } label: {
            HStack(spacing: 4) {
                Text(active > 0 ? "\(Lexicon.Finder.more) \u{00B7} \(active)" : Lexicon.Finder.more)
                    .font(.system(size: 13)).foregroundStyle(theme.textPrimary.color)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textSecondary.color)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .pill()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
        .help(Lexicon.Finder.moreHelp)
    }

    private func label(_ title: String, _ count: UInt32?) -> String {
        count.map { "\(title)  \($0.formatted())" } ?? title
    }
}

/// The star: Saved. Filled when on. Takes the family's state, holds none.
struct StarButton: View {
    @Environment(\.theme) private var theme
    let name: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "star.fill" : "star")
                .foregroundStyle(isOn ? theme.textPrimary.color : theme.textSecondary.color)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(isOn ? Lexicon.Finder.removeSaved : Lexicon.Finder.save)
        .accessibilityLabel(isOn ? "Remove \(name) from Saved" : "Save \(name)")
    }
}
