import FontDropCore
import SwiftUI

/// The Text inspector, in the order the look spec sets: the scale readout line, 01 why it pairs, 02 face,
/// 03 letters. The shortlist and "Use for Text" live on the stage. The sample-text playground left (IA ledger).
struct ReadingInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var showSources = false
    var body: some View {
        @Bindable var model = model
        let selected = model.candidate(model.selectedCandidate)
        if let c = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(c)
                    SectionRule().padding(.top, 16)
                    ScaleReadoutLine(open: $model.textScaleOpen).padding(.vertical, 16)
                    if model.textScaleOpen { ScaleModule(family: c.family, fallbackPath: c.filePath, inline: true).padding(.bottom, 16) }
                    if model.displayFamily != nil { whyModule(c) }
                    faceModule(c)
                    lettersModule(c)
                }
                .padding(.horizontal, 20).padding(.top, Metrics.inspectorTop).padding(.bottom, 24)
            }
        } else {
            EmptyScreen(label: Lexicon.R9.nothingSelected, line: Lexicon.R9.inspectorEmptyLine, compact: true)
        }
    }

    private func header(_ c: Candidate) -> some View {
        let isCurrent = model.chosen(.reading) == c.family
        return VStack(alignment: .leading, spacing: 6) {
            Text(c.family).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.textPrimary.color)
            Text(isCurrent ? Lexicon.Reading.currentTitle : Lexicon.Reading.candidateTitle).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
        }
    }

    // MARK: 01 Why it pairs

    private func whyModule(_ c: Candidate) -> some View {
        let family = model.familyByName[c.family]
        let summary = WhySummary.make(c, styleCount: Int(family?.styleCount ?? 0), xHeightNote: inspectorXHeightNote(c))
        return InspectorSection(title: Lexicon.whyItPairs) {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary.verdict).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if !summary.chips.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(summary.chips.enumerated()), id: \.offset) { _, chip in
                            Text(chip.text).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button { withAnimationIfAllowed { showSources.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(Lexicon.Why.sources)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(showSources ? 90 : 0))
                    }
                    .font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showSources ? "expanded" : "collapsed")
                if showSources { sources(c) }
            }
        }
    }

    private func inspectorXHeightNote(_ c: Candidate) -> String? {
        guard let display = model.displayFamily else { return nil }
        let body = model.familyByName[c.family].map { model.face("reading", $0) }
            ?? FaceSpec(path: c.filePath, settings: .defaults(job: "reading"))
        return measuredXHeightNote(display: model.face("display", display).resolvedPath, candidate: body.resolvedPath)
    }

    /// Every piece of evidence with its sources: the technical detail the verdict and chips leave out.
    private func sources(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if c.evidence.isEmpty {
                Text(Lexicon.Why.nothingNotable).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
            }
            ForEach(Array(c.evidence.enumerated()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: symbol(e)).font(.system(size: 11)).foregroundStyle(theme.textSecondary.color)
                        Text(Lexicon.whyTitle(e)).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
                        if let term = Lexicon.term(forLens: e.lens) { HelpButton(term: term) }
                        Spacer()
                    }
                    let detail = e.lens == "x-height" ? (inspectorXHeightNote(c) ?? Lexicon.whyDetail(e)) : Lexicon.whyDetail(e)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 13)).foregroundStyle(theme.textPrimary.color)
                            .help(e.lens == "Recommended for text" ? Lexicon.recommendedBy(Lexicon.sources(e.source)) : "")
                    }
                    if e.effect == 0 {
                        Text(Lexicon.notScored).font(.system(size: 11)).foregroundStyle(theme.textSecondary.color)
                    } else {
                        let word = Lexicon.strength(e.strength)
                        Text([word, Lexicon.strengthHelp[word]].compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(.system(size: 11)).foregroundStyle(theme.textSecondary.color)
                    }
                    let names = Lexicon.sources(e.source)
                    if !names.isEmpty { Text(names).font(.system(size: 11)).foregroundStyle(theme.textSecondary.color) }
                }
            }
        }
        .padding(.top, 4)
    }

    private func symbol(_ e: Evidence) -> String {
        e.effect > 0 ? "plus.circle" : e.effect < 0 ? "minus.circle" : "circle.dashed"
    }

    // MARK: 02 Face

    @ViewBuilder
    private func faceModule(_ c: Candidate) -> some View {
        if let family = model.familyByName[c.family] {
            InspectorSection(title: Lexicon.Why.face) {
                PlaygroundGroup(job: "reading", family: family, title: family.name, preview: "", startOpen: true, mode: .face)
            }
        }
    }

    // MARK: 03 Letters

    @ViewBuilder
    private func lettersModule(_ c: Candidate) -> some View {
        if let family = model.familyByName[c.family] {
            InspectorSection(title: Lexicon.Why.letters) {
                LettersStrip(face: model.face("reading", family), tick: model.fontTick)
            }
        }
    }
}

// MARK: - Why it pairs, as data

/// The verdict sentence and up to two chips for a candidate, built from the evidence the engine already
/// produced. No ranking happens here. Pure, so a test can read it.
struct WhySummary: Equatable {
    struct Chip: Equatable { var text: String; var effect: Int8; var warning: Bool }
    var verdict: String
    var chips: [Chip]

    static func make(_ c: Candidate, styleCount: Int, xHeightNote: String?) -> WhySummary {
        if c.isSameFamily {
            var chips: [Chip] = []
            if styleCount > 0 { chips.append(Chip(text: Lexicon.Why.styles(styleCount), effect: 1, warning: false)) }
            if let body = c.bodyStyle?.label { chips.append(Chip(text: Lexicon.bodyIn(body), effect: 1, warning: false)) }
            return WhySummary(verdict: Lexicon.Why.sameFamilyVerdict, chips: Array(chips.prefix(2)))
        }
        let all = ReadingRows.dedupedEvidence(c.evidence)
        let scored = all.filter { $0.effect != 0 }
        guard let lead = scored.first ?? all.first else {
            return WhySummary(verdict: Lexicon.Why.nothingNotable, chips: [])
        }
        func words(_ e: Evidence) -> String { Lexicon.chip(e, xHeightNote: e.lens == "x-height" ? xHeightNote : nil) }
        let verdict = "\(Lexicon.whyTitle(lead)). \(Lexicon.sentenceEnd(words(lead)))"
        let rest = all.filter { $0.lens != lead.lens || $0.detail != lead.detail }.prefix(2).map { e in
            Chip(text: words(e), effect: e.effect, warning: e.lens == "The middle" || e.lens == "Near-duplicate")
        }
        return WhySummary(verdict: verdict, chips: Array(rest))
    }
}

// MARK: - Scale readout line

/// The top of the Text inspector: a recessed screen with the brand's scale. Clicking it opens the full Scale module
/// under it (the same `ScaleModule` Set uses, on the same store), and clicking again closes it. R9a reversed the old
/// "the dial lives on Set": the designer wants to change the scale while reading the essay.
struct ScaleReadoutLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Binding var open: Bool

    var body: some View {
        let scale = model.scale
        Button { withAnimationIfAllowed { open.toggle() } } label: {
            HStack(spacing: 10) {
                Text(Lexicon.Scale.title).moduleLabel()
                if !open {          // open, the dial below says it
                    Text(Lexicon.Scale.readoutLine(scale)).font(InstrumentFonts.doto(18)).foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                SignalLight(lit: scale.locked)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.textSecondary.color)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.horizontal, open ? 0 : 14).frame(height: open ? 20 : 44)
            .background { if !open { Color.clear.recessed(radius: 12) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Lexicon.Scale.readoutHelp)
        .accessibilityLabel(Lexicon.Scale.readoutAccessibility(scale))
        .accessibilityValue(open ? "expanded" : "collapsed")
        .accessibilityHint(Lexicon.Scale.readoutHelp)
    }
}

// MARK: - Letters strip

/// Four recessed tiles of the letters that tell faces apart, set in the candidate: Il1, ag, RGQ, 0O.
struct LettersStrip: View {
    @Environment(\.theme) private var theme
    let face: FaceSpec
    let tick: Int

    static let samples = ["Il1", "ag", "RGQ", "0O"]

    var body: some View {
        let ratio = CGFloat(21 / max(face.settings.size, 1))
        HStack(spacing: 8) {
            ForEach(Self.samples, id: \.self) { sample in
                FaceText(face: face, text: sample, ratio: ratio, tick: tick, useLineHeight: false)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(theme.textPrimary.color)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .well(radius: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Lexicon.Why.lettersAccessibility(Self.samples))
    }
}

// MARK: - Set inspector

/// The Set screen's inspector: the brand, then 01 Scale (dial, Body, footer), 02 Text (Measure, Line height) and 03 Faces (axes).
struct SetInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.brand?.name ?? "FontDrop").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.textPrimary.color)
                    Text(Lexicon.Scale.setSubtitle).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
                }
                if let reading = model.readingFamily {
                    ScaleModule(family: reading.name, fallbackPath: reading.filePath)
                    TextModule()
                    FacesModule()
                } else {
                    EmptyScreen(label: Lexicon.Scale.title, line: Lexicon.Scale.needsText,
                                actionTitle: Lexicon.SetScreen.goToText, actionHint: "\u{2318}2", actionHelp: Lexicon.SetScreen.goToTextHelp,
                                action: { model.screen = .reading }, compact: true)
                        .frame(minHeight: 240)
                }
            }
            .padding(.horizontal, 20).padding(.top, Metrics.inspectorTop).padding(.bottom, 24)
        }
    }
}
