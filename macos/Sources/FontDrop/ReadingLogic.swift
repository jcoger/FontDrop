import FontDropCore
import Foundation

// The Reading screen's rules, kept out of the views so tests can reach them:
// keyboard selection in the list, the stage zoom, compare mode, the pinned current face,
// and the style names the pickers show.

// MARK: - Keyboard selection

enum ListNav {
    /// The id one step up (-1) or down (+1) from `current`. Stops at the ends. Nothing selected: the first row.
    static func move(_ ids: [String], from current: String?, by step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let i = ids.firstIndex(of: current) else { return ids[0] }
        return ids[min(max(i + step, 0), ids.count - 1)]
    }
}

// MARK: - Stage zoom

/// How far the stage board is scaled, as a multiple of the Fit size. 1 is Fit.
struct StageZoom: Equatable {
    static let range: ClosedRange<Double> = 0.5...4
    static let step = 1.25

    private(set) var factor = 1.0

    var isFit: Bool { abs(factor - 1) < 0.001 }
    var canZoomIn: Bool { factor < Self.range.upperBound - 0.001 }
    var canZoomOut: Bool { factor > Self.range.lowerBound + 0.001 }
    /// "Fit" at 1, else a percent of Fit.
    var label: String { isFit ? Lexicon.Reading.fit : "\(Int((factor * 100).rounded()))%" }

    mutating func zoomIn() { factor = Self.clamp(factor * Self.step) }
    mutating func zoomOut() { factor = Self.clamp(factor / Self.step) }
    mutating func fit() { factor = 1 }

    static func clamp(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }
}

// MARK: - Compare

enum Compare {
    static let maxBoards = 3

    /// Compare needs two shortlisted faces.
    static func isAvailable(shortlistCount: Int) -> Bool { shortlistCount >= 2 }

    /// The families side by side: up to three from the shortlist, the selected one first when it is on it.
    static func families(shortlist: [String], selected: String?) -> [String] {
        var list = shortlist
        if let selected, let i = list.firstIndex(of: selected), i > 0 { list.remove(at: i); list.insert(selected, at: 0) }
        return Array(list.prefix(maxBoards))
    }
}

// MARK: - The list's rows

enum ReadingRows {
    /// The Current face first (even when filters or paging would hide it), then the filtered candidates
    /// without a second copy of it. A search that does not match the Current face leaves it out.
    static func rows(current: Candidate?, shown: [Candidate], search: String) -> [Candidate] {
        let q = search.trimmingCharacters(in: .whitespaces)
        var out: [Candidate] = []
        if let current, q.isEmpty || current.family.localizedCaseInsensitiveContains(q) { out.append(current) }
        out.append(contentsOf: shown.filter { $0.family != current?.family })
        return out
    }

    /// At most two quiet reasons, in the Lexicon's words, joined for a row. "Same foundry" is dropped when a
    /// "Same designer" reason says the same name (the library falls back to the designer for the foundry).
    static func reasons(_ candidate: Candidate, xHeightNote: String?, limit: Int = 2) -> [String] {
        var out: [String] = []
        for e in dedupedEvidence(candidate.evidence) {
            let text = Lexicon.chip(e, xHeightNote: e.lens == "x-height" ? xHeightNote : nil)
            if !out.contains(text) { out.append(text) }
        }
        if candidate.isCrossedHands, !out.contains(Lexicon.Reading.mixedStructure) { out.append(Lexicon.Reading.mixedStructure) }
        return Array(out.prefix(limit))
    }

    /// Foundry evidence whose name is the designer's name is the same fact twice. Keep the designer one.
    static func dedupedEvidence(_ list: [Evidence]) -> [Evidence] {
        let designers = Set(list.filter { $0.lens == "Designer" }.map { $0.detail.lowercased() })
        return list.filter { !($0.lens == "Foundry" && designers.contains($0.detail.lowercased())) }
    }
}

// MARK: - Layout and scope

enum ReadingLayout {
    /// The list's width: 320 when there is room, narrower (never under 220) when the content column is tight.
    static func listWidth(for total: CGFloat) -> CGFloat { total >= 760 ? 320 : min(320, max(220, total * 0.42)) }

    /// The inspector starts closed when the content column would be under this with it open.
    static let inspectorMinContent: CGFloat = 760
    static let sidebarWidth: CGFloat = 235
    static let inspectorWidth: CGFloat = 330

    static func inspectorFits(windowWidth: CGFloat) -> Bool {
        windowWidth - sidebarWidth - inspectorWidth >= inspectorMinContent
    }
}

/// The source chips of the Display filter, as the three choices the Reading head offers.
enum SourceScope: String, CaseIterable, Identifiable {
    case yours, yoursAndGoogle, all, custom
    var id: String { rawValue }

    init(_ sources: Set<Source>) {
        switch sources {
        case [.yours]: self = .yours
        case [.yours, .google]: self = .yoursAndGoogle
        case [.yours, .google, .system]: self = .all
        default: self = .custom
        }
    }

    var sources: Set<Source>? {
        switch self {
        case .yours: [.yours]
        case .yoursAndGoogle: [.yours, .google]
        case .all: [.yours, .google, .system]
        case .custom: nil
        }
    }

    var label: String {
        switch self {
        case .yours: Lexicon.Reading.sourceYours
        case .yoursAndGoogle: Lexicon.Reading.sourceGoogle
        case .all: Lexicon.Reading.sourceAll
        case .custom: Lexicon.Reading.sourceMixed
        }
    }
}

// MARK: - Style names

enum StyleNames {
    /// What a style picker or list shows: the font's own name from its name table, else a cleaned file name,
    /// else the weight word.
    static func label(_ file: FontFile, family: String) -> String {
        let own = file.styleName.trimmingCharacters(in: .whitespaces)
        if !own.isEmpty { return own }
        return fallback(path: file.filePath, family: family, weight: Int(file.weight))
    }

    /// "ABCReproMono-Regular" with family "ABC Repro Mono" -> "Regular"; "GrandHeavy" -> "Grand Heavy".
    /// A stem with no readable words ("psz]") gives the weight word instead.
    static func fallback(path: String, family: String, weight: Int) -> String {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let compactFamily = family.replacingOccurrences(of: " ", with: "").lowercased()
        var label = stem
        let compactStem = stem.replacingOccurrences(of: " ", with: "").lowercased()
        if compactStem == compactFamily { return weightWord(weight) }
        if compactStem.hasPrefix(compactFamily), compactStem.count > compactFamily.count {
            // Drop as many characters as the family has (ignoring spaces in the stem).
            var dropped = 0, seen = 0
            for ch in stem {
                if ch != " " { seen += 1 }
                dropped += 1
                if seen == compactFamily.count { break }
            }
            label = String(stem.dropFirst(dropped))
        }
        label = label.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        label = spaced(label.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " "))
        let letters = label.filter(\.isLetter).count
        let clean = label.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
        guard letters >= 3, clean else { return weightWord(weight) }
        return label
    }

    /// Splits camel case: "GrandHeavy" -> "Grand Heavy". Runs of capitals stay together ("ABC").
    static func spaced(_ s: String) -> String {
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if i > 0, c.isUppercase, chars[i - 1].isLowercase { out.append(" ") }
            out.append(c)
        }
        return out
    }

    static func weightWord(_ w: Int) -> String {
        switch w {
        case ..<150: "Thin"
        case ..<250: "Extra Light"
        case ..<350: "Light"
        case ..<450: "Regular"
        case ..<550: "Medium"
        case ..<650: "Semibold"
        case ..<750: "Bold"
        case ..<850: "Extra Bold"
        default: "Black"
        }
    }

    static func isItalic(_ file: FontFile, family: String) -> Bool {
        let l = label(file, family: family).lowercased()
        return l.contains("italic") || l.contains("oblique")
    }

    /// Light to heavy; at the same weight, upright before italic; then by name.
    /// Two files can share a weight in their own data (Thin and Ultra Light both 250). That stays; this only orders them.
    static func sorted(_ files: [FontFile], family: String) -> [FontFile] {
        files.sorted { a, b in
            let ka = (a.weight, isItalic(a, family: family) ? 1 : 0)
            let kb = (b.weight, isItalic(b, family: family) ? 1 : 0)
            if ka != kb { return ka < kb }
            let na = label(a, family: family), nb = label(b, family: family)
            let order = na.localizedStandardCompare(nb)
            return order != .orderedSame ? order == .orderedAscending : a.filePath < b.filePath
        }
    }

    /// The listed file a picker should show for `path`. The path itself when it is listed. Otherwise the same
    /// file name in another format (the list keeps one file per style), else the nearest weight, upright first.
    /// Never nil for a non-empty list, so a picker is never blank.
    static func nearest(to path: String, in files: [FontFile], family: String, weight: Double?) -> FontFile? {
        guard !files.isEmpty else { return nil }
        if let hit = files.first(where: { $0.filePath == path }) { return hit }
        func stem(_ p: String) -> String { URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent.lowercased() }
        if let hit = files.first(where: { stem($0.filePath) == stem(path) }) { return hit }
        let target = weight ?? 400
        return files.min { a, b in
            let da = abs(Double(a.weight) - target), db = abs(Double(b.weight) - target)
            let ka = (da, isItalic(a, family: family) ? 1 : 0), kb = (db, isItalic(b, family: family) ? 1 : 0)
            return ka < kb
        }
    }
}
