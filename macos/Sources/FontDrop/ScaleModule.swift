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
    /// Inside the Text inspector, under the scale readout line, which already names the scale and shows the lock light.
    var inline = false

    var body: some View {
        let scale = model.scale
        let sizes = model.solvedSizes(reading: family, fallbackPath: fallbackPath)
        let auto = sizes.flatMap { DialMath.autoRatio(headline: $0.headline, body: $0.body, steps: $0.headlineStep) }
        VStack(alignment: .leading, spacing: 12) {
            if !inline {
                SectionRule().padding(.bottom, 4)
                HStack {
                    Text(Lexicon.Scale.title).moduleLabel()
                    Spacer()
                    HStack(spacing: 6) {
                        SignalLight(lit: scale.locked)
                        Text(scale.locked ? Lexicon.Dial.locked : Lexicon.auto).moduleLabel(color: scale.locked ? \.textPrimary : \.textSecondary)
                    }
                    .accessibilityHidden(true)
                }
            }
            dialScreen(scale: scale, auto: auto)
            BodyControl(scale: scale, autoBody: sizes?.body) { body in
                model.setBody(body, reading: family, fallbackPath: fallbackPath)
            }
            footer(scale: scale, sizes: sizes)
        }
        .padding(.top, inline ? 0 : 16)
        .padding(.bottom, inline ? 4 : 20)
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
                    .font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            }
            Spacer(minLength: 8)
            if scale.locked {
                Button { model.returnToAuto() } label: { Text(Lexicon.SetScreen.backToAuto).font(.system(size: 12)) }
                    .buttonStyle(.themeLink)
                    .accessibilityLabel(Lexicon.Dial.returnToAuto)
            }
        }
        .help(scale.locked ? Lexicon.Scale.lockedHelp : Lexicon.Scale.autoHelp)
    }
}

// MARK: - Body

/// Body size. Always live: touching it takes the scale out of Auto and sets the size.
struct BodyControl: View {
    let scale: TypeScale
    let autoBody: Double?
    let onChange: (Double) -> Void

    var body: some View {
        let value = scale.locked ? scale.body : (autoBody.map { min(max($0.rounded(), TypeScale.bodyRange.lowerBound), TypeScale.bodyRange.upperBound) } ?? scale.body)
        BodySlider(value: value, range: TypeScale.bodyRange, unit: "pt", dim: !scale.locked, onChange: onChange)
            .help(scale.locked ? Lexicon.Scale.lockedHelp : Lexicon.Scale.autoHelp)
    }
}

/// The value row: label and value on one line, one track under them. Click the value to type, Up and Down step it.
/// Every number in the inspectors is one of these. `dim` means the value is following Auto. `reset` adds a way back.
struct BodySlider: View {
    @Environment(\.theme) private var theme
    let value: Double
    let range: ClosedRange<Double>
    var enabled = true
    var step: Double = 1
    var label = Lexicon.Scale.body
    var valueText: (Double) -> String = Lexicon.Scale.bodyReadout
    var decimals = 0
    var unit: String?
    var autoText: String?
    var dim = false
    var reset: (() -> Void)?
    var resetHelp = Lexicon.SetScreen.backToAuto
    let onChange: (Double) -> Void

    private let thumb: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color).lineLimit(1)
                Spacer(minLength: 4)
                if let reset {
                    Button(action: reset) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 10, weight: .medium))
                            .frame(width: 18, height: Metrics.inline).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(theme.textSecondary.color)
                    .help(resetHelp).accessibilityLabel(resetHelp)
                }
                NumberField(label: label, value: value, range: range, step: step, decimals: decimals, unit: unit,
                            enabled: enabled, autoText: autoText, dim: dim, onChange: onChange)
            }
            track
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumb, 1)
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = thumb / 2 + CGFloat(t) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(theme.sliderTrack.color).frame(height: 2)
                Capsule().fill(theme.sliderFill.color.opacity(dim ? 0.55 : 1)).frame(width: max(x, 0), height: 2)
                Circle().fill(theme.sliderThumb.color)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.25), radius: 1, y: 0.5)
                    .offset(x: x - thumb / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard enabled else { return }
                let t = min(max((drag.location.x - thumb / 2) / usable, 0), 1)
                let raw = range.lowerBound + Double(t) * (range.upperBound - range.lowerBound)
                let v = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                if abs(v - value) > step / 100 { onChange(v) }
            })
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText(value))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: onChange(min(value + step, range.upperBound))
            case .decrement: onChange(max(value - step, range.lowerBound))
            @unknown default: break
            }
        }
    }
}
