import SwiftUI

/// The Scale section at the top of the Reading inspector. One body size and one ratio, shared by the Display and
/// Reading faces, saved per brand. Off (the default) the templates fit their type to each font and the two controls
/// rest. On, every size is `body x ratio^step`. The readout under it shows what the template on stage solved to.
///
/// React: a controlled form over a per-brand store, with the readout derived from the same solver the templates call.
struct ScaleSection: View {
    @Environment(AppModel.self) private var model
    let family: String
    var fallbackPath: String?

    var body: some View {
        let scale = model.scale
        let sizes = model.solvedSizes(reading: family, fallbackPath: fallbackPath)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Lexicon.Scale.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Toggle(Lexicon.Scale.lock, isOn: Binding(
                    get: { scale.locked },
                    set: { on in
                        if on { model.lockScale(reading: family, fallbackPath: fallbackPath) }
                        else { model.updateScale { $0.locked = false } }
                    }))
                    .toggleStyle(.switch).controlSize(.mini).font(.caption)
                    .help(Lexicon.Scale.lockHelp)
                    .accessibilityLabel(Lexicon.Scale.lockHelp)
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 10) {
                controls(scale)
                    .disabled(!scale.locked)
                    .opacity(scale.locked ? 1 : 0.55)
                // Quiet: the vibe by default; the numbers are here, small, and the help says how they are found.
                readout(scale: scale, sizes: sizes)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
    }

    private func controls(_ scale: TypeScale) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Lexicon.Scale.body).font(.callout)
                    Spacer()
                    Text(Lexicon.Scale.bodyReadout(scale.body)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { scale.body }, set: { v in model.updateScale { $0.body = v.rounded() } }),
                       in: TypeScale.bodyRange, step: 1)
                    .controlSize(.small)
                    .accessibilityLabel(Lexicon.Scale.body)
            }
            HStack {
                Text(Lexicon.Scale.ratio).font(.callout)
                Spacer()
                Picker(Lexicon.Scale.ratio, selection: Binding(
                    get: { TypeScale.nearestRatio(scale.ratio) },
                    set: { r in model.updateScale { $0.ratio = r } })) {
                    ForEach(TypeScale.ratios, id: \.self) { Text(Self.label($0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 100)
            }
        }
        .help(scale.locked ? Lexicon.Scale.lockedHelp : Lexicon.Scale.controlsOffHelp)
    }

    @ViewBuilder
    private func readout(scale: TypeScale, sizes: (headline: Double, body: Double, headlineStep: Int)?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if !scale.locked { Text(Lexicon.Scale.autoNote) }
            if let sizes, sizes.body > 0 {
                Text(Lexicon.Scale.headlineReadout(sizes.headline, times: sizes.headline / sizes.body))
                Text(Lexicon.Scale.bodyLine(sizes.body))
            }
        }
        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        .help(scale.locked ? Lexicon.Scale.lockedHelp : Lexicon.Scale.autoHelp)
    }

    private static func label(_ ratio: Double) -> String { TypeScale.ratioLabel(ratio) }
}
