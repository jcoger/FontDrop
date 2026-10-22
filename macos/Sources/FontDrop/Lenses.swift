import FontDropCore
import Foundation

// The Reading lenses (docs/ideas/pairing-experience.md): questions the designer
// asks, answered client-side from the evidence the core already returned.
// No numeric score is shown or used here. The engine's own order (the position
// in `Candidate.order`) is only a tie-break.

/// How different the pair is. Three ordered steps plus Any. `steps` is the order a slider
/// would use (Close to Strong), so the menu can become a slider without new copy.
enum ContrastLens: String, CaseIterable, Identifiable {
    case close = "Close", clear = "Clear", strong = "Strong", any = "Any"
    var id: String { rawValue }
    static let steps: [ContrastLens] = [.close, .clear, .strong]
    /// 0, 1, 2 for the three steps; nil for Any.
    var stepIndex: Int? { Self.steps.firstIndex(of: self) }
}

/// Do the two faces share a structure (Same) or cross it (Mixed)? Not scored.
enum StructureLens: String, CaseIterable, Identifiable {
    case same = "Same", mixed = "Mixed", any = "Any"
    var id: String { rawValue }
}

enum FoundryLens: String, CaseIterable, Identifiable {
    case sameOnly = "Same foundry only", any = "Any"
    var id: String { rawValue }
}

/// Best match is the engine's order. "Less common first" uses Google's popularity rank
/// (the only popularity data there is) and puts families Google does not list first.
enum ReadingSort: String, CaseIterable, Identifiable {
    case bestMatch = "Best match", xHeight = "Same x-height first", name = "Name", lessCommon = "Less common first"
    var id: String { rawValue }
}

struct Lenses: Equatable {
    var contrast: ContrastLens = .clear
    var structure: StructureLens = .any
    var foundry: FoundryLens = .any
    var sort: ReadingSort = .bestMatch

    var isNeutral: Bool { contrast == .any && structure == .any && foundry == .any }
}

/// One Reading candidate: a core `PairCandidate` plus its position in the engine's order.
struct Candidate: Identifiable, Hashable {
    let id: String            // font_id
    let family: String
    let filePath: String
    let pairType: String      // contrast | uniform | middle | superfamily | uncertain
    let evidence: [Evidence]
    let order: Int
    /// Google popularity rank, 1 = most used. Nil: Google does not list the family (often paid or trial faces).
    let googleRank: Int?
    /// For a Same family pair: which style of the family to use for body text.
    let bodyStyle: BodyStyle?

    init(_ m: PairCandidate, order: Int, googleRank: Int? = nil) {
        id = m.fontId; family = m.family; filePath = m.filePath
        pairType = m.pairType; evidence = m.evidence; self.order = order; self.googleRank = googleRank
        bodyStyle = m.suggestedBodyStyle
    }

    /// For tests and previews.
    init(id: String, family: String, filePath: String = "", pairType: String, evidence: [Evidence], order: Int,
         googleRank: Int? = nil, bodyStyle: BodyStyle? = nil) {
        self.id = id; self.family = family; self.filePath = filePath
        self.pairType = pairType; self.evidence = evidence; self.order = order; self.googleRank = googleRank
        self.bodyStyle = bodyStyle
    }

    /// The Display family offered as its own partner.
    var isSameFamily: Bool { pairType == "same_family" }

    var onGoogle: Bool { googleRank != nil }

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

}

enum LensEngine {
    /// Filters and sorts. `hidden` counts what the lenses removed, so nothing leaves silently.
    static func apply(_ all: [Candidate], lenses: Lenses, search: String = "") -> (shown: [Candidate], hidden: Int) {
        var shown = all.filter { passes($0, lenses) }
        let hidden = all.count - shown.count
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { shown = shown.filter { $0.family.localizedCaseInsensitiveContains(q) } }
        switch lenses.sort {
        case .bestMatch:
            shown.sort { $0.order < $1.order }   // Same family is order 0: the engine puts it first
        case .xHeight:
            shown.sort { ($0.xHeightGap ?? 99, $0.order) < ($1.xHeightGap ?? 99, $1.order) }
        case .name:
            shown.sort { $0.family.localizedCaseInsensitiveCompare($1.family) == .orderedAscending }
        case .lessCommon:
            // Not on Google first; then the highest rank number (the least used) first. The engine's order breaks ties.
            shown.sort { (($0.onGoogle ? 1 : 0), -($0.googleRank ?? 0), $0.order) < (($1.onGoogle ? 1 : 0), -($1.googleRank ?? 0), $1.order) }
        }
        return (shown, hidden)
    }

    static func passes(_ c: Candidate, _ l: Lenses) -> Bool {
        // Same family is its own group: it is not a serif-with-sans or a uniform pair, so the
        // Difference, Structure and Foundry questions do not apply to it. It always shows.
        if c.isSameFamily { return true }
        switch l.contrast {
        case .any: break
        case .close: if c.pairType != "uniform" { return false }
        case .clear: if c.pairType != "contrast" { return false }
        case .strong:
            // Contrast pairs that also differ in texture or cross hands: the far end.
            if c.pairType != "contrast" || !(c.has("Texture") || c.isCrossedHands) { return false }
        }
        switch l.structure {
        case .any: break
        case .same: if !c.isSameHand { return false }
        case .mixed: if !c.isCrossedHands { return false }
        }
        if l.foundry == .sameOnly && !c.sharesFoundry { return false }
        return true
    }
}
