import FontDropCore
import SwiftUI

// Small shared views. Each one is a "component" in React terms.

/// Draws `text` in the font at `path`. Reads the preloaded cache only: no state, no disk,
/// no async work, so it is safe inside a lazy grid. `tick` is not used for drawing. It is
/// here so the view redraws when the model loads more fonts.
struct FontText: View {
    let path: String
    let text: String
    let size: CGFloat
    var fallbacks: [String] = []     // tried in order if the font cannot draw `text`
    var checkCoverage = true
    var tick = 0

    var body: some View {
        switch FontLoader.shared.cached(path) {
        case .success(let loaded)?:
            Text(drawable(loaded)).font(Font(loaded.font(size: size)))
        case .failure?:
            Text(text).font(.system(size: size)).foregroundStyle(.tertiary)
        case nil:
            Text(text).font(.system(size: size)).opacity(0)   // reserve the space
        }
    }

    private func drawable(_ loaded: FontLoader.Loaded) -> String {
        guard checkCoverage else { return text }
        for candidate in [text] + fallbacks + [FontLoader.fallbackSample] where loaded.canDraw(candidate) {
            return candidate
        }
        return text
    }
}

/// Neutral tag, e.g. "Trial". Never a warning colour: trial fonts are welcome while exploring.
struct TagPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().stroke(.secondary.opacity(0.5), lineWidth: 1))
            .foregroundStyle(.secondary)
    }
}

/// One short reason as a chip. Effect +1 helps, -1 counts against, 0 is "not scored":
/// drawn neutral with a dashed outline. Meaning never rests on colour alone: "against"
/// carries a minus sign and "not scored" a dashed edge.
struct EvidenceChip: View {
    let text: String
    let effect: Int8
    var help: String = ""
    var warning = false      // "too close": an icon plus secondary colour, so it never reads as a plus

    private var label: Text {
        let words = Text((effect < 0 && !warning ? "\u{2212} " : "") + text)   // the icon already marks a warning
        return warning ? Text(Image(systemName: "exclamationmark.triangle")) + Text(" ") + words : words
    }

    var body: some View {
        label
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.quaternary.opacity(effect == 0 ? 0 : 0.6)))
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.4),
                                            style: StrokeStyle(lineWidth: 1, dash: effect == 0 ? [3, 2] : [])))
            .foregroundStyle(effect == 0 || warning ? Color.secondary : Color.primary)
            .help(help)
    }
}

/// A small "?" that opens a one-line explanation of a term. Book words live here, not in labels.
struct HelpButton: View {
    let term: Lexicon.Term
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.caption)
        }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
        .accessibilityLabel("What is \(term.rawValue)?")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(term.rawValue).font(.callout.weight(.semibold))
                Text(term.help).font(.callout).foregroundStyle(.secondary)
            }
            .padding(12).frame(width: 240, alignment: .leading)
        }
    }
}

/// "What do these mean?": every term and its one line, in one popover.
struct GlossaryButton: View {
    @State private var shown = false

    var body: some View {
        Button("What do these mean?") { shown.toggle() }
            .buttonStyle(.link).font(.caption)
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Lexicon.Term.allCases) { term in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(term.rawValue).font(.callout.weight(.semibold))
                            Text(term.help).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14).frame(width: 280, alignment: .leading)
            }
    }
}

/// Chips that wrap onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

/// A grouped block in the inspector: small title, rounded surface.
struct InspectorSection<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
    }
}

/// The bottom action of the inspector. The one prominent button on screen.
struct DecisionButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled)
        .padding(14)
        .background(.bar)
    }
}

/// The bottom of the inspector once a face is chosen: confirmation, Undo, and the next step.
/// Replaces "Use for ..." so the click visibly lands. The check bounces once (not with Reduce Motion).
///
/// React: a conditional footer driven by store state, with a CSS keyframe keyed on a counter.
struct ChosenPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let job: String
    var nextTitle: String?
    var next: (() -> Void)?

    var body: some View {
        let justChosen = model.canUndo(job)
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : model.choicePulse)
                Text(justChosen ? Lexicon.setDone(job) : Lexicon.current(job))
                    .font(.callout.weight(.semibold))
                Spacer()
                if justChosen {
                    Button(Lexicon.undo) { Task { await model.undo(job) } }
                        .buttonStyle(.link)
                }
                Button(Lexicon.clearFace(job)) { Task { await model.clear(job) } }
                    .buttonStyle(.link).foregroundStyle(.secondary).font(.caption)
            }
            if let nextTitle, let next {
                Button(action: next) {
                    HStack(spacing: 6) {
                        Text(nextTitle)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(14)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}

/// Shown while a choice waits for a brand. One field, prefilled, so naming takes a keystroke.
struct NameBrandSheet: View {
    @Environment(AppModel.self) private var model
    @State private var name = Lexicon.BrandSheet.suggestion
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Lexicon.BrandSheet.title).font(.title3.weight(.semibold))
            TextField(Lexicon.BrandSheet.field, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(create)
            Text(Lexicon.BrandSheet.help).font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(Lexicon.BrandSheet.cancel, role: .cancel) { model.pending = nil }
                    .keyboardShortcut(.cancelAction)
                Button(Lexicon.BrandSheet.ok, action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
        .onAppear { focused = true }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        Task { await model.createBrandAndApplyPending(trimmed) }
    }
}
