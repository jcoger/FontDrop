import FontDropCore
import SwiftUI

/// 02 Text of the Set inspector: the brand's Measure (characters per line) and Line height for body text.
/// The readouts sit on a recessed screen in Doto. Both values are saved per brand. Left alone, the measure is the
/// rules' default and the line height follows it (`TextRules`). Moving either one holds it until "Back to Auto".
///
/// React: two controlled sliders over the same per-brand store the Scale module writes.
struct TextModule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        let scale = model.scale
        let measure = TextRules.measure(scale)
        let lineHeight = TextRules.lineHeight(scale)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("02 \u{00B7} \(Lexicon.SetScreen.titleText)").moduleLabel()
                Spacer()
            }
            HStack(alignment: .top, spacing: 12) {
                readout(Lexicon.SetScreen.measure, "\(measure)", unit: Lexicon.SetScreen.measureUnit, held: scale.measure != nil)
                readout(Lexicon.SetScreen.lineHeight, String(format: "%.2f", lineHeight), unit: nil, held: scale.lineHeight != nil)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .recessed(radius: 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Lexicon.SetScreen.measure) \(measure) characters, \(Lexicon.SetScreen.lineHeight) " + String(format: "%.2f", lineHeight))

            control(label: Lexicon.SetScreen.measure,
                    slider: BodySlider(value: Double(measure), range: Double(TextRules.measureRange.lowerBound)...Double(TextRules.measureRange.upperBound),
                                       enabled: true, step: 1, label: Lexicon.SetScreen.measure,
                                       valueText: { "\(Int($0)) characters" }) { v in model.updateScale { $0.measure = Int(v) } },
                    held: scale.measure != nil, help: Lexicon.SetScreen.measureHelp) { model.updateScale { $0.measure = nil } }
            control(label: Lexicon.SetScreen.lineHeight,
                    slider: BodySlider(value: lineHeight, range: TextRules.lineHeightRange, enabled: true, step: 0.05,
                                       label: Lexicon.SetScreen.lineHeight, valueText: { String(format: "%.2f", $0) }) { v in
                        model.updateScale { $0.lineHeight = v } },
                    held: scale.lineHeight != nil, help: Lexicon.SetScreen.lineHeightHelp,
                    idle: Lexicon.SetScreen.lineHeightFollows) { model.updateScale { $0.lineHeight = nil } }

            Text(Lexicon.SetScreen.measureRule(measure))
                .font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 22)
    }

    private func readout(_ label: String, _ value: String, unit: String?, held: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).moduleLabel().lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(InstrumentFonts.doto(30)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle((held ? theme.textPrimary : theme.textSecondary).color)
                if let unit { Text(unit).moduleLabel() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func control(label: String, slider: BodySlider, held: Bool, help: String, idle: String = Lexicon.auto,
                         back: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).moduleLabel()
                Spacer()
                if held {
                    Button(action: back) { Text(Lexicon.SetScreen.backToAuto).moduleLabel() }
                        .buttonStyle(.plain)
                } else {
                    Text(idle).moduleLabel()
                }
            }
            slider
        }
        .help(help)
    }
}

/// 03 Faces of the Set inspector: for each face, its optical size (with the way back to Auto) and the STYL axis where
/// the face has one. Written into the same per-brand face settings the Text inspector's playground edits.
///
/// React: one controlled slider per axis the font file reports.
struct FacesModule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("03 \u{00B7} \(Lexicon.SetScreen.titleFaces)").moduleLabel()
                Spacer()
            }
            if let d = model.displayFamily { FaceAxes(job: "display", title: "Display", family: d) }
            if let t = model.readingFamily { FaceAxes(job: "reading", title: "Text", family: t) }
        }
        .padding(.top, 22)
    }
}

/// One face's axes. Optical size reads Auto until moved; "Auto" puts it back to following the size drawn.
private struct FaceAxes: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let job: String
    let title: String
    let family: FamilySummary
    @State private var loaded = 0

    var body: some View {
        let key = model.settingsKey(job, family.name)
        let settings = model.typeSettings.settings(key, job: job)
        let path = settings.stylePath ?? family.filePath
        let axes = FontLoader.shared.info(path)?.axes ?? []
        let _ = loaded
        let optical = axes.first { $0.tag == "opsz" }
        let styl = axes.first { $0.tag.trimmingCharacters(in: .whitespaces) == "STYL" }
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).moduleLabel()
                Text(family.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textPrimary.color)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if optical == nil && styl == nil {
                Text(axes.isEmpty ? Lexicon.SetScreen.fixedCut : Lexicon.SetScreen.noOpticalOrStyle).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            }
            if let optical {
                let set = settings.axes[optical.tag]
                axisControl(label: Lexicon.SetScreen.opticalSize, axis: optical, value: set ?? optical.defaultValue,
                            readout: Lexicon.SetScreen.opticalSizeReadout(set ?? optical.defaultValue, auto: set == nil),
                            held: set != nil, help: Lexicon.SetScreen.opticalHelp,
                            onChange: { v in model.typeSettings.update(key, job: job) { $0.axes[optical.tag] = v } },
                            back: { model.typeSettings.update(key, job: job) { $0.axes[optical.tag] = nil } })
            }
            if let styl {
                let set = settings.axes[styl.tag]
                axisControl(label: Lexicon.SetScreen.styleAxis, axis: styl, value: set ?? styl.defaultValue,
                            readout: "\(Int((set ?? styl.defaultValue).rounded()))", held: false, help: Lexicon.SetScreen.styleHelp,
                            onChange: { v in model.typeSettings.update(key, job: job) { $0.axes[styl.tag] = v } },
                            back: {})
            }
        }
        .task(id: path) {
            await FontLoader.shared.preload(paths: [path])
            loaded += 1
        }
    }

    private func axisControl(label: String, axis: FontLoader.Axis, value: Double, readout: String, held: Bool, help: String,
                             onChange: @escaping (Double) -> Void, back: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).moduleLabel()
                Spacer()
                Text(readout).font(InstrumentFonts.label(10)).tracking(1.4).textCase(.uppercase)
                    .foregroundStyle((held ? theme.textPrimary : theme.textSecondary).color)
                if held {
                    Button(action: back) { Text(Lexicon.SetScreen.backToAuto).moduleLabel() }
                        .buttonStyle(.plain).padding(.leading, 8)
                }
            }
            BodySlider(value: value, range: axis.min...axis.max, enabled: true, step: 1, label: label,
                       valueText: { "\(Int($0.rounded()))" }, onChange: onChange)
        }
        .help(help)
    }
}
