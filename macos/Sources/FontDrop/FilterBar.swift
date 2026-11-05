import FontDropCore
import SwiftUI

/// Above the Display grid: where the fonts come from, what kind they are, and a More menu for the rest.
/// The counts come from the core and already include every other filter, so a chip reads
/// "Your fonts 376" for what you would get. Search is the toolbar's field.
struct FilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let counts = model.finderResults?.counts
        FlowLayout(spacing: 8) {
            ForEach(Source.all, id: \.self) { source in
                FilterChip(title: Lexicon.Finder.sourceLabel(source),
                           count: counts?.sources.first { $0.source == source }.map { Int($0.count) },
                           isOn: model.filter.sources.contains(source)) {
                    toggle(&model.filter.sources, source)
                }
            }
            ForEach(Kind.all, id: \.self) { kind in
                FilterChip(title: Lexicon.Finder.kindLabel(kind),
                           count: counts?.kinds.first { $0.kind == kind }.map { Int($0.count) },
                           isOn: model.filter.kinds.contains(kind)) {
                    toggle(&model.filter.kinds, kind)
                }
            }
            FilterChip(title: Lexicon.Finder.saved, symbol: "star",
                       count: counts.map { Int($0.saved) }, isOn: model.filter.savedOnly) {
                model.filter.savedOnly.toggle()
            }
            MoreMenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ item: T) {
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
    }
}

/// One chip. A toggle: on is a tinted capsule, off is an outline. The count is quiet.
struct FilterChip: View {
    let title: String
    var symbol: String?
    var count: Int?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: isOn ? symbol + ".fill" : symbol).font(.caption) }
                Text(title)
                if let count { Text(count.formatted()).foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.16) : .clear))
            .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1))
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Style traits, Show hidden, and a way back to the standard filter.
struct MoreMenu: View {
    @Environment(AppModel.self) private var model

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
            Text(active > 0 ? "\(Lexicon.Finder.more) \u{00B7} \(active)" : Lexicon.Finder.more)
                .font(.callout)
        }
        .menuIndicator(.visible)
        .fixedSize()
        .help(Lexicon.Finder.moreHelp)
    }

    private func label(_ title: String, _ count: UInt32?) -> String {
        count.map { "\(title)  \($0.formatted())" } ?? title
    }
}

/// The star: Saved. Filled when on. Takes the family's state, holds none.
struct StarButton: View {
    let name: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "star.fill" : "star")
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(isOn ? Lexicon.Finder.removeSaved : Lexicon.Finder.save)
        .accessibilityLabel(isOn ? "Remove \(name) from Saved" : "Save \(name)")
    }
}

/// Save and Hide for the family in an inspector header.
struct FamilyActions: View {
    @Environment(AppModel.self) private var model
    let name: String

    var body: some View {
        let saved = model.isSaved(name), hidden = model.isHidden(name)
        HStack(spacing: 8) {
            Button {
                Task { await model.setFavorite(name, on: !saved) }
            } label: {
                Label(saved ? Lexicon.Finder.saved : Lexicon.Finder.save, systemImage: saved ? "star.fill" : "star")
            }
            Button {
                Task { await model.setHidden(name, hidden: !hidden) }
            } label: {
                Label(hidden ? Lexicon.Finder.unhide : Lexicon.Finder.hide, systemImage: hidden ? "eye" : "eye.slash")
            }
            .help(hidden ? Lexicon.Finder.unhideHelp : Lexicon.Finder.hideHelp)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
