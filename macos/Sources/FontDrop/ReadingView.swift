import FontDropCore
import SwiftUI

struct ReadingView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 330, maximum: 460), spacing: 16, alignment: .top)]

    var body: some View {
        @Bindable var model = model
        Group {
            if let display = model.displayFamily {
                content(display)
            } else {
                ContentUnavailableView {
                    Label(Lexicon.needsDisplayTitle, systemImage: "textformat.size")
                } description: {
                    Text(Lexicon.needsDisplayBody)
                } actions: {
                    Button(Lexicon.needsDisplayCTA) { model.screen = .display }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .task(id: "\(model.brandID ?? 0)/\(model.displayFamily?.fontId ?? "")") { await model.loadCandidates() }
        .toolbar { LensToolbar(lenses: $model.lenses) }
    }

    @ViewBuilder
    private func content(_ display: FamilySummary) -> some View {
        @Bindable var model = model
        let result = model.readingResult
        let tick = model.fontTick
        let chosen = model.chosen(.reading)
        let saved = Set(model.shortlist("reading"))
        let displayFace = model.face("display", display)
        let template = Templates.descriptor(model.templateID)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.brand?.name ?? "Your brand") pair \u{00B7} \(display.name) with each candidate")
                            .font(.callout.weight(.semibold))
                        Text("Headlines are set in your Display face. Body and interface text are the candidate.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Template", selection: $model.templateID) {
                        ForEach(Templates.all) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("Show the pair in a different layout")
                }
                statusRow(shown: result.shown.count, hidden: result.hidden)

                if model.candidatesLoading && model.candidates.isEmpty {
                    ProgressView("Finding partners for \(display.name)").frame(maxWidth: .infinity).padding(.top, 40)
                } else if let error = model.candidatesError {
                    ContentUnavailableView("Could not load candidates", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if result.shown.isEmpty {
                    ContentUnavailableView {
                        Label(model.candidates.isEmpty ? "No candidates" : Lexicon.readingNone,
                              systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(model.candidates.isEmpty
                             ? "The engine found no Reading partners for \(display.name)."
                             : "\(result.hidden) hidden by your filters.")
                    } actions: {
                        if !model.lenses.isNeutral { Button(Lexicon.clearFilters) { resetLenses() } }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(result.shown) { c in
                            let family = model.familyByName[c.family]
                            let bodyFace = family.map { model.face("reading", $0) }
                                ?? FaceSpec(path: c.filePath, settings: .defaults(job: "reading"))
                            CandidateCard(candidate: c, family: family, tick: tick,
                                          isSelected: model.selectedCandidate == c.id,
                                          isSaved: saved.contains(c.family),
                                          isChosen: chosen == c.family,
                                          xHeightNote: xHeightNote(display: displayFace.resolvedPath, candidate: bodyFace.resolvedPath),
                                          context: PairContext(brand: model.brand?.name ?? "Brand Name",
                                                               display: displayFace, body: bodyFace, tick: tick),
                                          template: template) {
                                model.selectedCandidate = c.id
                            } showWhy: {
                                model.selectedCandidate = c.id
                                model.showInspector = true
                            }
                        }
                    }
                    footer(result: result)
                }
            }
            .padding(20)
        }
    }

    private func statusRow(shown: Int, hidden: Int) -> some View {
        HStack(spacing: 10) {
            Label(model.includeUnfitFaces ? Lexicon.showingEvery : Lexicon.readingFixed,
                  systemImage: "line.3.horizontal.decrease")
                .font(.caption).foregroundStyle(.secondary)
                .help(Lexicon.readingFixedWhy)
            Button(model.includeUnfitFaces ? Lexicon.onlyTextFaces : Lexicon.showThem) {
                Task { await model.setIncludeUnfit(!model.includeUnfitFaces) }
            }
            .buttonStyle(.link).font(.caption)
            Text("\(shown) shown").font(.caption).foregroundStyle(.secondary)
            if hidden > 0 {
                Text("\u{00B7} \(hidden) hidden by your filters").font(.caption).foregroundStyle(.secondary)
                Button(Lexicon.clearFilters) { resetLenses() }.buttonStyle(.link).font(.caption)
            }
            Spacer()
            GlossaryButton()
        }
    }

    /// Under the grid: how many the filters hide (with a way out) and a way to ask for more.
    @ViewBuilder
    private func footer(result: (shown: [Candidate], hidden: Int)) -> some View {
        VStack(spacing: 10) {
            if result.hidden > 0 {
                HStack(spacing: 6) {
                    Text("Your filters hide \(result.hidden) more of the \(model.candidates.count) loaded.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button(Lexicon.clearFilters) { resetLenses() }.buttonStyle(.link)
                }
            }
            if model.candidatesHasMore {
                Button(Lexicon.showMore) { Task { await model.showMoreCandidates() } }
                    .controlSize(.large)
                    .disabled(model.candidatesLoading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func resetLenses() {
        model.lenses.contrast = .any; model.lenses.structure = .any; model.lenses.foundry = .any
    }

    /// "x-height 9% smaller", measured from the two loaded fonts so it has a direction.
    /// Only for candidates the engine already tagged with an x-height reason.
    private func xHeightNote(display: String, candidate: String) -> String? {
        guard case .success(let d)? = FontLoader.shared.cached(display),
              case .success(let c)? = FontLoader.shared.cached(candidate), d.xHeightRatio > 0 else { return nil }
        let diff = (c.xHeightRatio / d.xHeightRatio - 1) * 100
        if abs(diff) < 1 { return "Same x-height" }
        return "x-height \(Int(abs(diff).rounded()))% \(diff < 0 ? "smaller" : "larger") than Display"
    }
}

// MARK: - Toolbar lenses

/// The four questions. Each is a menu with an "any" state. Nothing is a slider yet:
/// `ContrastLens.steps` is the order a Similar-to-Bold slider would use.
struct LensToolbar: ToolbarContent {
    @Binding var lenses: Lenses

    var body: some ToolbarContent {
        ToolbarItemGroup {
            LensMenu(title: Lexicon.contrastLabel, value: lenses.contrast.rawValue) {
                Picker(Lexicon.contrastLabel, selection: $lenses.contrast) {
                    ForEach(ContrastLens.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            LensMenu(title: Lexicon.structureLabel, value: lenses.structure.rawValue) {
                Picker(Lexicon.structureLabel, selection: $lenses.structure) {
                    ForEach(StructureLens.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            LensMenu(title: Lexicon.foundryLabel, value: lenses.foundry.rawValue) {
                Picker(Lexicon.foundryLabel, selection: $lenses.foundry) {
                    ForEach(FoundryLens.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            LensMenu(title: Lexicon.sortLabel, value: lenses.sort.rawValue) {
                Picker(Lexicon.sortLabel, selection: $lenses.sort) {
                    ForEach(ReadingSort.allCases) { Text($0.rawValue).tag($0) }
                }
            }
        }
    }
}

struct LensMenu<Options: View>: View {
    let title: String
    let value: String
    @ViewBuilder var options: Options

    var body: some View {
        Menu {
            options.pickerStyle(.inline).labelsHidden()
        } label: {
            Text(title).foregroundStyle(.secondary) + Text("  ") + Text(value).fontWeight(.semibold)
        }
        .menuIndicator(.visible)
    }
}

// MARK: - Candidate card

/// One candidate: the pair drawn in the chosen template, the reasons as chips, and a footer.
struct CandidateCard: View {
    let candidate: Candidate
    let family: FamilySummary?
    let tick: Int
    let isSelected: Bool
    let isSaved: Bool
    let isChosen: Bool
    let xHeightNote: String?
    let context: PairContext
    let template: TemplateDescriptor
    let select: () -> Void
    let showWhy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(candidate.family).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                if isChosen {
                    Text("Chosen").font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                } else if isSaved {
                    Text("Saved").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            template.make(context)

            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.text) { chip in
                    EvidenceChip(text: chip.text, effect: chip.effect, help: chip.help, warning: chip.warning)
                }
            }
            .padding(.horizontal, 14)

            HStack {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Why", action: showWhy).buttonStyle(.link).font(.caption)
            }
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                          lineWidth: isSelected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: select)
    }

    private struct Chip { let text: String; let effect: Int8; let help: String; var warning = false }

    /// Engine evidence in designer words, plus "Mixed feel" when the two faces cross traditions.
    private var chips: [Chip] {
        var out = candidate.evidence.map { e in
            Chip(text: Lexicon.chip(e, xHeightNote: e.lens == "x-height" ? xHeightNote : nil),
                 effect: e.effect, help: Lexicon.sources(e.source), warning: e.lens == "Near-duplicate")
        }
        if candidate.isCrossedHands { out.append(Chip(text: "Mixed structure", effect: 0, help: Lexicon.Term.sameStructure.help)) }
        var seen = Set<String>()
        return out.filter { seen.insert($0.text).inserted }
    }

    private var footer: String {
        guard let family else { return "" }
        let styles = "\(family.styleCount) \(family.styleCount == 1 ? "style" : "styles")"
        return family.isTrial ? "\(styles) \u{00B7} Trial" : styles
    }
}

// MARK: - Inspector

struct ReadingInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selected = model.candidate(model.selectedCandidate)
        let isChosen = selected.map { model.chosen(.reading) == $0.family } ?? false
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c = selected {
                    header(c)
                    why(c)
                    playgrounds(c)
                } else {
                    Text("Select a candidate to see why it pairs.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                shortlist(selected)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) { action(selected, isChosen: isChosen) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isChosen)
    }

    private func header(_ c: Candidate) -> some View {
        let isSaved = model.shortlist("reading").contains(c.family)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.family).font(.title3.weight(.semibold))
                Text("Reading candidate").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await model.setShortlist("reading", family: c.family, on: !isSaved) }
            } label: {
                Label(isSaved ? "On the shortlist" : "Add to shortlist",
                      systemImage: isSaved ? "checkmark.circle.fill" : "plus.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func why(_ c: Candidate) -> some View {
        InspectorSection(title: Lexicon.whyItPairs) {
            if c.evidence.isEmpty {
                Text("The engine measured nothing notable.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(c.evidence.enumerated()), id: \.offset) { i, e in
                if i > 0 { Divider().padding(.vertical, 6) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: symbol(e)).font(.caption).foregroundStyle(tint(e))
                        Text(Lexicon.whyTitle(e)).font(.caption).foregroundStyle(.secondary)
                        if let term = Lexicon.term(forLens: e.lens) { HelpButton(term: term) }
                        Spacer()
                    }
                    let detail = Lexicon.whyDetail(e)
                    if !detail.isEmpty { Text(detail).font(.callout) }
                    if e.effect == 0 {
                        Text(Lexicon.notScored).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        let word = Lexicon.strength(e.strength)
                        Text([word, Lexicon.strengthHelp[word]].compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    let sources = Lexicon.sources(e.source)
                    if !sources.isEmpty { Text(sources).font(.caption2).foregroundStyle(.tertiary) }
                }
            }
        }
    }

    private func symbol(_ e: Evidence) -> String {
        e.effect > 0 ? "plus.circle" : e.effect < 0 ? "minus.circle" : "circle.dashed"
    }

    private func tint(_ e: Evidence) -> Color {
        e.effect > 0 ? .accentColor : e.effect < 0 ? .orange : .secondary
    }

    /// Two collapsible groups: the Display face and the selected candidate. Both feed the cards live.
    @ViewBuilder
    private func playgrounds(_ c: Candidate) -> some View {
        let open = model.options.openPlayground
        if let display = model.displayFamily {
            PlaygroundGroup(job: "display", family: display, title: "Display \u{00B7} \(display.name)",
                            preview: SampleCopy.displayHeadline, startOpen: open)
        }
        if let family = model.familyByName[c.family] {
            PlaygroundGroup(job: "reading", family: family, title: "Reading \u{00B7} \(family.name)",
                            preview: SampleCopy.paragraphs[0], startOpen: open)
        }
    }

    private func shortlist(_ selected: Candidate?) -> some View {
        let list = model.shortlist("reading")
        return InspectorSection(title: Lexicon.shortlistTitle, trailing: "\(list.count)") {
            if list.isEmpty {
                Text(Lexicon.shortlistEmpty).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(list.enumerated()), id: \.element) { i, name in
                if i > 0 { Divider().padding(.vertical, 5) }
                HStack {
                    Button(name) {
                        if let c = model.candidates.first(where: { $0.family == name }) { model.selectedCandidate = c.id }
                    }
                    .buttonStyle(.plain).lineLimit(1)
                    Spacer()
                    if model.chosen(.reading) == name {
                        Text("Chosen").font(.caption).foregroundStyle(Color.accentColor)
                    }
                    Button { Task { await model.setShortlist("reading", family: name, on: false) } } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Remove from shortlist")
                    .accessibilityLabel("Remove \(name) from shortlist")
                }
            }
        }
    }

    @ViewBuilder
    private func action(_ selected: Candidate?, isChosen: Bool) -> some View {
        if isChosen {
            ChosenPanel(job: "reading", nextTitle: Lexicon.setTheType) { model.screen = .set }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            DecisionButton(title: Lexicon.useFor("reading"), disabled: selected == nil) {
                if let c = selected { Task { await model.choose("reading", family: c.family) } }
            }
        }
    }
}
