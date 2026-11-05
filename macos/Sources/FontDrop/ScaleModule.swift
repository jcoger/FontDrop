import SwiftUI

/// The Scale module of the Set inspector (board 19): header with the lock light, the dial on a recessed screen,
/// the Body slider, and the footer line. One body size and one ratio, shared by the Display and Text faces and
/// saved per brand. Auto (the default) lets the templates fit their type to each font; turning the dial locks it.
///
/// React: a controlled form over a per-brand store; the readouts derive from the same solver the templates call.
struct ScaleModule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let family: String
    var fallbackPath: String?

    var body: some View {
        let scale = model.scale
        let sizes = model.solvedSizes(reading: family, fallbackPath: fallbackPath)
        let auto = sizes.flatMap { DialMath.autoRatio(headline: $0.headline, body: $0.body, steps: $0.headlineStep) }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("01 \u{00B7} \(Lexicon.Scale.title)").moduleLabel()
                Spacer()
                HStack(spacing: 6) {
                    SignalLight(lit: scale.locked)
                    Text(scale.locked ? Lexicon.Dial.locked : Lexicon.auto).moduleLabel(color: scale.locked ? \.textPrimary : \.textSecondary)
                }
                .accessibilityHidden(true)
            }
            dialScreen(scale: scale, auto: auto)
            BodyControl(scale: scale, autoBody: sizes?.body) { body in
                model.updateScale { $0.body = body }
            }
            footer(scale: scale, sizes: sizes)
        }
        .padding(.top, 22)
    }

    private func dialScreen(scale: TypeScale, auto: Double?) -> some View {
        let shown = scale.locked ? scale.ratio : (auto ?? scale.ratio)
        return HStack(alignment: .center, spacing: 10) {
            RatioDial(scale: scale, autoRatio: auto,
                      onTurn: { ratio in model.setRatio(ratio, reading: family, fallbackPath: fallbackPath) },
                      onAuto: { model.returnToAuto() })
                .frame(width: 142)
            VStack(alignment: .leading, spacing: 4) {
                Text(Lexicon.Dial.label).moduleLabel()
                Text(DialMath.valueLabel(shown))
                    .font(InstrumentFonts.doto(30))
                    .foregroundStyle((scale.locked ? theme.textPrimary : theme.textSecondary).color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(caption(scale: scale, shown: shown)).moduleLabel().lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .recessed(radius: 14)
    }

    private func caption(scale: TypeScale, shown: Double) -> String {
        if scale.locked || DialMath.isOnStop(shown) { return DialMath.intervalName(shown) }
        return Lexicon.Dial.betweenStops
    }

    private func footer(scale: TypeScale, sizes: (headline: Double, body: Double, headlineStep: Int)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let sizes, sizes.body > 0 {
                Text(Lexicon.Scale.footer(headline: sizes.headline, times: sizes.headline / sizes.body))
                    .moduleLabel(color: \.textPrimary)
            }
            Spacer(minLength: 8)
            if scale.locked {
                Button { model.returnToAuto() } label: { Text(Lexicon.Dial.pressForAuto).moduleLabel() }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Lexicon.Dial.returnToAuto)
            } else {
                Text(Lexicon.Dial.turnToLock).moduleLabel()
            }
        }
        .help(scale.locked ? Lexicon.Scale.lockedHelp : Lexicon.Scale.autoHelp)
    }
}

// MARK: - Body

/// BODY label, the value in Doto 30, a ruler, the track and thumb, and the 9 and 24 range labels.
/// In Auto the value is what Auto solved to and the slider rests; turning the dial unlocks it.
struct BodyControl: View {
    @Environment(\.theme) private var theme
    let scale: TypeScale
    let autoBody: Double?
    let onChange: (Double) -> Void

    var body: some View {
        let value = scale.locked ? scale.body : (autoBody.map { min(max($0.rounded(), TypeScale.bodyRange.lowerBound), TypeScale.bodyRange.upperBound) } ?? scale.body)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Lexicon.Scale.body).moduleLabel()
                Text("\(Int(value.rounded()))")
                    .font(InstrumentFonts.doto(30))
                    .foregroundStyle((scale.locked ? theme.textPrimary : theme.textSecondary).color)
                    .frame(minWidth: 42, alignment: .leading)
            }
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                BodySlider(value: value, range: TypeScale.bodyRange, enabled: scale.locked, onChange: onChange)
                HStack {
                    Text("\(Int(TypeScale.bodyRange.lowerBound))")
                    Spacer()
                    Text("\(Int(TypeScale.bodyRange.upperBound))")
                }
                .moduleLabel()
                .accessibilityHidden(true)
            }
        }
        .help(scale.locked ? Lexicon.Scale.lockedHelp : Lexicon.Scale.controlsOffHelp)
    }
}

/// A ruler of ticks over a thin track with a thumb. Whole points. VoiceOver adjusts it a point at a time.
struct BodySlider: View {
    @Environment(\.theme) private var theme
    let value: Double
    let range: ClosedRange<Double>
    let enabled: Bool
    let onChange: (Double) -> Void

    private let thumb: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumb, 1)
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = thumb / 2 + CGFloat(t) * usable
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    var x: CGFloat = 0.5
                    while x < size.width {
                        context.fill(Path(CGRect(x: x, y: 0, width: 1, height: 9)), with: .color(theme.rulerTick.color))
                        x += 8
                    }
                }
                .frame(height: 9)
                Capsule().fill(theme.sliderTrack.color).frame(height: 4).offset(y: 18)
                Capsule().fill(theme.sliderFill.color).frame(width: max(x, 0), height: 4).offset(y: 18)
                Circle().fill(theme.sliderThumb.color)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(theme.isDark ? 0.6 : 0.25), radius: theme.isDark ? 1.5 : 2, y: 1)
                    .offset(x: x - thumb / 2, y: 12)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard enabled else { return }
                let t = min(max((drag.location.x - thumb / 2) / usable, 0), 1)
                let v = (range.lowerBound + Double(t) * (range.upperBound - range.lowerBound)).rounded()
                if v != value { onChange(v) }
            })
        }
        .frame(height: 32)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Lexicon.Scale.body)
        .accessibilityValue(Lexicon.Scale.bodyReadout(value))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: onChange(min(value + 1, range.upperBound))
            case .decrement: onChange(max(value - 1, range.lowerBound))
            @unknown default: break
            }
        }
    }
}
