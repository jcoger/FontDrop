import FontDropCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewBrand = false
    @State private var newName = ""
    @State private var renaming: Brand?
    @State private var renameText = ""

    var body: some View {
        let selection = Binding<Screen?>(get: { model.screen }, set: { if let s = $0 { model.screen = s } })
        List(selection: selection) {
            Section {
                ForEach(model.brands) { brand in brandRow(brand) }
                if model.brands.isEmpty {
                    Text(Lexicon.brandsEmpty).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Brands")
                    Spacer()
                    Button { newName = ""; showNewBrand = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("New brand")
                }
            }

            Section("Type") {
                ForEach([Screen.display, .reading, .ui, .mono]) { screen in typeRow(screen).tag(screen) }
            }

            Section("Library") { savedRow }

            Section {
                Label("Set", systemImage: Screen.set.symbol).tag(Screen.set)
                HStack {
                    Label("Colors", systemImage: Screen.colors.symbol)
                    Spacer()
                    Text("Parked").font(.caption)
                }
                .foregroundStyle(.tertiary)
                .selectionDisabled()
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("\(model.fontCount.formatted()) fonts \u{00B7} \(model.families.count.formatted()) families")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .alert("New brand", isPresented: $showNewBrand) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await model.createBrand(newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename brand", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let b = renaming { Task { await model.renameBrand(b, to: renameText) } } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func brandRow(_ brand: Brand) -> some View {
        let selected = brand.id == model.brandID
        return Button { Task { await model.selectBrand(brand.id) } } label: {
            HStack(spacing: 8) {
                Text(String(brand.name.prefix(1)).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : Color.secondary.opacity(0.2)))
                Text(brand.name).lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).padding(.horizontal, 6) : nil)
        .contextMenu {
            Button("Rename\u{2026}") { renameText = brand.name; renaming = brand }
        }
    }

    /// Saved: the starred families. A shortcut for the Saved chip on the Display grid.
    private var savedRow: some View {
        let on = model.filter.savedOnly
        return Button {
            model.filter.savedOnly.toggle()
            if ![Screen.display, .ui, .mono].contains(model.screen) { model.screen = .display }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Color.accentColor : Color.secondary)
                Text(Lexicon.Finder.saved)
                Spacer()
                Text("\(model.savedCount)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Lexicon.Finder.savedSidebarHelp)
        .listRowBackground(on ? RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).padding(.horizontal, 6) : nil)
    }

    private func typeRow(_ screen: Screen) -> some View {
        let chosen = model.chosen(screen)
        let family = chosen.flatMap { model.familyByName[$0] }
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Label(screen.title, systemImage: screen.symbol)
                if let family {
                    FontText(path: family.filePath, text: family.name, size: 11, tick: model.fontTick)
                        .foregroundStyle(.secondary).lineLimit(1)
                        .padding(.leading, 24)
                } else if let chosen {
                    Text(chosen).font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 24)
                }
            }
            Spacer()
            trailing(screen, chosen: chosen)
        }
    }

    @ViewBuilder
    private func trailing(_ screen: Screen, chosen: String?) -> some View {
        if screen == .reading, !model.shortlist("reading").isEmpty {
            Text("\(model.shortlist("reading").count)").font(.caption).foregroundStyle(.secondary)
        } else if chosen != nil {
            Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
        } else if screen == .ui || screen == .mono {
            Image(systemName: "plus").font(.caption).foregroundStyle(.tertiary)
        }
    }
}
