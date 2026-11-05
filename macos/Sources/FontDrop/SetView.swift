import CoreText
import FontDropCore
import SwiftUI

/// The Set screen (board 04): the brand's pair at every step of the scale. Each row names the step, its size in
/// points and the face that sets it, then shows a real line of text at that size. The Body row is a paragraph at the
/// brand's measure and line height. It updates as the dial, Body, Measure and Line height move.
///
/// A row that is too wide for the stage shrinks its preview, never its numbers: the label still says the true size.
/// React: a table of rows, each computing its own `transform: scale()` from the width it was given.
struct SetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private let labelWidth: CGFloat = 148
    private let gutter: CGFloat = 20
    private let pad: CGFloat = 28
    /// Under this stage width the label sits above its specimen, so the specimen keeps the whole column.
    private let stackBelow: CGFloat = 760

    private func isStacked(_ width: CGFloat) -> Bool { width < stackBelow }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content(width: geo.size.width)
                    .frame(width: geo.size.width, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.stage.color)
        .overlay(alignment: .top) { SetBar() }
        // The saved style (a heavy cut, say) may not be loaded yet. Without its file the text draws invisibly.
        .task(id: "\(model.displayFamily?.name ?? "")/\(model.readingFamily?.name ?? "")") {
            await model.preloadStyles(of: [model.displayFamily?.name, model.readingFamily?.name].compactMap { $0 })
        }
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        let tick = model.fontTick
        let display = model.displayFamily, reading = model.readingFamily
        if display == nil && reading == nil {
            EmptyScreen(label: Lexicon.SetScreen.neitherLabel, line: Lexicon.SetScreen.neitherLine,
                        actionTitle: Lexicon.SetScreen.goToDisplay, actionHint: "\u{2318}1", actionHelp: Lexicon.SetScreen.goToDisplayHelp,
                        action: { model.screen = .display })
                .frame(minHeight: 420)
        } else {
            // One face is enough to start: its steps are drawn, and the other face's steps hold a quiet row that says so.
            let sizes = reading.map { SetSizes.resolve(model: model, reading: $0) } ?? SetSizes.fromScale(model.scale)
            let displayFace = display.map { model.face("display", $0) }, textFace = reading.map { model.face("reading", $0) }
            let displayWho = display.flatMap { d in displayFace.map { (Lexicon.SetScreen.faceAndStyle(d.name, model.styleLabel($0, family: d.name)), $0) } }
            let textWho = reading.flatMap { r in textFace.map { (Lexicon.SetScreen.faceAndStyle(r.name, model.styleLabel($0, family: r.name)), $0) } }
            let stacked = isStacked(width)
            let specWidth = max(width - 2 * pad - (stacked ? 0 : labelWidth + gutter), 120)
            VStack(alignment: .leading, spacing: 0) {
                Text(display != nil && reading != nil
                     ? Lexicon.SetScreen.stageTitle(display: display!.name, text: reading!.name)
                     : Lexicon.SetScreen.stageTitleOne((display ?? reading)!.name))
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.textPrimary.color)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
                ForEach(ScaleStep.stageOrder) { step in
                    if let who = step.isDisplayFace ? displayWho : textWho {
                        row(step, sizes: sizes, who: who, specWidth: specWidth, stacked: stacked, tick: tick)
                    } else {
                        missingRow(step, sizes: sizes, stacked: stacked)
                    }
                }
                scaledNote(sizes: sizes, display: displayFace, text: textFace, specWidth: specWidth)
            }
            .padding(.horizontal, pad).padding(.top, 52).padding(.bottom, 32)
        }
    }

    /// The row for a step whose face is not chosen yet: the same label, and one quiet line with the way to choose it.
    private func missingRow(_ step: ScaleStep, sizes: SetSizes, stacked: Bool) -> some View {
        let needsDisplay = step.isDisplayFace
        let label = VStack(alignment: .leading, spacing: 3) {
            Text("\(step.label) \u{00B7} \(Lexicon.SetScreen.points(sizes.size(step)))").moduleLabel().lineLimit(1).minimumScaleFactor(0.7)
        }
        let chooser = HStack(spacing: 10) {
            Text(needsDisplay ? Lexicon.SetScreen.chooseDisplay : Lexicon.SetScreen.chooseText)
                .font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
            Button(needsDisplay ? Lexicon.SetScreen.goToDisplay : Lexicon.SetScreen.goToText) {
                model.screen = needsDisplay ? .display : .reading
            }
            .buttonStyle(.themeLink).font(.system(size: 13))
            .help(needsDisplay ? Lexicon.SetScreen.goToDisplayHelp : Lexicon.SetScreen.goToTextHelp)
            Text(needsDisplay ? "\u{2318}1" : "\u{2318}2").moduleLabel()
        }
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.sliderTrack.color).frame(height: 1)
            if stacked {
                VStack(alignment: .leading, spacing: 8) { label; chooser }.padding(.vertical, 14)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: gutter) {
                    label.frame(width: labelWidth, alignment: .leading)
                    chooser
                }
                .padding(.vertical, 14)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    private func line(for step: ScaleStep) -> String { step.sampleLine }

    private func row(_ step: ScaleStep, sizes: SetSizes, who: (name: String, face: FaceSpec),
                     specWidth: CGFloat, stacked: Bool, tick: Int) -> some View {
        let pt = sizes.size(step)
        let plan = SetRowPlan.make(step: step, pt: pt, face: who.face, text: line(for: step), specWidth: Double(specWidth), sizes: sizes)
        let specimen = FaceText(face: who.face, text: line(for: step), ratio: CGFloat(plan.drawnPt / max(who.face.settings.size, 1)),
                                tick: tick, trackBias: 0, leading: plan.leading)
            .lineLimit(step == .body ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: CGFloat(plan.drawnWidth ?? Double(specWidth)), alignment: .leading)
            .foregroundStyle(theme.textPrimary.color)
            .accessibilityLabel("\(step.label), \(Lexicon.SetScreen.points(pt)), \(who.name)")
            .accessibilityValue(line(for: step))
        let label = VStack(alignment: .leading, spacing: 3) {
            Text("\(step.label) \u{00B7} \(Lexicon.SetScreen.points(pt))").moduleLabel().lineLimit(1).minimumScaleFactor(0.7)
            if step == .body {
                Text("\(sizes.measure) \(Lexicon.SetScreen.measureUnit) \u{00B7} " + String(format: "%.2f", sizes.lineHeight))
                    .moduleLabel()
            }
            Text(who.name).font(.system(size: 11)).foregroundStyle(theme.textSecondary.color)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.sliderTrack.color).frame(height: 1)
            if stacked {
                VStack(alignment: .leading, spacing: 8) { label; specimen }.padding(.vertical, 14)
            } else {
                HStack(alignment: .top, spacing: gutter) {
                    label.frame(width: labelWidth, alignment: .leading).padding(.top, 4)
                    specimen
                }
                .padding(.vertical, 14)
            }
        }
    }

    /// One quiet line when any preview was scaled to fit.
    @ViewBuilder
    private func scaledNote(sizes: SetSizes, display: FaceSpec?, text: FaceSpec?, specWidth: CGFloat) -> some View {
        let scaled = ScaleStep.stageOrder.contains { step in
            guard let face = step.isDisplayFace ? display : text else { return false }
            return SetRowPlan.make(step: step, pt: sizes.size(step), face: face, text: line(for: step),
                                   specWidth: Double(specWidth), sizes: sizes).factor < 0.999
        }
        if scaled {
            Text(Lexicon.SetScreen.previewScaled).moduleLabel().padding(.top, 12)
        }
    }
}

/// The sizes Set draws: body and ratio as the Scale module reads them (locked: the brand's; Auto: what Fit solved to),
/// and the measure and line height for body text.
struct SetSizes {
    var body: Double
    var ratio: Double
    var measure: Int
    var lineHeight: Double

    func size(_ step: ScaleStep) -> Double { body * pow(ratio, Double(step.rawValue)) }

    /// No Text face to fit against: the brand's own body and ratio, as saved.
    @MainActor
    static func fromScale(_ scale: TypeScale) -> SetSizes {
        SetSizes(body: scale.body, ratio: scale.ratio, measure: TextRules.measure(scale), lineHeight: TextRules.lineHeight(scale))
    }

    @MainActor
    static func resolve(model: AppModel, reading: FamilySummary) -> SetSizes {
        let scale = model.scale
        let solved = model.solvedSizes(reading: reading.name, fallbackPath: reading.filePath)
        let auto = solved.flatMap { DialMath.autoRatio(headline: $0.headline, body: $0.body, steps: $0.headlineStep) }
        return SetSizes(body: scale.locked ? scale.body : (solved?.body ?? scale.body),
                        ratio: scale.locked ? scale.ratio : (auto ?? scale.ratio),
                        measure: TextRules.measure(scale), lineHeight: TextRules.lineHeight(scale))
    }
}

/// How one row is drawn: the leading, the preview factor that makes it fit, and the width it takes.
struct SetRowPlan {
    var leading: Double
    /// 1 when the row fits at its true size.
    var factor: Double
    /// The point size actually drawn (true size times the factor).
    var drawnPt: Double
    /// The column width for the body paragraph; nil for one-line rows.
    var drawnWidth: Double?

    @MainActor
    static func make(step: ScaleStep, pt: Double, face: FaceSpec, text: String, specWidth: Double, sizes: SetSizes) -> SetRowPlan {
        let base = max(face.settings.size, 1)
        guard let first = FontLoader.shared.styledFont(face, ratio: CGFloat(pt / base)) else {
            return SetRowPlan(leading: 1.2, factor: 1, drawnPt: pt, drawnWidth: nil)
        }
        // The font at a drawn size. Width is not a straight line of size: a face with an optical size axis draws
        // wider letters when it is small, so the fit is checked at the size it will really be drawn.
        func font(at drawn: Double) -> CTFont { FontLoader.shared.styledFont(face, ratio: CGFloat(drawn / base)) ?? first }
        func lineWidth(at drawn: Double) -> Double { TextRules.lineWidth(text, font: font(at: drawn), trackingEm: face.settings.tracking) }
        func column(at drawn: Double) -> Double {
            TextRules.columnWidth(measure: sizes.measure,
                                  advance: TextRules.averageAdvance(of: text, font: font(at: drawn), trackingEm: face.settings.tracking))
        }
        /// Shrinks the factor until `width(pt * f)` fits `room`, a few passes.
        func fit(room: Double, width: (Double) -> Double) -> Double {
            var f = TextRules.previewScale(width: width(pt), available: room)
            for _ in 0..<4 where f < 1 {
                let w = width(pt * f)
                if w <= room { break }
                f *= room / w
            }
            return f
        }
        if step == .body {
            // The column is `measure` characters of this text at this size. Shrinking it whole keeps every line break.
            let f = fit(room: specWidth, width: { column(at: $0) })
            return SetRowPlan(leading: sizes.lineHeight, factor: f, drawnPt: pt * f, drawnWidth: min(column(at: pt * f), specWidth))
        }
        // A little under the full width: the widest line must not touch the edge.
        let f = fit(room: specWidth * 0.98, width: { lineWidth(at: $0) })
        return SetRowPlan(leading: TextRules.headingLeading(step: step.rawValue), factor: f, drawnPt: pt * f, drawnWidth: nil)
    }
}

/// The bar over the Set stage: the Export menu, a line that says what an export did, and the inspector toggle.
struct SetBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 8)
            if let note = model.exportNotice {
                Text(note).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(theme.textPrimary.color)
                    .padding(.horizontal, 14).frame(height: 36)
                    .glass(\.glassBar, in: Capsule(), bar: true)
                    .transition(.opacity)
                    .accessibilityLabel(note)
            }
            Menu {
                ExportMenuItems()
            } label: {
                HStack(spacing: 6) {
                    Text(Lexicon.Export.menu).font(.system(size: 13)).foregroundStyle(theme.textPrimary.color)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textSecondary.color)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .padding(.horizontal, 14).frame(height: 36)
            .glass(\.glassBar, in: Capsule(), bar: true)
            .disabled(!model.canExport)
            .help(model.exportReason ?? Lexicon.Export.menu)
            .accessibilityLabel(Lexicon.Export.menu)
            InspectorToggle()
        }
        .padding(.horizontal, 16).padding(.top, 16)
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.15), value: model.exportNotice)
    }
}
