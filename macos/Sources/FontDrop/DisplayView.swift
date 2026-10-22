import FontDropCore
import SwiftUI

/// The grid used by Display, UI and Mono: every family, set in the brand's name.
/// `screen` decides which job "Use for ..." chooses a face for.
struct FamilyPickerView: View {
    @Environment(AppModel.self) private var model
    let screen: Screen

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]

    var body: some View {
        @Bindable var model = model
        let families = model.visibleFamilies
        let chosen = model.chosen(screen)
        let sample = model.sampleText
        let tick = model.fontTick

        VStack(spacing: 0) {
        FilterBar()
            .padding(.horizontal, 20).padding(.vertical, 10)
        Divider()
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose the \(screen.title) face").font(.title2.weight(.semibold))
                    Text(subtitle(count: families.count))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if families.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(families) { family in
                            FamilyCard(family: family, sample: sample, tick: tick,
                                       isSelected: model.selectedFamily == family.name,
                                       isChosen: chosen == family.name,
                                       isSaved: model.isSaved(family.name),
                                       isHidden: model.isHidden(family.name),
                                       playground: model.selectedFamily == family.name ? playgroundFace(family) : nil,
                                       toggleSaved: { Task { await model.setFavorite(family.name, on: !model.isSaved(family.name)) } },
                                       toggleHidden: { Task { await model.setHidden(family.name, hidden: !model.isHidden(family.name)) } })
                                .id(family.name)
                                .onTapGesture { model.selectedFamily = family.name }
                        }
                    }
                }
            }
            .padding(20)
        }
        // Open on the chosen face, so the grid starts where you left off.
        .task(id: "\(model.brandID ?? 0)/\(screen.rawValue)/\(model.fontsReady)") {
            if model.fontsReady, let name = model.chosen(screen) { proxy.scrollTo(name, anchor: .center) }
        }
        }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.filter.savedOnly && model.search.isEmpty && model.filter.kinds.isEmpty && model.filter.traits.isEmpty {
            ContentUnavailableView(Lexicon.Finder.savedEmpty, systemImage: "star")
        } else {
            ContentUnavailableView {
                Label(Lexicon.Finder.noMatches, systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button(Lexicon.clearFilters) { model.filter = .standard; model.search = "" }
            }
        }
    }

    /// The selected card shows the playground's style, axes, features and tracking (its size stays the card's).
    private func playgroundFace(_ family: FamilySummary) -> FaceSpec? {
        guard let job = screen.job, model.typeSettings.isModified(model.settingsKey(job, family.name), job: job) else { return nil }
        var face = model.face(job, family)
        face.settings.size = 54
        return face
    }

    private func subtitle(count: Int) -> String {
        let brand = model.brand?.name ?? "Your brand name"
        let tail = screen == .display ? "The face you pick here sets the tone for Reading." : "Pick one for this job."
        return "\(brand) set in each of \(count) families. Your fonts come first. \(tail)"
    }
}

/// One family card. Takes plain values and holds no state.
struct FamilyCard: View {
    let family: FamilySummary
    let sample: String
    let tick: Int
    let isSelected: Bool
    let isChosen: Bool
    let isSaved: Bool
    let isHidden: Bool
    var playground: FaceSpec?        // set on the selected card once the designer changed something
    let toggleSaved: () -> Void
    let toggleHidden: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let playground {
                    FaceText(face: playground, text: sample, tick: tick, useLineHeight: false)
                } else {
                    FontText(path: family.filePath, text: sample, size: 54, fallbacks: [family.name], tick: tick)
                }
            }
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124)
                .overlay(alignment: .topTrailing) {
                    if isSaved { StarButton(name: family.name, isOn: true, toggle: toggleSaved) }
                    else { StarButton(name: family.name, isOn: false, toggle: toggleSaved).opacity(0.55) }
                }
            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(family.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(family.styleCount) \(family.styleCount == 1 ? "style" : "styles")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isChosen {
                    Text("Chosen").font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                } else if isHidden {
                    TagPill(text: Lexicon.Finder.hidden)
                } else if family.isTrial {
                    TagPill(text: "Trial")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
        .contextMenu {
            Button(isSaved ? Lexicon.Finder.removeSaved : Lexicon.Finder.save, systemImage: isSaved ? "star.slash" : "star", action: toggleSaved)
            Button(isHidden ? Lexicon.Finder.unhide : Lexicon.Finder.hide, systemImage: isHidden ? "eye" : "eye.slash", action: toggleHidden)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                          lineWidth: isSelected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Inspector

struct FamilyInspector: View {
    @Environment(AppModel.self) private var model
    let screen: Screen
    @State private var detail: FamilyDetail?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let name = model.selectedFamily, let family = model.familyByName[name] {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(family)
                    if let job = screen.job {
                        PlaygroundGroup(job: job, family: family, title: "Playground \u{00B7} \(family.name)",
                                        preview: model.sampleText, startOpen: true)
                    }
                    if let detail, detail.family == name { facts(family, detail) }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { action(family) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.choices[screen.job ?? ""] == family.name)
            .task(id: name) { detail = await model.detail(for: name) }
        } else {
            ContentUnavailableView("No family selected", systemImage: "textformat",
                                   description: Text("Select a family to see its styles, axes and x-height."))
        }
    }

    private func header(_ family: FamilySummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(family.name).font(.title3.weight(.semibold))
            Text("\(screen.title) candidate" + (detail.map { $0.axes.isEmpty ? "" : " \u{00B7} Variable" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            FamilyActions(name: family.name).padding(.top, 6)
        }
    }

    @ViewBuilder
    private func facts(_ family: FamilySummary, _ d: FamilyDetail) -> some View {
        InspectorSection(title: "Styles", trailing: "\(d.styles.count)") {
            ForEach(Array(d.styles.prefix(10).enumerated()), id: \.element.fontId) { i, style in
                if i > 0 { Divider().padding(.vertical, 5) }
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(styleLabel(style)).font(.callout).lineLimit(1)
                        Text("Weight \(style.weight)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    FontText(path: style.filePath, text: model.sampleText, size: 17,
                             fallbacks: [family.name], tick: model.fontTick)
                        .lineLimit(1)
                }
            }
            if d.styles.count > 10 {
                Text("\(d.styles.count - 10) more").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
        InspectorSection(title: "Facts") {
            if let entry = model.allEntries[family.name] {
                fact(Lexicon.Finder.sourceFact, Lexicon.Finder.sources(entry.sources))
                Divider().padding(.vertical, 5)
            }
            fact("x-height", d.xHeight.map { String(format: "%.3f", $0) } ?? "Unavailable")
            Divider().padding(.vertical, 5)
            fact("Structure", family.skeleton.isEmpty ? "Unknown" : Lexicon.structure(family.skeleton))
            Divider().padding(.vertical, 5)
            fact("License", family.isTrial ? Lexicon.licenseTrial : Lexicon.licenseOK)
            if let vendor = family.vendor {
                Divider().padding(.vertical, 5)
                fact("Vendor", vendor)
            }
            if let urlText = family.foundryUrl, let url = URL(string: urlText) {
                Divider().padding(.vertical, 5)
                HStack {
                    Text("Foundry").font(.callout)
                    Spacer()
                    Link(family.isTrial ? Lexicon.getLicense : (url.host() ?? "Foundry page"), destination: url).font(.callout).lineLimit(1)
                }
            }
        }
    }

    /// The font's own style name ("Grand Heavy"), else a cleaned file name.
    private func styleLabel(_ style: FontFile) -> String { StyleNames.label(style, family: style.family) }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(value).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    @ViewBuilder
    private func action(_ family: FamilySummary) -> some View {
        if let job = screen.job {
            if model.choices[job] == family.name {
                ChosenPanel(job: job,
                            nextTitle: job == "display" ? Lexicon.findReading : nil,
                            next: job == "display" ? { model.screen = .reading } : nil)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                DecisionButton(title: Lexicon.useFor(job)) {
                    Task { await model.choose(job, family: family.name) }
                }
            }
        }
    }
}
