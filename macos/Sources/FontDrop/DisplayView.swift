import FontDropCore
import SwiftUI

/// The grid used by Display, UI and Mono: every family, set in the brand's name.
/// `screen` decides which job "Use for ..." chooses a face for.
struct FamilyPickerView: View {
    @Environment(AppModel.self) private var model
    let screen: Screen

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]

    var body: some View {
        @Bindable var model = model
        let families = model.visibleFamilies
        let chosen = model.chosen(screen)
        let sample = model.sampleText
        let tick = model.fontTick

        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose the \(screen.title) face").font(.title2.weight(.semibold))
                    Text(subtitle(count: families.count))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if families.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(families) { family in
                            FamilyCard(family: family, sample: sample, tick: tick,
                                       isSelected: model.selectedFamily == family.name,
                                       isChosen: chosen == family.name)
                                .id(family.name)
                                .onTapGesture { model.selectedFamily = family.name }
                        }
                    }
                }
            }
            .padding(20)
        }
        // Open on the chosen face, so the grid starts where you left off.
        .task(id: "\(model.brandID ?? 0)/\(screen.rawValue)/\(model.fontsReady)") {
            if model.fontsReady, let name = model.chosen(screen) { proxy.scrollTo(name, anchor: .center) }
        }
        }
        .toolbar {
            ToolbarItem {
                Picker("Category", selection: $model.category) {
                    ForEach(FamilyCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func subtitle(count: Int) -> String {
        let brand = model.brand?.name ?? "Your brand name"
        let tail = screen == .display ? "The face you pick here sets the tone for Reading." : "Pick one for this job."
        return "\(brand) set in each of \(count) families. User-installed fonts come first. \(tail)"
    }
}

/// One family card. Takes plain values and holds no state.
struct FamilyCard: View {
    let family: FamilySummary
    let sample: String
    let tick: Int
    let isSelected: Bool
    let isChosen: Bool

    var body: some View {
        VStack(spacing: 0) {
            FontText(path: family.filePath, text: sample, size: 54,
                     fallbacks: [family.name], tick: tick)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(family.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(family.styleCount) \(family.styleCount == 1 ? "style" : "styles")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isChosen {
                    Text("Chosen").font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                } else if family.isTrial {
                    TagPill(text: "Trial")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                          lineWidth: isSelected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Inspector

struct FamilyInspector: View {
    @Environment(AppModel.self) private var model
    let screen: Screen
    @State private var detail: FamilyDetail?

    var body: some View {
        if let name = model.selectedFamily, let family = model.familyByName[name] {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(family)
                    specimen(family)
                    if let detail, detail.family == name { facts(family, detail) }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { action(family) }
            .task(id: name) { detail = await model.detail(for: name) }
        } else {
            ContentUnavailableView("No family selected", systemImage: "textformat",
                                   description: Text("Select a family to see its styles, axes and x-height."))
        }
    }

    private func header(_ family: FamilySummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(family.name).font(.title3.weight(.semibold))
            Text("\(screen.title) candidate" + (detail.map { $0.axes.isEmpty ? "" : " \u{00B7} Variable" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func specimen(_ family: FamilySummary) -> some View {
        FontText(path: family.filePath, text: "Aa Gg Rr", size: 56, tick: model.fontTick)
            .lineLimit(1).minimumScaleFactor(0.4)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    @ViewBuilder
    private func facts(_ family: FamilySummary, _ d: FamilyDetail) -> some View {
        InspectorSection(title: "Styles", trailing: "\(d.styles.count)") {
            ForEach(Array(d.styles.prefix(10).enumerated()), id: \.element.fontId) { i, style in
                if i > 0 { Divider().padding(.vertical, 5) }
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(styleLabel(style)).font(.callout).lineLimit(1)
                        Text("Weight \(style.weight)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    FontText(path: style.filePath, text: model.sampleText, size: 17,
                             fallbacks: [family.name], tick: model.fontTick)
                        .lineLimit(1)
                }
            }
            if d.styles.count > 10 {
                Text("\(d.styles.count - 10) more").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
        if !d.axes.isEmpty {
            InspectorSection(title: "Axes", trailing: "\(d.axes.count)") {
                ForEach(Array(d.axes.enumerated()), id: \.element.id) { i, axis in
                    if i > 0 { Divider().padding(.vertical, 5) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(axis.tag.trimmingCharacters(in: .whitespaces)) \u{00B7} \(axis.name)").font(.callout)
                            Spacer()
                            Text("\(fmt(axis.min))\u{2013}\(fmt(axis.max))").font(.caption).foregroundStyle(.secondary)
                        }
                        if axis.max > axis.min {
                            Gauge(value: axis.defaultValue, in: axis.min...axis.max) { EmptyView() }
                                .gaugeStyle(.linearCapacity)
                                .controlSize(.small)
                        }
                        Text("Default \(fmt(axis.defaultValue))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        InspectorSection(title: "Facts") {
            fact("x-height", d.xHeight.map { String(format: "%.3f", $0) } ?? "Unavailable")
            Divider().padding(.vertical, 5)
            fact("Skeleton", family.skeleton.isEmpty ? "Unknown" : family.skeleton.capitalized)
            Divider().padding(.vertical, 5)
            fact("Licence", family.isTrial ? "Trial build" : "Not marked as trial")
            if let vendor = family.vendor {
                Divider().padding(.vertical, 5)
                fact("Vendor", vendor)
            }
            if let urlText = family.foundryUrl, let url = URL(string: urlText) {
                Divider().padding(.vertical, 5)
                HStack {
                    Text("Foundry").font(.callout)
                    Spacer()
                    Link(url.host() ?? "Foundry page", destination: url).font(.callout).lineLimit(1)
                }
            }
        }
    }

    /// File name without extension. It tells italics and widths apart; the `name` column does not.
    private func styleLabel(_ style: FontFile) -> String {
        URL(fileURLWithPath: style.filePath).deletingPathExtension().lastPathComponent
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(value).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    @ViewBuilder
    private func action(_ family: FamilySummary) -> some View {
        if let job = screen.job {
            let isChosen = model.choices[job] == family.name
            DecisionButton(title: isChosen ? "Chosen for \(screen.title)" : "Use for \(screen.title)",
                           disabled: isChosen) {
                Task { await model.choose(job, family: family.name) }
            }
        }
    }
}
