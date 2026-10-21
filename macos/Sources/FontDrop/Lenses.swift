import FontDropCore
import Foundation

// The Reading lenses (docs/ideas/pairing-experience.md): questions the designer
// asks, answered client-side from the evidence the core already returned.
// No numeric score is shown or used here. The engine's own order (the position
// in `Candidate.order`) is only a tie-break.

enum ContrastLens: String, CaseIterable, Identifiable {
    case close = "Close", clear = "Clear", extreme = "Extreme", any = "Any"
    var id: String { rawValue }
}

enum HandLens: String, CaseIterable, Identifiable {
    case same = "Same", crossed = "Crossed", either = "Either"
    var id: String { rawValue }
}

enum FoundryLens: String, CaseIterable, Identifiable {
    case yes = "Yes", any = "Any"
    var id: String { rawValue }
}

enum ReadingSort: String, CaseIterable, Identifiable {
    case unexpected = "Unexpected first", xHeight = "Best x-height", name = "Name"
    var id: String { rawValue }
}

struct Lenses: Equatable {
    var contrast: ContrastLens = .clear
    var hand: HandLens = .either
    var foundry: FoundryLens = .any
    var sort: ReadingSort = .unexpected

    var isNeutral: Bool { contrast == .any && hand == .either && foundry == .any }
}

/// One Reading candidate: a core `PairMatch` plus its position in the engine's order.
struct Candidate: Identifiable, Hashable {
    let id: String            // font_id
    let family: String
    let filePath: String
    let pairType: String      // contrast | uniform | middle | superfamily | uncertain
    let evidence: [Evidence]
    let order: Int

    init(_ m: PairMatch, order: Int) {
        id = m.fontId; family = m.family; filePath = m.filePath
        pairType = m.pairType; evidence = m.evidence; self.order = order
    }

    /// For tests and previews.
    init(id: String, family: String, filePath: String = "", pairType: String, evidence: [Evidence], order: Int) {
        self.id = id; self.family = family; self.filePath = filePath
        self.pairType = pairType; self.evidence = evidence; self.order = order
    }

    static func == (a: Candidate, b: Candidate) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    func has(_ lens: String) -> Bool { evidence.contains { $0.lens == lens } }

    /// Same hand: shared skeleton, "both pen-made / constructed", or a uniform pair.
    var isSameHand: Bool { has("Skeleton") || has("Same hand") || pairType == "uniform" }
    var isCrossedHands: Bool { !isSameHand && (pairType == "contrast" || pairType == "middle") }
    var sharesFoundry: Bool { has("Foundry") }

    /// "within 5%" -> 5. Nil when the engine had no x-height evidence (gap over 10%, or unmeasured).
    var xHeightGap: Double? {
        guard let d = evidence.first(where: { $0.lens == "x-height" })?.detail else { return nil }
        let digits = d.filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    /// How many "shortcut" reasons this candidate leans on (shared foundry, designer, skeleton).
    /// Fewer means less obvious. Stands in for "unexpected" until there is popularity data.
    var obviousCount: Int { evidence.filter { $0.strength == "shortcut" }.count }
}

enum LensEngine {
    /// Filters and sorts. `hidden` counts what the lenses removed, so nothing leaves silently.
    static func apply(_ all: [Candidate], lenses: Lenses, search: String = "") -> (shown: [Candidate], hidden: Int) {
        var shown = all.filter { passes($0, lenses) }
        let hidden = all.count - shown.count
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { shown = shown.filter { $0.family.localizedCaseInsensitiveContains(q) } }
        switch lenses.sort {
        case .unexpected:
            shown.sort { ($0.obviousCount, $0.order) < ($1.obviousCount, $1.order) }
        case .xHeight:
            shown.sort { ($0.xHeightGap ?? 99, $0.order) < ($1.xHeightGap ?? 99, $1.order) }
        case .name:
            shown.sort { $0.family.localizedCaseInsensitiveCompare($1.family) == .orderedAscending }
        }
        return (shown, hidden)
    }

    static func passes(_ c: Candidate, _ l: Lenses) -> Bool {
        switch l.contrast {
        case .any: break
        case .close: if c.pairType != "uniform" { return false }
        case .clear: if c.pairType != "contrast" { return false }
        case .extreme:
            // Contrast pairs that also differ in texture or cross hands: the far end.
            if c.pairType != "contrast" || !(c.has("Texture") || c.isCrossedHands) { return false }
        }
        switch l.hand {
        case .either: break
        case .same: if !c.isSameHand { return false }
        case .crossed: if !c.isCrossedHands { return false }
        }
        if l.foundry == .yes && !c.sharesFoundry { return false }
        return true
    }
}
