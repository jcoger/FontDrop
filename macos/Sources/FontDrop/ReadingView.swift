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
                ReadingStage()
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .task(id: "\(model.brandID ?? 0)/\(model.displayFamily?.fontId ?? "none")/\(model.sourcesKey)/\(model.lenses.sort == .characterFirst)") { await model.loadCandidates() }
    }
}

// MARK: - The list

struct ReadingList: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @Namespace private var glide
    @State private var keyboardNav = false       // the focus ring shows once the arrow keys are used, not after a click

    var body: some View {
        let result = model.readingResult
        let rows = ReadingRows.rows(current: model.currentReadingCandidate, shown: result.shown, search: model.search)
        VStack(spacing: 0) {
            ReadingListHead(count: result.shown.count)
            listBody(rows: rows, result: result)
            ReadingListFoot(hidden: result.hidden)
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func listBody(rows: [Candidate], result: (shown: [Candidate], hidden: Int)) -> some View {
        if model.scanningEmptyLibrary && model.candidates.isEmpty {
            ProgressView(Lexicon.Scan.scanningFonts)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.readingIsLoading && model.candidates.isEmpty {
            ProgressView(model.displayFamily.map { Lexicon.Reading.finding($0.name) } ?? Lexicon.Reading.findingFaces)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.candidatesError {
            EmptyScreen(label: Lexicon.R9.couldNotLoadLabel, line: error)
        } else if rows.isEmpty {
            EmptyScreen(label: Lexicon.R9.noMatchesLabel,
                        line: ([model.candidates.isEmpty ? Lexicon.Reading.findingNone : Lexicon.readingNone]
                               + (result.hidden > 0 ? [Lexicon.Reading.hiddenByFilters(result.hidden) + "."] : [])).joined(separator: " "),
                        actionTitle: model.lenses.isNeutral ? nil : Lexicon.clearFilters,
                        action: model.lenses.isNeutral ? nil : { model.resetLenses() })
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { c in row(c) }
                    }
                    .padding(8)
                    .environment(\.glide, glide)
                }
                .focusable()
                .focused($focused)
                .focusEffectDisabled()      // the ring is drawn on the row (CandidateRow), distinct from the pill
                .onKeyPress(.upArrow) { move(-1, rows) }
                .onKeyPress(.downArrow) { move(1, rows) }
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.isEmpty, model.canUseSelected else { return .ignored }
                    Task { await model.useSelected() }
                    return .handled
                }
                .onKeyPress(keys: [.space]) { press in
                    guard press.modifiers.isEmpty, model.selectedFaceName != nil else { return .ignored }
                    model.togglePreview()
                    return .handled
                }
                .onChange(of: model.focusListTick) { _, _ in focused = true }
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
        return CandidateRow(candidate: c, family: family,
                            face: family.map { model.face("reading", $0) } ?? FaceSpec(path: c.filePath, settings: .defaults(job: "reading")),
                            tick: model.fontTick,
                            reasons: reasons(for: c, family: family),
                            isSelected: model.selectedCandidate == c.id, isCurrent: isCurrent, onShortlist: onShortlist,
                            showFocus: keyboardNav && focused)
        .id(c.id)
        .contentShape(Rectangle())
        .onTapGesture { keyboardNav = false; model.selectedCandidate = c.id; focused = true }
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
        keyboardNav = true
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
    var showFocus = false
    @Environment(\.theme) private var theme

    /// Rows set text at 15 to 16pt, whatever the playground size is, so rows compare fairly.
    private var ratio: CGFloat {
        let size = max(face.settings.size, 1)
        return CGFloat(min(max(size, 15), 16) / size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(candidate.family).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(theme.textPrimary.color)
                Spacer(minLength: 4)
                if isCurrent { Text(Lexicon.Reading.current).font(.system(size: 11)).foregroundStyle(theme.textSecondary.color) }
                else if onShortlist { Text(Lexicon.Reading.onShortlistTag).font(.system(size: 11)).foregroundStyle(theme.textSecondary.color) }
                if family?.isTrial == true { TagPill(text: Lexicon.Reading.trialTag) }
            }
            FaceText(face: face, text: SampleCopy.rowText, ratio: ratio, tick: tick)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !reasons.isEmpty {
                Text(reasons.joined(separator: " \u{00B7} ")).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color).lineLimit(1)
            }
        }
        .foregroundStyle(theme.textPrimary.color)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SelectionPill(on: isSelected))
        .overlay {
            if showFocus && isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
            }
        }
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
    @Environment(\.theme) private var theme
    let count: Int

    var body: some View {
        @Bindable var model = model
        let hasDisplay = model.displayFamily != nil
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayFamily.map { Lexicon.Reading.title($0.name) } ?? Screen.reading.title)
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(theme.textPrimary.color)
                Text(countLine).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color).lineLimit(1).monospacedDigit()
            }
            SearchField(prompt: Lexicon.Reading.searchPrompt)
            // One row (board 17): every question that narrows the list in one "Filters · n" menu, then Sort.
            HStack(spacing: 6) {
                let active = ReadingFilterCount.active(sources: model.filter.sources, lenses: model.lenses, hasDisplay: hasDisplay)
                Menu {
                    Section(Lexicon.Reading.sourceLabel) {
                        Picker(Lexicon.Reading.sourceLabel, selection: Binding(
                            get: { SourceScope(model.filter.sources) },
                            set: { if let s = $0.sources { model.filter.sources = s } })) {
                            ForEach(SourceScope.allCases.filter { $0 != .custom }) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline).labelsHidden()
                    }
                    if hasDisplay {
                        Section(Lexicon.contrastLabel) {
                            Picker(Lexicon.contrastLabel, selection: $model.lenses.contrast) {
                                ForEach(ContrastLens.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.inline).labelsHidden()
                        }
                        Section(Lexicon.structureLabel) {
                            Picker(Lexicon.structureLabel, selection: $model.lenses.structure) {
                                ForEach(StructureLens.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.inline).labelsHidden()
                        }
                        Section(Lexicon.foundryLabel) {
                            Picker(Lexicon.foundryLabel, selection: $model.lenses.foundry) {
                                ForEach(FoundryLens.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.inline).labelsHidden()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Lexicon.R4.filters(active)).font(.system(size: 12)).foregroundStyle(theme.textPrimary.color)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textSecondary.color)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .pill()
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(Lexicon.R4.filtersHelp)
                .accessibilityLabel("Filters").accessibilityValue(active == 0 ? "none" : "\(active) on")
                HeadMenu(title: Lexicon.sortLabel, value: model.effectiveLenses.sort.rawValue, showTitle: false) {
                    Picker(Lexicon.sortLabel, selection: Binding(
                        get: { model.effectiveLenses.sort },
                        set: { model.lenses.sort = $0 })) {
                        ForEach(hasDisplay ? ReadingSort.allCases : ReadingSort.withoutDisplay) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if !hasDisplay {
                Button(Lexicon.Reading.pickHeadline) { model.screen = .display }
                    .buttonStyle(.themeLink).font(.caption)
            }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
    }

    private var countLine: String {
        let n = model.shortlist("reading").count
        return n > 0 ? "\(Lexicon.Reading.facesCount(count)) \u{00B7} \(Lexicon.Reading.onShortlist(n))" : Lexicon.Reading.facesCount(count)
    }
}

/// A small menu chip: "Difference: Distinct".
struct HeadMenu<Options: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: String
    var showTitle = true
    @ViewBuilder var options: Options

    var body: some View {
        Menu {
            options.pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: 4) {
                (Text(showTitle ? title + " \u{00B7} " : "").foregroundStyle(theme.textSecondary.color) + Text(value).foregroundStyle(theme.textPrimary.color))
                    .font(.system(size: 12)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textSecondary.color)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .pill()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(title).accessibilityValue(value)
    }
}

/// Under the list: the long-text rule's count with its way out, what the filters hide, and Show more.
struct ReadingListFoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let hidden: Int

    var body: some View {
        let showUnfitRow = model.includeUnfitFaces || model.notForLongText > 0
        if showUnfitRow || hidden > 0 || model.candidatesHasMore {
            VStack(alignment: .leading, spacing: 4) {
                if showUnfitRow {
                    HStack(spacing: 6) {
                        Text(model.includeUnfitFaces ? Lexicon.Reading.showingAll : Lexicon.Finder.notForLongText(model.notForLongText))
                            .foregroundStyle(theme.textSecondary.color)
                            .help(Lexicon.readingFixedWhy)
                        Button(model.includeUnfitFaces ? Lexicon.Reading.onlyFit : Lexicon.showThem) {
                            Task { await model.setIncludeUnfit(!model.includeUnfitFaces) }
                        }
                        .buttonStyle(.themeLink)
                    }
                }
                if hidden > 0 {
                    HStack(spacing: 6) {
                        Text(Lexicon.Reading.hiddenByFilters(hidden)).foregroundStyle(theme.textSecondary.color)
                        Button(Lexicon.clearFilters) { model.resetLenses() }.buttonStyle(.themeLink)
                    }
                }
                if model.candidatesHasMore {
                    Button(Lexicon.showMore) { Task { await model.showMoreCandidates() } }
                        .buttonStyle(.themeLink).disabled(model.candidatesLoading)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
        }
    }
}

/// The "n" in "Filters · n": how many of the head's questions are narrowing the list. Source counts when it is not
/// the standard Your fonts + Google. Difference, Structure and Foundry count when they are not Any, and only once a
/// Display face exists (before that the list has no such questions).
enum ReadingFilterCount {
    static func active(sources: Set<Source>, lenses: Lenses, hasDisplay: Bool) -> Int {
        var n = SourceScope(sources) == .yoursAndGoogle ? 0 : 1
        if hasDisplay {
            if lenses.contrast != .any { n += 1 }
            if lenses.structure != .any { n += 1 }
            if lenses.foundry != .any { n += 1 }
        }
        return n
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
