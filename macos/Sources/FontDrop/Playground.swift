import FontDropCore
import SwiftUI

/// The live type playground for one face. A collapsible group in the inspector.
/// Every control writes into `TypeSettingsStore`; the cards and templates read the same store,
/// so they redraw as you drag. Settings are saved per brand + job + family.
///
/// React: a controlled form whose state lives in a store, with `useMemo` caches below it.
struct PlaygroundGroup: View {
    @Environment(AppModel.self) private var model
    let job: String                  // "display" or "reading": picks defaults and the settings key
    let family: FamilySummary
    let title: String                // e.g. "Display \u{00B7} Acme Serif"
    let preview: String              // the text the live specimen at the top draws
    @State private var open: Bool
    @State private var loaded = 0    // bumps when this family's style files finish loading

    init(job: String, family: FamilySummary, title: String, preview: String, startOpen: Bool) {
        self.job = job; self.family = family; self.title = title; self.preview = preview
        _open = State(initialValue: startOpen)
    }

    private var key: String { model.settingsKey(job, family.name) }
    private var store: TypeSettingsStore { model.typeSettings }
    private var styles: [FontFile] { StyleNames.sorted(model.fontsByFamily[family.name] ?? [], family: family.name) }

    var body: some View {
        let s = store.settings(key, job: job)
        let path = s.stylePath ?? family.filePath
        let info = FontLoader.shared.info(path)
        let _ = loaded

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { withAnimationIfAllowed { open.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playground, \(title)")
                .accessibilityValue(open ? "expanded" : "collapsed")
                Spacer()
                if store.isModified(key, job: job) {
                    Button("Reset") { store.reset(key) }
                        .buttonStyle(.link).font(.caption)
                        .help("Back to this face's own defaults")
                }
            }
            .padding(.horizontal, 2)

            if open {
                VStack(alignment: .leading, spacing: 12) {
                    specimen(FaceSpec(path: family.filePath, settings: s))
                    stylePicker(s)
                    if let info {
                        if !info.axes.isEmpty { axes(info.axes, s) }
                        numbers(s)
                        features(info.features, s)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            }
        }
        .task(id: family.name) {
            await FontLoader.shared.preload(paths: styles.map(\.filePath) + [family.filePath])
            loaded += 1
        }
    }

    // MARK: pieces

    private func specimen(_ face: FaceSpec) -> some View {
        FaceText(face: face, text: preview, ratio: CGFloat(face.settings.trim), tick: model.fontTick + loaded)
            .lineLimit(job == "display" ? 2 : 4)
            .minimumScaleFactor(job == "display" ? 0.3 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    private func stylePicker(_ s: TypeSettings) -> some View {
        // Files, and under each variable file its named instances ("Light", "Black").
        let choices = StyleChoices.build(files: styles, family: family.name, instances: FontInstances.of)
        // The saved or suggested file may not be in the list (the list keeps one file per style), so pick the nearest listed one.
        let wanted = s.stylePath ?? family.filePath
        let defaults = Dictionary((FontLoader.shared.info(wanted)?.axes ?? []).map { ($0.tag, $0.defaultValue) }, uniquingKeysWith: { a, _ in a })
        let hit = StyleChoices.current(in: choices, path: wanted, set: s.axes, defaults: defaults)
        let fallbackFile = StyleNames.nearest(to: wanted, in: styles, family: family.name,
                                              weight: StyleTraits.of(path: wanted)?.weight)?.filePath
        // A slider moved off every instance: say "Custom" rather than show a wrong name.
        let custom = hit == nil && choices.contains { $0.path == wanted && $0.isInstance }
        let current = hit?.id ?? (custom ? StyleChoice.customID : (fallbackFile ?? wanted))
        let plain = choices.filter { !$0.isInstance }
        let groups = Dictionary(grouping: choices.filter(\.isInstance), by: { $0.path })
        let groupOrder = choices.filter(\.isInstance).map(\.path).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return HStack {
            Text("Style").font(.callout)
            Spacer()
            if choices.count > 1 {
                Picker("Style", selection: Binding(
                    get: { current },
                    set: { new in
                        guard let pick = choices.first(where: { $0.id == new }) else { return }   // "Custom" is a status, not a choice
                        store.update(key, job: job) {
                            $0.stylePath = (pick.path == family.filePath ? nil : pick.path)
                            $0.axes = pick.axes      // an instance sets its axes; a plain file clears them
                        }
                    })) {
                    ForEach(plain) { Text($0.label).tag($0.id) }
                    ForEach(groupOrder, id: \.self) { path in
                        Section(groups[path]?.first?.group ?? "Variable") {
                            ForEach(groups[path] ?? []) { Text($0.label).tag($0.id) }
                        }
                    }
                    if custom { Text("Custom").tag(StyleChoice.customID) }
                }
                .labelsHidden().frame(maxWidth: 190)
            } else {
                Text(choices.first?.label ?? "Regular").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func axes(_ axes: [FontLoader.Axis], _ s: TypeSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variable axes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(axes) { axis in
                slider("\(axis.name) \u{00B7} \(axis.tag.trimmingCharacters(in: .whitespaces))",
                       value: Binding(
                        get: { s.axes[axis.tag] ?? axis.defaultValue },
                        set: { v in store.update(key, job: job) { $0.axes[axis.tag] = v } }),
                       range: axis.min...axis.max, readout: fmt(s.axes[axis.tag] ?? axis.defaultValue))
            }
        }
    }

    private func numbers(_ s: TypeSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Lexicon.Scale.sectionFace).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            slider(Lexicon.Scale.trim, value: Binding(get: { s.trim }, set: { v in store.update(key, job: job) { $0.trim = v } }),
                   range: TypeSettings.trimRange, readout: Lexicon.Scale.trimReadout(s.trim))
                .help(Lexicon.Scale.trimHelp)
            slider("Tracking", value: Binding(get: { s.tracking }, set: { v in store.update(key, job: job) { $0.tracking = v } }),
                   range: -0.08...0.3, readout: String(format: "%+.3f em", s.tracking))
            slider("Line height", value: Binding(get: { s.lineHeight }, set: { v in store.update(key, job: job) { $0.lineHeight = v } }),
                   range: 0.8...2.2, readout: String(format: "%.2f", s.lineHeight))
        }
    }

    @ViewBuilder
    private func features(_ list: [FeatureControl], _ s: TypeSettings) -> some View {
        if list.isEmpty {
            Text("No OpenType features in this style.").font(.caption).foregroundStyle(.secondary)
        } else {
            let groups = Dictionary(grouping: list, by: \.group)
            ForEach(["Letters", "Figures", "Stylistic sets"].filter { groups[$0] != nil }, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(groups[group] ?? []) { control in featureRow(control, s) }
                }
            }
        }
    }

    @ViewBuilder
    private func featureRow(_ c: FeatureControl, _ s: TypeSettings) -> some View {
        switch c.kind {
        case .toggle(let type, let on, _, let defaultOn):
            let k = "\(type).\(on)"
            Toggle(c.label, isOn: Binding(
                get: { (s.features[k] ?? (defaultOn ? 1 : 0)) == 1 },
                set: { v in store.update(key, job: job) { settings in
                    // Back at the font's default: forget the choice instead of storing it.
                    if v == defaultOn { settings.features[k] = nil } else { settings.features[k] = v ? 1 : 0 }
                } }))
                .toggleStyle(.switch).controlSize(.small).font(.callout)
        case .choice(let type, let options):
            HStack {
                Text(c.label).font(.callout)
                Spacer()
                Picker(c.label, selection: Binding<Int>(
                    get: { s.features["\(type)"] ?? -1 },
                    set: { v in store.update(key, job: job) { $0.features["\(type)"] = v < 0 ? nil : v } })) {
                    Text("Default").tag(-1)
                    ForEach(options, id: \.selector) { Text($0.label).tag($0.selector) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 140)
            }
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, readout: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).controlSize(.small)
                .accessibilityLabel(label)
        }
    }

    // MARK: helpers

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

/// Runs `body` with animation unless the Mac's Reduce Motion setting is on.
@MainActor
func withAnimationIfAllowed(_ body: () -> Void) {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { body() } else { withAnimation(.snappy(duration: 0.2), body) }
}
