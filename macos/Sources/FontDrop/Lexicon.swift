import FontDropCore
import Foundation

/// One place that turns engine words into designer words. Source: docs/copy/lexicon-and-strings.md.
/// Rule: a book term (skeleton, dynamic, texture, lens, evidence) never appears as a label.
/// It may appear inside a help popover. If a string in a view is an engine word, route it through here.
enum Lexicon {
    // MARK: Terms with a one-line help

    enum Term: String, CaseIterable, Identifiable {
        case structure = "Structure", sameStructure = "Same or mixed structure", rational = "Rational"
        case strokeContrast = "Stroke contrast", difference = "Clear difference", harmony = "Harmony"
        case superfamily = "Superfamily", tooClose = "Too close"
        var id: String { rawValue }

        var help: String {
            switch self {
            case .structure: "How the letters are built: from the pen, from circles and lines, or upright and regular."
            case .sameStructure: "Same structure reads calm. Mixed adds tension. Not scored."
            case .rational: "Upright and regular: grotesques, neo-grotesques and Didone serifs like Bodoni."
            case .strokeContrast: "How much strokes change from thick to thin."
            case .difference: "Different enough to look intentional, usually serif with sans."
            case .harmony: "Same form and structure. Reads as one voice."
            case .superfamily: "Drawn as one set. Safest choice."
            case .tooClose: "So alike it can look like a mistake."
            }
        }
    }

    /// The help term behind an engine evidence lens, when there is one.
    static func term(forLens lens: String) -> Term? {
        switch lens {
        case "Skeleton": .structure
        case "Same hand": .sameStructure
        case "Texture": .strokeContrast
        case "Clear contrast": .difference
        case "Uniform": .harmony
        case "Designed together": .superfamily
        case "The middle", "Near-duplicate": .tooClose
        default: nil
        }
    }

    /// Pair type (engine) to the group word.
    static func pairGroup(_ pairType: String) -> String {
        switch pairType {
        case "contrast": "Clear difference"
        case "uniform": "Harmony"
        case "superfamily": "Superfamily"
        case "middle": "Too close"
        default: "Unclassified"
        }
    }

    // MARK: Structure and stroke words

    /// skeleton: dynamic -> Humanist, rational -> Rational, geometric -> Geometric.
    static func structure(_ engine: String) -> String {
        switch engine.lowercased() {
        case "dynamic": "Humanist"
        case "rational": "Rational"
        case "geometric": "Geometric"
        default: engine.capitalized
        }
    }

    /// "both dynamic" -> "Both humanist". Case of the first word follows the sentence.
    static func sentence(replacingStructureIn text: String) -> String {
        var out = text
        for (engine, word) in [("dynamic", "humanist"), ("rational", "rational"), ("geometric", "geometric"),
                               ("pen-made", "humanist"), ("constructed", "constructed")] {
            out = out.replacingOccurrences(of: engine, with: word, options: .caseInsensitive)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    // MARK: Strength and sources

    /// rule / guideline / shortcut / caveat -> Firm / Common advice / Rule of thumb / Use with care.
    static func strength(_ engine: String) -> String {
        switch engine {
        case "rule": "Firm"
        case "guideline": "Common advice"
        case "shortcut": "Rule of thumb"
        case "caveat": "Use with care"
        default: engine.capitalized
        }
    }

    static let strengthHelp: [String: String] = [
        "Firm": "Most sources agree.",
        "Common advice": "Several sources recommend it.",
        "Rule of thumb": "Helps, no guarantee.",
        "Use with care": "Sources disagree.",
    ]

    private static let titles: [String: String] = [
        "STO": "Universal Principles of Typography",
        "LAT": "Better Web Typography", "LCS": "Better Web Typography", "LCL": "Better Web Typography",
        "TWC": "Typewolf checklist", "TWG": "Typewolf checklist",
        "BRO": "Flexible Typesetting",
        "BON": "Smashing (Bonneville)", "MAY": "Smashing (Mayer)",
        "REY": "Smashing (Reynolds)", "RUI": "Refactoring UI", "RFR": "Refactoring UI",
    ]

    /// "LAT ch.5; TWC 69-70; BON p.145; MAY" -> "Better Web Typography, Typewolf checklist, Smashing (Bonneville), Smashing (Mayer)".
    /// Codes stay in the engine. Page refs and notes ("p.145", "(not definitive)") are dropped.
    static func sources(_ raw: String) -> String {
        var names: [String] = []
        for piece in raw.split(whereSeparator: { $0 == ";" }) {
            let first = piece.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
            let name = titles[first] ?? first
            if !name.isEmpty && !names.contains(name) { names.append(name) }
        }
        return names.joined(separator: ", ")
    }

    // MARK: Chips and Why rows

    /// The short chip for one piece of engine evidence. `xHeightNote` is the measured, directional
    /// version ("x-height 9% smaller") the card computes from the two fonts.
    static func chip(_ e: Evidence, xHeightNote: String? = nil) -> String {
        switch e.lens {
        case "Clear contrast": return e.detail.replacingOccurrences(of: " + ", with: " with ").capitalizedFirst
        case "Uniform": return sentence(replacingStructureIn: e.detail)
        case "Designed together": return "Superfamily"
        case "The middle": return "Too close"
        case "Unclassified": return "Structure unknown"
        case "Skeleton": return sentence(replacingStructureIn: e.detail)
        case "Same hand": return "Same structure"
        case "x-height":
            if let xHeightNote { return xHeightNote }
            let n = Double(e.detail.filter { $0.isNumber || $0 == "." }) ?? 0
            return n < 1 ? "Same x-height" : "x-height within \(Int(n))% of Display"
        case "Texture": return strokeSentence(e.detail)
        case "Foundry": return "Same foundry"
        case "Designer": return "Same designer"
        case "Near-duplicate": return "Too close to Display"
        case "Width": return "Widths far apart"
        default: return e.detail.isEmpty ? e.lens : "\(e.lens): \(e.detail)"
        }
    }

    /// The engine detail is "<Display's stroke> vs <candidate's stroke>", e.g. "contrasting vs linear".
    /// Says which face is which: "Even stroke vs high-contrast Display".
    static func strokeSentence(_ detail: String) -> String {
        let parts = detail.components(separatedBy: " vs ").map { $0.lowercased() }
        guard parts.count == 2 else { return "Different stroke contrast than Display" }
        func candidate(_ s: String) -> String { s.contains("linear") ? "even stroke" : s.contains("contrast") ? "high contrast" : s }
        func display(_ s: String) -> String { s.contains("linear") ? "even-stroke" : s.contains("contrast") ? "high-contrast" : s }
        return "\(candidate(parts[1]).capitalizedFirst) vs \(display(parts[0])) Display"
    }

    /// The row title in the Why list.
    static func whyTitle(_ e: Evidence) -> String {
        switch e.lens {
        case "Skeleton", "Same hand": "Structure"
        case "Clear contrast": "Clear difference"
        case "Uniform": "Harmony"
        case "Designed together": "Superfamily"
        case "The middle", "Near-duplicate": "Too close"
        case "Texture": "Stroke contrast"
        case "Foundry": "Foundry"
        case "Designer": "Designer"
        default: e.lens
        }
    }

    /// The row detail. The foundry or designer name lives here, not in the chip.
    static func whyDetail(_ e: Evidence) -> String {
        switch e.lens {
        case "Foundry", "Designer": e.detail
        default: chip(e)
        }
    }

    // MARK: Lens labels (2.x)

    static let contrastLabel = "Difference", structureLabel = "Structure", foundryLabel = "Foundry", sortLabel = "Sort"

    // MARK: Choose flow (5.x)

    static func useFor(_ job: String) -> String { "Use for \(job.capitalized)" }
    static func setDone(_ job: String) -> String { "\(job.capitalized) face set" }
    static func current(_ job: String) -> String { "Current \(job.capitalized) face" }
    static let undo = "Undo"
    static let findReading = "Find a Reading face"
    static let setTheType = "Next: sizes and spacing"

    // MARK: Brand sheet and empty states (6.x)

    enum BrandSheet {
        static let title = "Name this brand"
        static let field = "Brand name"
        static let help = "Your faces and shortlists save to this brand."
        static let ok = "Create brand"
        static let cancel = "Cancel"
        static let suggestion = "Untitled brand"
    }
    static let brandsEmpty = "No brands yet"
    static let needsDisplayTitle = "Pick a Display face first"
    static let needsDisplayBody = "Reading suggestions start from it."
    static let needsDisplayCTA = "Choose a Display face"
    static let readingFixed = "Showing faces made for long text"
    static let readingFixedWhy = "Hidden: display cuts, condensed and mono faces, and families without italic or bold."
    static let showThem = "Show them"
    static let onlyTextFaces = "Only faces made for long text"
    static let showingEvery = "Showing every face, including display, condensed and mono"
    static let readingNone = "No matches with these filters."
    static let clearFilters = "Clear filters"
    static let showMore = "Show more"

    // MARK: Finding fonts (8.x)

    enum Finder {
        static func sourceLabel(_ s: Source) -> String {
            switch s { case .yours: "Your fonts"; case .google: "Google Fonts"; case .system: "Mac system" }
        }
        static func kindLabel(_ k: Kind) -> String {
            switch k { case .serif: "Serif"; case .sans: "Sans"; case .script: "Script"; case .display: "Display"; case .mono: "Mono" }
        }
        static func traitLabel(_ t: Trait) -> String {
            switch t {
            case .italic: "Italic"; case .variable: "Variable"; case .condensed: "Condensed"
            case .wide: "Wide"; case .trial: "Trial"
            }
        }
        static let more = "More"
        static let moreHelp = "Style filters and hidden families"
        static let traitsHeader = "Style"
        static let showHidden = "Show hidden"
        static let hide = "Hide"
        static let unhide = "Unhide"
        static let hidden = "Hidden"
        static let hideHelp = "Hide this family from every list. Show it again from More."
        static let unhideHelp = "Put this family back in the lists."
        static let save = "Save"
        static let saved = "Saved"
        static let removeSaved = "Remove from Saved"
        static let savedEmpty = "Nothing saved yet. Star a family to keep it here."
        static let searchPrompt = "Search name, foundry or designer"
        static let noMatches = "No families match these filters."
        static let sourceFact = "Source"
        /// 7.20: the long-text rule's count, with its own control.
        static func notForLongText(_ n: Int) -> String { "\(n) not made for long text" }
        static let lessCommon = "Less common first"
        static let lessCommonHelp = "Faces fewer sites use. Families not on Google Fonts come first."
        /// "Your fonts \u{00B7} Google Fonts", for the inspector.
        static func sources(_ list: [Source]) -> String { list.map(sourceLabel).joined(separator: " \u{00B7} ") }
    }

    // MARK: Inspector (4.x)

    static let whyItPairs = "Why it pairs"
    static let notScored = "Not scored. Your choice."
    static let shortlistTitle = "Shortlist"
    static let shortlistEmpty = "Nothing here yet. Add faces you want to compare."
    static let licenseOK = "Not marked as trial"
    static let licenseTrial = "Trial version \u{00B7} License before you ship"
    static let getLicense = "Get the license"
}

extension String {
    /// Uppercases the first letter only ("serif with sans" -> "Serif with sans").
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
