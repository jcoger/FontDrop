import FontDropCore
import SwiftUI

/// The sidebar panel: brand switcher, the three jobs (Display, Text, Set), and the status readout.
/// Rows are buttons on a neutral pill, not a system List, so the pill matches the Text list's.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var showNewBrand = false
    @State private var newName = ""
    @State private var renaming: Brand?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 36)                 // the traffic lights sit here
            sectionLabel("Brands")
            brandSwitcher.padding(.bottom, 18)
            sectionLabel("Type")
            VStack(spacing: 2) {
                ForEach(Screen.sidebar) { screen in row(screen) }
            }
            Spacer(minLength: 12)
            StatusReadout()
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            .padding(.horizontal, 12).padding(.bottom, 6)
    }

    // MARK: Brand switcher

    @ViewBuilder
    private var brandSwitcher: some View {
        if model.brands.isEmpty {
            HStack {
                Text(Lexicon.brandsEmpty).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                Spacer()
                Button { newName = ""; showNewBrand = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("New brand").accessibilityLabel("New brand")
            }
            .padding(.horizontal, 12)
        } else {
            let current = model.brand
            Menu {
                ForEach(model.brands) { brand in
                    Button {
                        Task { await model.selectBrand(brand.id) }
                    } label: {
                        if brand.id == model.brandID { Label(brand.name, systemImage: "checkmark") } else { Text(brand.name) }
                    }
                }
                Divider()
                Button("New brand\u{2026}") { newName = ""; showNewBrand = true }
                if let current { Button("Rename\u{2026}") { renameText = current.name; renaming = current } }
            } label: {
                HStack(spacing: 10) {
                    Text(String((current?.name ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.onPrimaryButton.color)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.textPrimary.color))
                    Text(current?.name ?? "").font(.system(size: 14)).lineLimit(1)
                        .foregroundStyle(theme.textPrimary.color)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary.color)
                }
                .padding(.horizontal, 12).frame(height: 44)
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel("Brand")
            .accessibilityValue(current?.name ?? "")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ screen: Screen) -> some View {
        let selected = model.screen == screen
        Button { model.screen = screen } label: {
            HStack(spacing: 12) {
                Image(systemName: screen.symbol).font(.system(size: 16, weight: .regular))
                    .frame(width: 22)
                    .foregroundStyle(theme.textPrimary.color)
                if screen == .set { setLines } else { typeLines(screen) }
                Spacer(minLength: 4)
                if screen != .set, model.chosen(screen) != nil {
                    Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SelectionPill(on: selected, sidebar: true, radius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            if let job = screen.job {
                Button(Lexicon.clearFace(job)) { Task { await model.clear(job) } }
                    .disabled(!model.canClear(job))
                if model.chosen(screen) == nil, model.canUndo(job) {
                    Button(Lexicon.undo) { Task { await model.undo(job) } }
                }
            }
        }
    }

    /// Set: the brand's scale on a second line, like Display and Text show their face.
    private var setLines: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Screen.set.title).font(.system(size: 13)).foregroundStyle(theme.textPrimary.color)
            Text(Lexicon.Scale.sidebarLine(model.scale))
                .font(.system(size: 12)).foregroundStyle(theme.textSecondary.color).monospacedDigit()
        }
    }

    private func typeLines(_ screen: Screen) -> some View {
        let chosen = model.chosen(screen)
        let family = chosen.flatMap { model.familyByName[$0] }
        return VStack(alignment: .leading, spacing: 1) {
            Text(screen.title).font(.system(size: 13)).foregroundStyle(theme.textPrimary.color)
            if let family {
                FontText(path: family.filePath, text: family.name, size: 12, tick: model.fontTick)
                    .foregroundStyle(theme.textSecondary.color).lineLimit(1)
            } else if let chosen {
                Text(chosen).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            } else if let job = screen.job, model.canUndo(job) {
                // Just cleared: say so, with the way back.
                HStack(spacing: 6) {
                    Text(Lexicon.cleared(job)).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
                    Button(Lexicon.undo) { Task { await model.undo(job) } }
                        .buttonStyle(.themeLink).font(.system(size: 12))
                }
            }
        }
    }
}

/// The status readout at the foot of the sidebar: a recessed screen, Doto digits, a red light only while scanning.
struct StatusReadout: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            switch model.scanState {
            case .idle:
                Text(Lexicon.Status.counts(families: model.families.count, files: model.fontCount))
            case .running:
                SignalLight(lit: true)
                Text(Lexicon.Status.scanning)
            case .failed:
                Text(Lexicon.Status.failed)
                Button(Lexicon.Scan.retry) { Task { await model.retryScan() } }
                    .buttonStyle(.themeLink).font(.system(size: 11))
                    .help(Lexicon.Scan.retryHelp)
            }
            Spacer(minLength: 0)
        }
        .font(InstrumentFonts.doto(13))
        .foregroundStyle(theme.textPrimary.color)
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 12).frame(height: 40)
        .recessed(radius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.scanState == .running ? Lexicon.Scan.updating
                            : "\(model.fontCount.formatted()) fonts, \(model.families.count.formatted()) families")
    }
}
