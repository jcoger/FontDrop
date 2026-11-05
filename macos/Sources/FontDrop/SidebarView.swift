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

            // Display, Text, Set. UI and Mono are off the sidebar; Saved is a filter on Display; Colors is on the Text stage.
            Section {
                ForEach(Screen.sidebar) { screen in
                    row(screen).tag(screen)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            libraryFooter
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

    /// The library's counts, or where the rescan stands: updating (with a spinner) or failed (with Retry).
    @ViewBuilder
    private var libraryFooter: some View {
        switch model.scanState {
        case .idle:
            Text("\(model.fontCount.formatted()) fonts \u{00B7} \(model.families.count.formatted()) families")
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(Lexicon.Scan.updating)
            }
            .accessibilityElement(children: .combine)
        case .failed:
            HStack(spacing: 8) {
                Text(Lexicon.Scan.failed)
                Button(Lexicon.Scan.retry) { Task { await model.retryScan() } }
                    .buttonStyle(.link)
                    .help(Lexicon.Scan.retryHelp)
            }
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

    @ViewBuilder
    private func row(_ screen: Screen) -> some View {
        if screen == .set { setRow } else { typeRow(screen) }
    }

    /// Set: the brand's scale on a second line, like Display and Text show their face.
    private var setRow: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(Screen.set.title, systemImage: Screen.set.symbol)
            Text(Lexicon.Scale.sidebarLine(model.scale))
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                .padding(.leading, 24)
        }
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
                } else if let job = screen.job, model.canUndo(job) {
                    // Just cleared: say so, with the way back.
                    HStack(spacing: 6) {
                        Text(Lexicon.cleared(job)).font(.system(size: 11)).foregroundStyle(.secondary)
                        Button(Lexicon.undo) { Task { await model.undo(job) } }
                            .buttonStyle(.link).font(.system(size: 11))
                    }
                    .padding(.leading, 24)
                }
            }
            Spacer()
            if chosen != nil {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if let job = screen.job {
                Button(Lexicon.clearFace(job)) { Task { await model.clear(job) } }
                    .disabled(!model.canClear(job))
                if chosen == nil, model.canUndo(job) {
                    Button(Lexicon.undo) { Task { await model.undo(job) } }
                }
            }
        }
    }
}
