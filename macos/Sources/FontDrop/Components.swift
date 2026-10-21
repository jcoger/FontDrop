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

/// One piece of evidence from the core, as a chip. Effect +1 helps, -1 counts against,
/// 0 is "your call": drawn neutral with a dashed outline.
struct EvidenceChip: View {
    let evidence: Evidence

    var body: some View {
        Text(label)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.quaternary.opacity(evidence.effect == 0 ? 0 : 0.6)))
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.4),
                                            style: StrokeStyle(lineWidth: 1, dash: evidence.effect == 0 ? [3, 2] : [])))
            .foregroundStyle(evidence.effect == 0 ? .secondary : .primary)
            .help(evidence.source.isEmpty ? evidence.lens : "\(evidence.lens). Source: \(evidence.source)")
    }

    private var label: String {
        let prefix = evidence.effect > 0 ? "+ " : evidence.effect < 0 ? "\u{2212} " : ""
        return prefix + (evidence.detail.isEmpty ? evidence.lens : "\(evidence.lens): \(evidence.detail)")
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
