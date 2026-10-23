import FontDropCore
import SwiftUI

/// The stage: the selected candidate in the chosen template, scaled to fit, with a bar above (template,
/// colors, zoom) and the decide bar below. In Compare it shows two or three shortlisted faces side by side.
///
/// React: a canvas area with a `transform: scale()` wrapper, a toolbar above and a sticky action bar below.
struct ReadingStage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let compared = model.comparedFamilies
        let selected = model.candidate(model.selectedCandidate)
        VStack(spacing: 0) {
            StageBar(title: title(selected: selected, compared: compared), comparing: !compared.isEmpty)
            Divider()
            GeometryReader { geo in
                canvas(size: geo.size, selected: selected, compared: compared)
            }
            .background(Color.primary.opacity(0.07))
            Divider()
            DecideBar(selected: selected, comparing: !compared.isEmpty)
        }
        .task(id: taskID(selected: selected, compared: compared)) {
            let names = ([selected?.family, model.displayFamily?.name].compactMap { $0 }) + compared
            await model.preloadStyles(of: names)
        }
    }

    private func taskID(selected: Candidate?, compared: [String]) -> String {
        let family: String = selected?.family ?? ""
        let others: String = compared.joined(separator: ",")
        let display: String = model.displayFamily?.name ?? ""
        let revision: Int = model.libraryRevision
        return family + "/" + others + "/" + display + "/" + String(revision)
    }

    private func title(selected: Candidate?, compared: [String]) -> String {
        if !compared.isEmpty { return Lexicon.Reading.comparing(compared.count) }
        guard let selected else { return "" }
        if let display = model.displayFamily { return "\(display.name) + \(selected.family)" }
        return Lexicon.Reading.onItsOwn(selected.family)
    }

    @ViewBuilder
    private func canvas(size: CGSize, selected: Candidate?, compared: [String]) -> some View {
        if !compared.isEmpty {
            compare(size: size, families: compared)
        } else if let c = selected, let ctx = model.pairContext(reading: c.family, fallbackPath: c.filePath) {
            StageCanvas(context: ctx, template: model.activeTemplate, zoom: model.stageZoom.factor, size: size)
        } else {
            Text(Lexicon.Reading.pickOne).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Side by side: same template and colors, each board scaled to its column. A label row above each board.
    private func compare(size: CGSize, families: [String]) -> some View {
        let gap: CGFloat = 16, pad: CGFloat = 16, label: CGFloat = 30
        let n = CGFloat(families.count)
        let colW = max((size.width - pad * 2 - gap * (n - 1)) / n, 80)
        return HStack(alignment: .top, spacing: gap) {
            ForEach(families, id: \.self) { name in
                VStack(spacing: 6) {
                    HStack {
                        Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Button(Lexicon.Reading.use) { use(name) }.controlSize(.small)
                    }
                    .frame(height: label - 6)
                    if let ctx = model.pairContext(reading: name) {
                        StageCanvas(context: ctx, template: model.activeTemplate, zoom: 1,
                                    size: CGSize(width: colW, height: max(size.height - pad * 2 - label, 80)), padding: 0, topAligned: true)
                    }
                }
                .frame(width: colW)
            }
        }
        .padding(pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func use(_ family: String) {
        if let c = model.candidates.first(where: { $0.family == family }) ?? model.currentReadingCandidate.flatMap({ $0.family == family ? $0 : nil }) {
            model.selectedCandidate = c.id
        }
        model.compareMode = false
        Task { await model.choose("reading", family: family) }
    }
}

// MARK: - Canvas

/// One board, scaled. At Fit it is the largest size that fits the width and the height. Zoomed in, it scrolls.
/// Zoom may animate the scale. A window resize never does, and neither does changing candidate.
struct StageCanvas: View {
    let context: PairContext
    let template: TemplateDescriptor
    var zoom: Double = 1
    let size: CGSize
    var padding: CGFloat = 24
    var topAligned = false
    @State private var designHeight: CGFloat = 640
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let availW = max(size.width - padding * 2, 60), availH = max(size.height - padding * 2, 60)
        let fit = min(availW / Board<EmptyView>.designWidth, availH / max(designHeight, 1))
        let width = Board<EmptyView>.designWidth * fit * CGFloat(zoom)
        ScrollView([.horizontal, .vertical]) {
            template.make(context)
                .frame(width: width)
                .onPreferenceChange(BoardHeightKey.self) { if $0 > 0 { designHeight = $0 } }
                .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
                .padding(padding)
                .frame(minWidth: size.width, minHeight: size.height, alignment: topAligned ? .top : .center)
        }
        .scrollIndicators(zoom > 1.001 ? .automatic : .hidden)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: zoom)
    }
}

// MARK: - Bars

struct StageBar: View {
    @Environment(AppModel.self) private var model
    let title: String
    let comparing: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                LayoutMenu()
                ColorsButton()
                ZoomControls().disabled(comparing)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                LayoutMenu()
                ColorsButton()
                ZoomControls().disabled(comparing)
            }
            HStack(spacing: 10) {
                LayoutMenu()
                ZoomControls().disabled(comparing)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                ZoomControls().disabled(comparing)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .background(.bar)
    }
}

/// One menu for template and layout together, grouped by template: "Article · Essay".
struct LayoutMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = Templates.descriptor(model.templateID)
        let variant = model.brandStyle.variant(current)
        let variantTitle = current.variants.first { $0.id == variant }?.title ?? ""
        Menu {
            ForEach(Templates.all) { template in
                Section(template.title) {
                    ForEach(template.variants) { v in
                        Button {
                            model.templateID = template.id
                            model.brandStyle.setVariant(v.id, template: template)
                        } label: {
                            if template.id == current.id && v.id == variant { Label(v.title, systemImage: "checkmark") }
                            else { Text(v.title) }
                        }
                    }
                }
            }
        } label: {
            Text("\(current.title) \u{00B7} \(variantTitle)")
        }
        .menuStyle(.button).fixedSize()
        .help(Lexicon.Reading.layoutHelp)
        .accessibilityLabel(Lexicon.Colors.layoutLabel)
        .accessibilityValue("\(current.title), \(variantTitle)")
    }
}

/// Minus, Fit, plus. Command-minus, command-0 and command-plus.
struct ZoomControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let zoom = model.stageZoom
        HStack(spacing: 0) {
            Button { model.stageZoom.zoomOut() } label: { Image(systemName: "minus").frame(width: 18) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!zoom.canZoomOut)
                .help(Lexicon.Reading.zoomOut)
                .accessibilityLabel(Lexicon.Reading.zoomOut)
            Button { model.stageZoom.fit() } label: { Text(zoom.label).frame(minWidth: 34) }
                .keyboardShortcut("0", modifiers: .command)
                .help(Lexicon.Reading.zoomFit)
                .accessibilityLabel(Lexicon.Reading.zoomFit)
            Button { model.stageZoom.zoomIn() } label: { Image(systemName: "plus").frame(width: 18) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!zoom.canZoomIn)
                .help(Lexicon.Reading.zoomIn)
                .accessibilityLabel(Lexicon.Reading.zoomIn)
            Button("") { model.stageZoom.zoomIn() }              // command-plus on layouts where plus is its own key
                .keyboardShortcut("+", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .fixedSize()
    }
}

/// The bar under the stage: the one action. Shortlist for the current face, Compare, Use for Reading.
/// After a choice it turns into the confirmation with Undo and the next step.
struct DecideBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selected: Candidate?
    let comparing: Bool

    var body: some View {
        let isChosen = selected.map { model.chosen(.reading) == $0.family } ?? false
        Group {
            if comparing { compareBar }
            else if isChosen { chosenBar }
            else { chooseBar }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(.bar)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isChosen)
    }

    private var shortlistCount: Int { model.shortlist("reading").count }

    private var chooseBar: some View {
        let on = selected.map { model.shortlist("reading").contains($0.family) } ?? false
        let toggle = Button {
            if let c = selected { Task { await model.setShortlist("reading", family: c.family, on: !on) } }
        } label: {
            Label(on ? Lexicon.Reading.shortlistOn : Lexicon.Reading.addToShortlist,
                  systemImage: on ? "checkmark.circle.fill" : "plus.circle")
        }
        .disabled(selected == nil)
        let toggleIcon = Button {
            if let c = selected { Task { await model.setShortlist("reading", family: c.family, on: !on) } }
        } label: {
            Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
        }
        .help(on ? Lexicon.Reading.removeFromShortlist : Lexicon.Reading.addToShortlist)
        .accessibilityLabel(on ? Lexicon.Reading.removeFromShortlist : Lexicon.Reading.addToShortlist)
        .disabled(selected == nil)
        let compare = Button(Lexicon.Reading.compare(shortlistCount)) { model.compareMode = true }
        let use = Button(Lexicon.useFor("reading")) {
            if let c = selected { Task { await model.choose("reading", family: c.family) } }
        }
        .buttonStyle(.borderedProminent).disabled(selected == nil)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                hint
                Spacer(minLength: 8)
                toggle
                if Compare.isAvailable(shortlistCount: shortlistCount) { compare }
                use
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                toggle
                if Compare.isAvailable(shortlistCount: shortlistCount) { compare }
                use
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                toggleIcon
                if Compare.isAvailable(shortlistCount: shortlistCount) { compare }
                use
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                use
            }
        }
        .controlSize(.regular)
    }

    private var hint: some View {
        Text(Lexicon.Reading.hint).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }

    private var compareBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button(Lexicon.Reading.backToOne) { model.compareMode = false }
        }
    }

    private var chosenBar: some View {
        let justChosen = model.canUndo("reading")
        let noDisplay = model.displayFamily == nil
        return HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : model.choicePulse)
            Text(justChosen ? Lexicon.setDone("reading") : Lexicon.current("reading")).font(.callout.weight(.semibold)).lineLimit(1)
            if justChosen { Button(Lexicon.undo) { Task { await model.undo("reading") } }.buttonStyle(.link) }
            Button(Lexicon.clearFace("reading")) { Task { await model.clear("reading") } }
                .buttonStyle(.link).foregroundStyle(.secondary).font(.caption).lineLimit(1)
            Spacer(minLength: 8)
            Button {
                model.screen = noDisplay ? .display : .set
            } label: {
                HStack(spacing: 6) {
                    Text(noDisplay ? Lexicon.Reading.findDisplay : Lexicon.setTheType).lineLimit(1)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
