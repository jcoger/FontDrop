import FontDropCore
import SwiftUI

/// Sample copy shown in every candidate. Neutral on purpose; no client names.
enum SampleCopy {
    static let headline = "Nobody has to ask, and nobody has to tip twice."
    static let paragraphs = [
        "Book a table for four and we hold it until you arrive. Your name is on the list, the kitchen knows, and the first round is already poured.",
        "They know the window seat is yours and the music stays low. Nothing to confirm, nothing to repeat.",
    ]
    static let button = "Reserve a table"
    static let caption = "Avg. wait 4 min"
    static let displayHeadline = "Good things, held warm."
}

struct ReadingView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 16, alignment: .top)]

    var body: some View {
        @Bindable var model = model
        Group {
            if let display = model.displayFamily {
                content(display)
            } else {
                ContentUnavailableView {
                    Label("Choose a Display face first", systemImage: "textformat.size")
                } description: {
                    Text("Reading candidates are matched to your Display face.")
                } actions: {
                    Button("Go to Display") { model.screen = .display }
                }
            }
        }
        .task(id: "\(model.brandID ?? 0)/\(model.displayFamily?.fontId ?? "")") { await model.loadCandidates() }
        .toolbar { LensToolbar(lenses: $model.lenses) }
    }

    @ViewBuilder
    private func content(_ display: FamilySummary) -> some View {
        let result = model.readingResult
        let tick = model.fontTick
        let chosen = model.chosen(.reading)
        let saved = Set(model.shortlist("reading"))

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(model.brand?.name ?? "Brand") headline \u{00B7} \(display.name) \u{00B7} Display")
                        .font(.caption).foregroundStyle(.secondary)
                    FontText(path: display.filePath, text: SampleCopy.displayHeadline, size: 44,
                             checkCoverage: false, tick: tick)
                        .lineLimit(2)
                }
                statusRow(shown: result.shown.count, hidden: result.hidden)

                if model.candidatesLoading && model.candidates.isEmpty {
                    ProgressView("Finding partners for \(display.name)").frame(maxWidth: .infinity).padding(.top, 40)
                } else if let error = model.candidatesError {
                    ContentUnavailableView("Could not load candidates", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if result.shown.isEmpty {
                    ContentUnavailableView {
                        Label(model.candidates.isEmpty ? "No candidates" : "Nothing matches these lenses",
                              systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(model.candidates.isEmpty
                             ? "The engine found no Reading partners for \(display.name)."
                             : "\(result.hidden) hidden by your lenses. Set a lens to Any to see them.")
                    } actions: {
                        if !model.lenses.isNeutral { Button("Show everything") { resetLenses() } }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(result.shown) { c in
                            CandidateCard(candidate: c, family: model.familyByName[c.family], tick: tick,
                                          isSelected: model.selectedCandidate == c.id,
                                          isSaved: saved.contains(c.family),
                                          isChosen: chosen == c.family)
                                .onTapGesture { model.selectedCandidate = c.id }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func statusRow(shown: Int, hidden: Int) -> some View {
        HStack(spacing: 10) {
            Label("Text cuts only", systemImage: "line.3.horizontal.decrease")
                .font(.caption).foregroundStyle(.secondary)
                .help("The engine only offers faces with regular, italic and bold, not condensed or mono.")
            Text("\(shown) shown").font(.caption).foregroundStyle(.secondary)
            if hidden > 0 {
                Text("\u{00B7} \(hidden) hidden by your lenses").font(.caption).foregroundStyle(.secondary)
                Button("Show everything") { resetLenses() }.buttonStyle(.link).font(.caption)
            }
            Spacer()
        }
    }

    private func resetLenses() {
        model.lenses.contrast = .any; model.lenses.hand = .either; model.lenses.foundry = .any
    }
}

// MARK: - Toolbar lenses

/// The four questions. Each is a menu with an "any" state. Nothing is a slider.
struct LensToolbar: ToolbarContent {
    @Binding var lenses: Lenses

    var body: some ToolbarContent {
        ToolbarItemGroup {
            LensMenu(title: "How much contrast", value: lenses.contrast.rawValue) {
                Picker("How much contrast", selection: $lenses.contrast) {
                    ForEach(ContrastLens.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            LensMenu(title: "Same hand", value: lenses.hand.rawValue) {
                Picker("Same hand", selection: $lenses.hand) {
                    ForEach(HandLens.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            LensMenu(title: "Same foundry", value: lenses.foundry.rawValue) {
                Picker("Same foundry", selection: $lenses.foundry) {
                    ForEach(FoundryLens.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            LensMenu(title: "Sort", value: lenses.sort.rawValue) {
                Picker("Sort", selection: $lenses.sort) {
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

struct CandidateCard: View {
    let candidate: Candidate
    let family: FamilySummary?
    let tick: Int
    let isSelected: Bool
    let isSaved: Bool
    let isChosen: Bool

    private var path: String { candidate.filePath }

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

            VStack(alignment: .leading, spacing: 12) {
                FontText(path: path, text: SampleCopy.headline, size: 24, checkCoverage: false, tick: tick)
                ForEach(SampleCopy.paragraphs, id: \.self) { p in
                    FontText(path: path, text: p, size: 14, checkCoverage: false, tick: tick)
                        .lineSpacing(3)
                }
                HStack(spacing: 10) {
                    FontText(path: path, text: SampleCopy.button, size: 14, checkCoverage: false, tick: tick)
                        .foregroundStyle(.background)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(.primary))
                    FontText(path: path, text: SampleCopy.caption, size: 12, checkCoverage: false, tick: tick)
                        .italic().foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)

            FlowLayout(spacing: 6) {
                ForEach(Array(candidate.evidence.enumerated()), id: \.offset) { _, e in
                    EvidenceChip(evidence: e)
                }
            }
            .padding(.horizontal, 14)

            HStack {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Why this one").font(.caption).foregroundStyle(Color.accentColor)
            }
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                          lineWidth: isSelected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
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

    var body: some View {
        let selected = model.candidate(model.selectedCandidate)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c = selected {
                    header(c)
                    evidence(c)
                } else {
                    Text("Select a candidate to read its evidence.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                shortlist(selected)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) { action(selected) }
    }

    private func header(_ c: Candidate) -> some View {
        let isSaved = model.shortlist("reading").contains(c.family)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.family).font(.title3.weight(.semibold))
                Text("Reading candidate \u{00B7} \(c.evidence.count) lenses measured")
                    .font(.caption).foregroundStyle(.secondary)
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

    private func evidence(_ c: Candidate) -> some View {
        InspectorSection(title: "Evidence") {
            if c.evidence.isEmpty {
                Text("The engine measured nothing notable.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(c.evidence.enumerated()), id: \.offset) { i, e in
                if i > 0 { Divider().padding(.vertical, 6) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: symbol(e)).font(.caption).foregroundStyle(tint(e))
                        Text(e.lens).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(strength(e)).font(.caption.weight(.medium))
                    }
                    if !e.detail.isEmpty { Text(e.detail).font(.callout) }
                    if !e.source.isEmpty {
                        Text(e.source).font(.caption2).foregroundStyle(.tertiary)
                    }
                    if e.effect == 0 {
                        Text("Shown, not scored. Your call.").font(.caption2).foregroundStyle(.secondary)
                    }
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

    /// Effect 0 is the designer's call, so it says so instead of a strength.
    private func strength(_ e: Evidence) -> String {
        e.effect == 0 ? "Your call" : e.strength.capitalized
    }

    private func shortlist(_ selected: Candidate?) -> some View {
        let list = model.shortlist("reading")
        return InspectorSection(title: "Shortlist \u{00B7} Reading", trailing: "\(list.count)") {
            if list.isEmpty {
                Text("Nothing yet. Add candidates you want to come back to. The shortlist is kept for this brand.")
                    .font(.callout).foregroundStyle(.secondary)
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
                }
            }
        }
    }

    @ViewBuilder
    private func action(_ selected: Candidate?) -> some View {
        let isChosen = selected.map { model.chosen(.reading) == $0.family } ?? false
        DecisionButton(title: isChosen ? "Chosen for Reading" : "Use for Reading",
                       disabled: selected == nil || isChosen) {
            if let c = selected { Task { await model.choose("reading", family: c.family) } }
        }
    }
}
