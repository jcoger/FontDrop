import CoreText
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
        let job = screen.job ?? "display"
        if let family = model.inspectedFamily(job: job) {
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
            .animation(Motion.ok(Motion.quick), value: model.choices[screen.job ?? ""] == family.name)
        } else {
            EmptyScreen(label: Lexicon.R4.noSelection, line: Lexicon.R4.noSelectionHelp)
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
            SampleField(face: face, text: model.sampleText, tick: model.fontTick)
                .foregroundStyle(theme.textPrimary.color)
                .frame(height: SampleFit.fieldHeight)
                .frame(maxWidth: .infinity)
                .recessed(radius: 12)
                .accessibilityElement(children: .ignore)
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

/// The number behind the Sample field: how far the line is scaled to fit. (Its letters, not its line box, are centred
/// by a baseline alignment guide in `SampleField`.)
enum SampleFit {
    static let fieldHeight: CGFloat = 76
    static let sidePadding: CGFloat = 16
    static let baseSize: CGFloat = 44

    /// 1 when the line fits in `width`; else the factor that makes it fit on one line.
    static func scale(lineWidth: CGFloat, width: CGFloat) -> CGFloat {
        guard lineWidth > width, lineWidth > 0 else { return 1 }
        return max(0.05, width / lineWidth)
    }
}

/// The big sample line. One line, left aligned, scaled down to fit the field's width, and centred vertically on its letters.
struct SampleField: View {
    let face: FaceSpec
    let text: String
    let tick: Int

    var body: some View {
        GeometryReader { geo in
            let ratio0 = SampleFit.baseSize / max(CGFloat(face.settings.size), 1)
            let width = geo.size.width - SampleFit.sidePadding * 2
            if let base = FontLoader.shared.styledFont(face, ratio: ratio0) {
                let size = CTFontGetSize(base)
                let kern = CGFloat(face.settings.tracking) * size
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: base, .kern: kern]))
                let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                let s = SampleFit.scale(lineWidth: lineWidth, width: width)
                let font = s < 0.999 ? CTFontCreateCopyWithAttributes(base, size * s, nil, nil) : base
                let cap = CTFontGetCapHeight(font)
                FaceText(face: face, text: text, ratio: ratio0 * s, tick: tick, useLineHeight: false)
                    .lineLimit(1).fixedSize()
                    // The view's own baseline, not a line-box guess: the capital band's middle sits on the frame's middle.
                    .alignmentGuide(VerticalAlignment.center) { d in d[VerticalAlignment.firstTextBaseline] - cap / 2 }
                    .frame(width: width, height: geo.size.height, alignment: .leading)
                    .padding(.leading, SampleFit.sidePadding)
            } else {
                FaceText(face: face, text: text, ratio: ratio0, tick: tick, useLineHeight: false)
                    .lineLimit(1)
                    .frame(width: width, height: geo.size.height, alignment: .leading)
                    .padding(.leading, SampleFit.sidePadding)
            }
        }
    }
}
