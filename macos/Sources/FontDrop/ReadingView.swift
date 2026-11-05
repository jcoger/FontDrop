import FontDropCore
import SwiftUI

/// Reading: a candidate list on the left, the stage on the right. The list is for choosing what to look at
/// (the faces themselves, two lines each). The stage is for judging it (the pair in a real layout).
///
/// React: a master-detail split. A virtual list with a roving selection, and a canvas that renders the selected item.
struct ReadingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ReadingList()
                    .frame(width: ReadingLayout.listWidth(for: geo.size.width))
                Divider()
                ReadingStage()
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .task(id: "\(model.brandID ?? 0)/\(model.displayFamily?.fontId ?? "none")/\(model.sourcesKey)") { await model.loadCandidates() }
    }
}

// MARK: - The list

struct ReadingList: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        let result = model.readingResult
        let rows = ReadingRows.rows(current: model.currentReadingCandidate, shown: result.shown, search: model.search)
        VStack(spacing: 0) {
            ReadingListHead(count: result.shown.count)
            Divider()
            listBody(rows: rows, result: result)
            Divider()
            ReadingListFoot(hidden: result.hidden)
        }
        .background(.background)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func listBody(rows: [Candidate], result: (shown: [Candidate], hidden: Int)) -> some View {
        if model.candidatesLoading && model.candidates.isEmpty {
            ProgressView(model.displayFamily.map { Lexicon.Reading.finding($0.name) } ?? "").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.candidatesError {
            ContentUnavailableView("Could not load candidates", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label(model.candidates.isEmpty ? Lexicon.Reading.findingNone : Lexicon.readingNone,
                      systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                if result.hidden > 0 { Text(Lexicon.Reading.hiddenByFilters(result.hidden)) }
            } actions: {
                if !model.lenses.isNeutral { Button(Lexicon.clearFilters) { model.resetLenses() } }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { c in row(c) }
                    }
                }
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { move(-1, rows) }
                .onKeyPress(.downArrow) { move(1, rows) }
                .onChange(of: model.selectedCandidate) { _, id in
                    if let id { proxy.scrollTo(id) }         // no animation: flipping candidates is a hard cut
                }
            }
        }
    }

    private func row(_ c: Candidate) -> some View {
        let family = model.familyByName[c.family]
        let onShortlist = model.shortlist("reading").contains(c.family)
        let isCurrent = model.chosen(.reading) == c.family
        return VStack(spacing: 0) {
            CandidateRow(candidate: c, family: family,
                         face: family.map { model.face("reading", $0) } ?? FaceSpec(path: c.filePath, settings: .defaults(job: "reading")),
                         tick: model.fontTick,
                         reasons: reasons(for: c, family: family),
                         isSelected: model.selectedCandidate == c.id, isCurrent: isCurrent, onShortlist: onShortlist)
            Divider()
        }
        .id(c.id)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedCandidate = c.id; focused = true }
        .contextMenu {
            Button(onShortlist ? Lexicon.Reading.removeFromShortlist : Lexicon.Reading.addToShortlist) {
                Task { await model.setShortlist("reading", family: c.family, on: !onShortlist) }
            }
            Button(Lexicon.useFor("reading")) { Task { await model.choose("reading", family: c.family) } }
        }
    }

    /// The row's quiet reasons: at most two, no reasons at all before there is a Display face to pair with.
    private func reasons(for c: Candidate, family: FamilySummary?) -> [String] {
        guard model.displayFamily != nil else { return [] }
        if c.isSameFamily { return [Lexicon.Reading.sameFamilyRow(c.bodyStyle?.label)] }
        return ReadingRows.reasons(c, xHeightNote: xHeightNote(c))
    }

    private func xHeightNote(_ c: Candidate) -> String? {
        guard let display = model.displayFamily else { return nil }
        let body = model.familyByName[c.family].map { model.face("reading", $0).resolvedPath } ?? c.filePath
        return measuredXHeightNote(display: model.face("display", display).resolvedPath, candidate: body)
    }

    private func move(_ step: Int, _ rows: [Candidate]) -> KeyPress.Result {
        guard model.comparedFamilies.isEmpty else { return .ignored }       // compare shows several; arrows do nothing
        if let id = ListNav.move(rows.map(\.id), from: model.selectedCandidate, by: step) { model.selectedCandidate = id }
        return .handled
    }
}

// MARK: - Row

/// One candidate: its name, two lines set in its own face at reading size, and at most two quiet reasons.
/// More reasons live in the inspector's Why list and in the hover help.
struct CandidateRow: View {
    let candidate: Candidate
    let family: FamilySummary?
    let face: FaceSpec
    let tick: Int
    let reasons: [String]
    let isSelected: Bool
    let isCurrent: Bool
    let onShortlist: Bool

    /// Rows set text at 15 to 16pt, whatever the playground size is, so rows compare fairly.
    private var ratio: CGFloat {
        let size = max(face.settings.size, 1)
        return CGFloat(min(max(size, 15), 16) / size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(candidate.family).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if isCurrent { Text(Lexicon.Reading.current).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                else if onShortlist { Text(Lexicon.Reading.onShortlistTag).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                if family?.isTrial == true { TagPill(text: Lexicon.Reading.trialTag) }
            }
            FaceText(face: face, text: SampleCopy.rowText, ratio: ratio, tick: tick)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !reasons.isEmpty {
                Text(reasons.joined(separator: " \u{00B7} ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .overlay(alignment: .leading) { if isSelected { Rectangle().fill(Color.accentColor).frame(width: 3) } }
        .help(hoverHelp)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var hoverHelp: String {
        let all = ReadingRows.dedupedEvidence(candidate.evidence).map { Lexicon.chip($0) }
        return all.isEmpty ? candidate.family : all.joined(separator: "\n")
    }
}

// MARK: - Head and foot

/// The list's head: what it is for, and the questions that filter it. Search stays in the window toolbar.
struct ReadingListHead: View {
    @Environment(AppModel.self) private var model
    let count: Int

    var body: some View {
        @Bindable var model = model
        let hasDisplay = model.displayFamily != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.displayFamily.map { Lexicon.Reading.title($0.name) } ?? Screen.reading.title)
                    .font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Text(countLine).font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
            FlowLayout(spacing: 6) {
                HeadMenu(title: Lexicon.Reading.sourceLabel, value: SourceScope(model.filter.sources).label) {
                    Picker(Lexicon.Reading.sourceLabel, selection: Binding(
                        get: { SourceScope(model.filter.sources) },
                        set: { if let s = $0.sources { model.filter.sources = s } })) {
                        ForEach(SourceScope.allCases.filter { $0 != .custom }) { Text($0.label).tag($0) }
                    }
                }
                if hasDisplay {
                    HeadMenu(title: Lexicon.contrastLabel, value: model.lenses.contrast.rawValue) {
                        Picker(Lexicon.contrastLabel, selection: $model.lenses.contrast) {
                            ForEach(ContrastLens.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    HeadMenu(title: Lexicon.structureLabel, value: model.lenses.structure.rawValue) {
                        Picker(Lexicon.structureLabel, selection: $model.lenses.structure) {
                            ForEach(StructureLens.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    HeadMenu(title: Lexicon.foundryLabel, value: model.lenses.foundry.rawValue) {
                        Picker(Lexicon.foundryLabel, selection: $model.lenses.foundry) {
                            ForEach(FoundryLens.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                }
                HeadMenu(title: Lexicon.sortLabel, value: model.effectiveLenses.sort.rawValue) {
                    Picker(Lexicon.sortLabel, selection: Binding(
                        get: { model.effectiveLenses.sort },
                        set: { model.lenses.sort = $0 })) {
                        ForEach(hasDisplay ? ReadingSort.allCases : ReadingSort.withoutDisplay) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                }
            }
            if !hasDisplay {
                Button(Lexicon.Reading.pickHeadline) { model.screen = .display }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var countLine: String {
        let n = model.shortlist("reading").count
        return n > 0 ? "\(count) \u{00B7} \(Lexicon.Reading.onShortlist(n))" : "\(count)"
    }
}

/// A small menu chip: "Difference: Distinct".
struct HeadMenu<Options: View>: View {
    let title: String
    let value: String
    @ViewBuilder var options: Options

    var body: some View {
        Menu {
            options.pickerStyle(.inline).labelsHidden()
        } label: {
            (Text(title + ": ").foregroundStyle(.secondary) + Text(value).fontWeight(.medium))
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.quaternary.opacity(0.7)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(title).accessibilityValue(value)
    }
}

/// Under the list: the long-text rule's count with its way out, what the filters hide, and Show more.
struct ReadingListFoot: View {
    @Environment(AppModel.self) private var model
    let hidden: Int

    var body: some View {
        let showUnfitRow = model.includeUnfitFaces || model.notForLongText > 0
        if showUnfitRow || hidden > 0 || model.candidatesHasMore {
            VStack(alignment: .leading, spacing: 4) {
                if showUnfitRow {
                    HStack(spacing: 6) {
                        Text(model.includeUnfitFaces ? Lexicon.Reading.showingAll : Lexicon.Finder.notForLongText(model.notForLongText))
                            .foregroundStyle(.secondary)
                            .help(Lexicon.readingFixedWhy)
                        Button(model.includeUnfitFaces ? Lexicon.Reading.onlyFit : Lexicon.showThem) {
                            Task { await model.setIncludeUnfit(!model.includeUnfitFaces) }
                        }
                        .buttonStyle(.link)
                    }
                }
                if hidden > 0 {
                    HStack(spacing: 6) {
                        Text(Lexicon.Reading.hiddenByFilters(hidden)).foregroundStyle(.secondary)
                        Button(Lexicon.clearFilters) { model.resetLenses() }.buttonStyle(.link)
                    }
                }
                if model.candidatesHasMore {
                    Button(Lexicon.showMore) { Task { await model.showMoreCandidates() } }
                        .buttonStyle(.link).disabled(model.candidatesLoading)
                }
            }
            .font(.caption)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
        }
    }
}

extension AppModel {
    func resetLenses() {
        lenses.contrast = .any; lenses.structure = .any; lenses.foundry = .any
    }
}

/// "x-height 9% smaller than Display", measured from the two loaded fonts so it has a direction.
/// Shared by the list rows and the inspector's Why list so both say the same number.
func measuredXHeightNote(display: String, candidate: String) -> String? {
    guard case .success(let d)? = FontLoader.shared.cached(display),
          case .success(let c)? = FontLoader.shared.cached(candidate), d.xHeightRatio > 0 else { return nil }
    let diff = (c.xHeightRatio / d.xHeightRatio - 1) * 100
    if abs(diff) < 1 { return "Same x-height" }
    return "x-height \(Int(abs(diff).rounded()))% \(diff < 0 ? "smaller" : "larger") than Display"
}
