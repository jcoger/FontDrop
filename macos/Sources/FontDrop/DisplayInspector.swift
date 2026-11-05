import FontDropCore
import SwiftUI

/// The Display inspector, in the Instrument look and in the IA spec's order, one job per module:
/// 01 Sample (the line the cards draw), 02 Face (Style, then "Spacing and features"), 03 Alternates (stylistic
/// sets as glyphs), 04 Letters (the shapes that tell faces apart). Save and Hide live on the card (hover star,
/// context menu), not here. "Use for Display" stays the one prominent button.
struct FamilyInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let screen: Screen

    var body: some View {
        if let name = model.selectedFamily, let family = model.familyByName[name] {
            let job = screen.job ?? "display"
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(family, job: job)
                    InspectorSection(title: "01 \u{00B7} \(Lexicon.R4.sample)") { SampleModule(job: job, family: family) }
                    InspectorSection(title: "02 \u{00B7} \(Lexicon.Why.face)") {
                        PlaygroundGroup(job: job, family: family, title: family.name, preview: "", startOpen: true, mode: .face)
                    }
                    InspectorSection(title: "03 \u{00B7} \(Lexicon.R4.alternates)") { AlternatesModule(job: job, family: family) }
                    InspectorSection(title: "04 \u{00B7} \(Lexicon.Why.letters)") {
                        LettersStrip(face: model.face(job, family), tick: model.fontTick)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 52).padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) { action(family).background(.ultraThinMaterial) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.choices[screen.job ?? ""] == family.name)
        } else {
            ContentUnavailableView(Lexicon.R4.noSelection, systemImage: "textformat",
                                   description: Text(Lexicon.R4.noSelectionHelp))
        }
    }

    /// The name, then a quiet label line: its job here, how many styles, Trial, and where to get it.
    private func header(_ family: FamilySummary, job: String) -> some View {
        let isCurrent = model.choices[job] == family.name
        var parts = [isCurrent ? Lexicon.R4.currentTitle(job) : Lexicon.R4.candidateTitle(job), Lexicon.Why.styles(Int(family.styleCount))]
        if family.isTrial { parts.append(Lexicon.Reading.trialTag) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(family.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.textPrimary.color)
            Text(parts.joined(separator: " \u{00B7} ")).moduleLabel()
            if let urlText = family.foundryUrl, let url = URL(string: urlText) {
                Link(family.isTrial ? Lexicon.getLicense : (url.host() ?? Lexicon.R4.foundryPage), destination: url)
                    .font(.system(size: 13)).foregroundStyle(theme.textSecondary.color).lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func action(_ family: FamilySummary) -> some View {
        if let job = screen.job {
            if model.choices[job] == family.name {
                ChosenPanel(job: job,
                            nextTitle: job == "display" ? Lexicon.findText : nil,
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

/// Module 01: the face set in the sample line, and one field to type your own. Empty puts the brand name back.
struct SampleModule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let job: String
    let family: FamilySummary

    var body: some View {
        let face = model.face(job, family)
        VStack(alignment: .leading, spacing: 10) {
            FaceText(face: face, text: model.sampleText, ratio: CGFloat(44 / max(face.settings.size, 1)),
                     tick: model.fontTick, useLineHeight: false)
                .lineLimit(1).minimumScaleFactor(0.3)
                .foregroundStyle(theme.textPrimary.color)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .padding(.horizontal, 14)
                .recessed(radius: 12)
                .accessibilityLabel(model.sampleText)
            HStack(spacing: 6) {
                TextField(Lexicon.R4.samplePlaceholder, text: Binding(get: { model.customSample ?? "" }, set: { model.setSample($0) }),
                          axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .lineLimit(1...3)
                    .accessibilityLabel(Lexicon.R4.sample)
                if model.customSample != nil {
                    Button { model.setSample("") } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(theme.textSecondary.color)
                        .help(Lexicon.R4.sampleClear)
                        .accessibilityLabel(Lexicon.R4.sampleClear)
                }
            }
        }
    }
}
