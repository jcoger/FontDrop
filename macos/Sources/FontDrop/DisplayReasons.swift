import FontDropCore
import Foundation

/// The one line under a Display card while Pairs with is on. A line that is the same on every card says nothing, so
/// each card shows the evidence that sets its pair apart: a helping reason that few of the cards at the top of the
/// list share. When every reason is common, the pair type's line (Clear contrast with ...) is the fallback.
enum DisplayReasons {
    /// How many cards at the top of the ranking count as "the visible cards" when judging what is common.
    static let window = 60
    /// A reason shared by more than this share of those cards does not tell them apart.
    static let commonShare = 0.5

    struct Entry {
        let family: String
        let pairType: String
        let evidence: [Evidence]
    }

    /// The line for every ranked family, by family name. `text` is the chosen Text face.
    static func lines(_ ranked: [Entry], text: String) -> [String: String] {
        var counts: [String: Int] = [:]
        let top = ranked.prefix(window)
        for entry in top {
            for key in Set(entry.evidence.filter(usable).map(key)) { counts[key, default: 0] += 1 }
        }
        let total = Double(max(top.count, 1))
        var out: [String: String] = [:]
        for entry in ranked {
            let fallback = Lexicon.Pairs.reason(pairType: entry.pairType, text: text)
            // The rarest helping reason; a stronger source breaks a tie; the engine's order after that.
            let best = entry.evidence.enumerated()
                .filter { usable($0.element) }
                .map { (index: $0.offset, e: $0.element, share: Double(counts[key($0.element)] ?? 0) / total) }
                .filter { $0.share <= commonShare }
                .min { (a, b) in (a.share, strength(a.e), a.index) < (b.share, strength(b.e), b.index) }
            if let best, let line = Lexicon.Pairs.evidenceLine(best.e, text: text) { out[entry.family] = line }
            else if let fallback { out[entry.family] = fallback }
        }
        return out
    }

    private static func usable(_ e: Evidence) -> Bool {
        e.effect == 1 && Lexicon.Pairs.evidenceLine(e, text: "") != nil
    }
    private static func key(_ e: Evidence) -> String { e.lens + "|" + e.detail }
    private static func strength(_ e: Evidence) -> Int {
        switch e.strength { case "rule": 0; case "guideline": 1; default: 2 }
    }
}
