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
        case superfamily = "Superfamily", tooClose = "Too close", sameFamily = "Same family"
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
            case .sameFamily: Lexicon.sameFamilyHelp
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
        case "Same family": .sameFamily
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
        case "same_family": sameFamilyGroup
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
        // The type guides behind "Recommended for text" (core/data/text-recommendations.csv).
        "TYW": "Typewolf", "BPT": "Butterick's Practical Typography",
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
        case "Recommended for text": return "Recommended for text \u{00B7} \(e.detail)"
        case "Foundry": return "Same foundry"
        case "Designer": return "Same designer"
        case "Near-duplicate": return "Too close to Display"
        case "Same family": return "Same family: \(e.detail)"
        case "Long text": return "May be weak for long text"
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
        case "Recommended for text": "Type guides"
        case "Same family": "Same family"
        case "Foundry": "Foundry"
        case "Designer": "Designer"
        default: e.lens
        }
    }

    /// The row detail. The foundry or designer name lives here, not in the chip.
    static func whyDetail(_ e: Evidence) -> String {
        switch e.lens {
        case "Foundry", "Designer", "Same family": e.detail
        case "Long text": e.detail + "."
        default: chip(e)
        }
    }

    /// 16.2: the hover on the "Recommended for text" row: who recommends it.
    static func recommendedBy(_ sources: String) -> String { "Recommended for body text by \(sources)" }

    // MARK: Same family (9.x)

    static let sameFamilyGroup = "Same family"
    static let sameFamilyHelp = "Use this family for both. Pick a different width or weight for the body."
    /// On the Same family card: which style the body text starts in.
    static func bodyIn(_ style: String) -> String { "Body in \(style)" }

    // MARK: Lens labels (2.x)

    static let contrastLabel = "Difference", structureLabel = "Structure", foundryLabel = "Foundry", sortLabel = "Sort"

    // MARK: Choose flow (5.x)

    /// The designer's name for a job. The core's `reading` job is called Text on screen (docs/copy section 17).
    static func jobName(_ job: String) -> String { job == "reading" ? "Text" : job.capitalized }
    static func useFor(_ job: String) -> String { "Use for \(jobName(job))" }
    static func picked(_ job: String) -> String { "\(jobName(job)) face picked" }
    static func current(_ job: String) -> String { "Current \(jobName(job)) face" }
    static let undo = "Undo"
    /// "Clear Display face". Takes the face off the job. Undo puts it back.
    static func clearFace(_ job: String) -> String { "Clear \(jobName(job)) face" }
    static func cleared(_ job: String) -> String { "\(jobName(job)) face cleared" }
    static let typeMenu = "Type"
    static let findText = "Find a Text face"
    static let setTheType = "Next: Set"

    // MARK: Navigation (17.x)

    /// The menu that holds the three screens and their command-1 to command-3 shortcuts.
    static let goMenu = "Go"
    /// 17.7: the variable font's optical size axis. Auto follows the size drawn.
    static let opticalSize = "Optical size"
    static let auto = "Auto"
    // View menu
    static let sidebarJobs = "Display, Text and Set"
    static let showSidebar = "Show Sidebar"
    static let hideSidebar = "Hide Sidebar"
    static let showInspector = "Show Inspector"
    static let hideInspector = "Hide Inspector"

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
    static let needsDisplayBody = "Text suggestions start from it."
    static let needsDisplayCTA = "Choose a Display face"
    static let readingFixed = "Showing faces made for long text"
    static let readingFixedWhy = "Hidden: display cuts, condensed and mono faces, and families without italic or bold."
    static let showThem = "Show them"
    static let onlyTextFaces = "Only faces made for long text"
    static let showingEvery = "Showing every face, including display, condensed and mono"
    static let readingNone = "No matches with these filters."
    static let clearFilters = "Clear filters"
    static let showMore = "Show more"

    // MARK: Scanning the library (13.x)

    /// The Text inspector's modules (docs/design/2026-11-05-instrument-look.md).
    enum Why {
        static let sources = "Sources"
        static let face = "Face"
        static let letters = "Letters"
        static let sameFamilyVerdict = "Same family. Drawn as one set, the safest choice."
        static let nothingNotable = "The engine measured nothing notable."
        static func styles(_ n: Int) -> String { n == 1 ? "1 style" : "\(n) styles" }
        static func lettersAccessibility(_ samples: [String]) -> String { "Letters in this face: " + samples.joined(separator: ", ") }
    }

    /// Ends a chip's words as a sentence.
    static func sentenceEnd(_ text: String) -> String { text.hasSuffix(".") ? text : text + "." }

    /// The About window's credits: the two bundled fonts and their licence.
    static let aboutCredits = "Doto and Geist Mono are bundled under the SIL Open Font License 1.1. The licence texts are in the app's Resources folder."

    enum Features {
        /// The core's feature group "Letters" is shown as "Small caps and ligatures" (IA decision 4).
        static func groupTitle(_ group: String) -> String { group == "Letters" ? "Small caps and ligatures" : group }
    }

    /// The sidebar's status readout (Doto, capitals by style).
    enum Status {
        static func counts(families: Int, files: Int) -> String { "\(families) FAM \u{00B7} \(files) FILES" }
        static let scanning = "UPDATING"
        /// Sidebar readout while a scan counts files: "1204 / 4549 FILES".
        static func scanProgress(read: Int, of total: Int) -> String { "\(read) / \(total) FILES" }
        static let failed = "UPDATE FAILED"
    }

    enum Scan {
        /// Sidebar footer while a rescan runs.
        static let updating = "Updating your library\u{2026}"
        /// Sidebar footer when the rescan failed. The library stays as it was.
        static let failed = "Couldn\u{2019}t update the library"
        static let retry = "Retry"
        static let retryHelp = "Scan your font folders again"
        /// Display and Text while the library is empty and a scan is working on it.
        static let scanningFonts = "Scanning your fonts\u{2026}"
    }

    /// First run, empty library, edge states (round R2b, spec "Launch").
    enum Launch {
        static let scanTitle = "Scanning your fonts"
        static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
        static func ofFiles(_ files: Int, families: Int) -> String { "of \(files) files \u{00B7} \(families) families found" }
        static let headline = "Start with a headline face, or a text face."
        static let body = "Fonts show up as they are read. When you pick one, FontDrop asks which brand it is for."
        static let startDisplay = "Start with Display"
        static let startText = "Start with Text"
        static func scanAccessibility(_ fraction: Double, read: Int, of total: Int) -> String {
            "Scanning your fonts, \(Int((fraction * 100).rounded())) percent, \(read) of \(total) files"
        }
        /// A face this brand chose that is no longer on this Mac. The sidebar row says so under its name.
        static let notInstalled = "Not installed"
        static func notInstalledAccessibility(_ job: String, _ family: String) -> String { "\(job), \(family), not installed" }
        static let emptyTitle = "No fonts found"
        static let emptyBody = "FontDrop reads the fonts installed on this Mac. Add some in Font Book, then come back."
        static let openFontBook = "Open Font Book"
    }

    /// The ratio dial on Set (spec "Dial", board 13).
    enum Dial {
        static let label = "Ratio"
        static let locked = "Locked"
        static let betweenStops = "Auto \u{00B7} between stops"
        static let pressForAuto = "Press for Auto"
        static let turnToLock = "Turn to lock"
        static let returnToAuto = "Return to Auto"
        static let hint = "Adjust to choose a ratio and lock the sizes. Press to return to Auto."
        static let minorThird = "Minor third"
        static let majorThird = "Major third"
        static let fourth = "Fourth"
        static let fifth = "Fifth"
        static let golden = "Golden"
        /// VoiceOver value: "1.333, locked" or "Auto".
        static func accessibilityValue(_ scale: TypeScale, autoRatio: Double?) -> String {
            scale.locked ? "\(TypeScale.ratioLabel(scale.ratio)), locked" : "Auto"
        }
    }

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
        /// 9.5: the chip counts what the filters show; the sidebar counts every saved family.
        static let savedChipHelp = "Saved fonts in this view"
        static let savedEmpty = "Nothing saved yet. Star a family to keep it here."
        static let searchPrompt = "Search name, foundry or designer"
        static let noMatches = "No families match these filters."
        static let sourceFact = "Source"
        /// 7.20: the long-text rule's count, with its own control.
        static func notForLongText(_ n: Int) -> String { "\(n) not made for long text" }
        static let lessCommon = "Less common first"
        /// 15.1: Sort option that flips Text's two groups: personality first, the dependable text faces after.
        static let moreCharacter = "More character first"
        static let moreCharacterHelp = "Faces with more personality come first. The dependable text faces follow."
        static let lessCommonHelp = "Faces fewer sites use. Families not on Google Fonts come first."
        /// "Your fonts \u{00B7} Google Fonts", for the inspector.
        static func sources(_ list: [Source]) -> String { list.map(sourceLabel).joined(separator: " \u{00B7} ") }
    }

    // MARK: Inspector (4.x)

    static let whyItPairs = "Why it pairs"
    static let notScored = "Not scored. Your choice."
    static let licenseOK = "Not marked as trial"
    static let licenseTrial = "Trial version \u{00B7} License before you ship"
    static let getLicense = "Get the license"

    // MARK: Text list and stage (11.x)

    enum Reading {
        static func title(_ display: String) -> String { "Text for \(display)" }
        static func onShortlist(_ n: Int) -> String { "\(n) on shortlist" }
        static func facesCount(_ n: Int) -> String { n == 1 ? "1 face" : "\(n) faces" }
        static let searchPrompt = "Search families"
        static func subtitle(_ n: Int) -> String { "Text \u{00B7} \(onShortlist(n))" }
        static let current = "Current"
        static let onShortlistTag = "On shortlist"
        static let trialTag = "Trial"
        static let mixedStructure = "Mixed structure"
        static func sameFamilyRow(_ style: String?) -> String { style.map { "Same family \u{00B7} \(bodyIn($0))" } ?? "Same family" }
        static let fit = "Fit"
        static let zoomIn = "Zoom in", zoomOut = "Zoom out", zoomFit = "Fit to window"
        static let layoutHelp = "Template and layout"
        static let hint = "\u{2191} \u{2193} flips candidates in place"
        static let addToShortlist = "Add to shortlist"
        static let removeFromShortlist = "Remove from shortlist"
        static let shortlistOn = "On shortlist"
        static func compare(_ n: Int) -> String { "Compare shortlist (\(n))" }
        static let backToOne = "Back to one"
        static let use = "Use"
        static func comparing(_ n: Int) -> String { "Comparing \(n) on your shortlist" }
        static let candidateTitle = "Text candidate"
        static let currentTitle = "Current Text face"
        static let sourceLabel = "Source"
        static let sourceYours = "Your fonts", sourceGoogle = "+ Google Fonts", sourceAll = "All", sourceMixed = "Custom"
        static let foot = "Not made for long text"
        static func footCount(_ n: Int) -> String { "\(n) not made for long text" }
        static let findingNone = "No Text partners found."
        static let findingFaces = "Finding Text faces"
        static func finding(_ display: String) -> String { "Finding partners for \(display)" }
        static func onItsOwn(_ family: String) -> String { "\(family) on its own" }
        static let pickHeadline = "Pick a headline face to see pairs"
        static let findDisplay = "Find a Display face"
        static let showingAll = "Showing every face"
        static let onlyFit = "Only long-text faces"
        static func hiddenByFilters(_ n: Int) -> String { "\(n) hidden by filters" }
        static let pickOne = "Pick a candidate to see why it pairs."
    }

    // MARK: Template colors and layouts (10.x)

    /// The readout poster's bar labels. They print the playground's real values.
    enum Readout {
        static let display = "Display"
        static let displayItalic = "Display italic"
        static let reading = "Text"
        static func weight(_ w: Int) -> String { "Weight \(w)" }
        static func readingWeight(_ w: Int) -> String { "Text \u{00B7} \(w)" }
        static func italic(_ on: Bool) -> String { on ? "Italic on" : "Italic off" }
        static func tracking(_ em: Double) -> String { abs(em) < 0.0005 ? "Tracking 0" : String(format: "Tracking %+.3f em", em) }
        static func size(_ pt: Int) -> String { "\(pt) pt" }
    }

    /// The Scale section of the Text inspector, and the Trim slider in each face's playground (docs/copy section 14).
    enum Scale {
        static let title = "Scale"
        static let lock = "Lock"
        static let lockHelp = "Lock sizes to the ratio"
        static let body = "Body"
        static let ratio = "Ratio"
        static let autoNote = "Auto: sizes fit each font"
        static let autoHelp = "Auto sizes each face to match the board's letter height, and headlines fill their column. Lock to choose the sizes by hand."
        static let lockedHelp = "Every size is the body size times the ratio, once for each step up. Headlines still wrap and never split a word."
        static let controlsOffHelp = "Lock sizes to change the body size and ratio"
        static func bodyReadout(_ pt: Double) -> String { "\(Int(pt.rounded())) pt" }
        static func headlineReadout(_ pt: Double, times: Double) -> String {
            "Headline \(Int(pt.rounded())) pt \u{00B7} " + String(format: "%.1f", times) + "\u{00D7} body"
        }
        static func bodyLine(_ pt: Double) -> String { "Body \(Int(pt.rounded())) pt" }
        /// The footer under the Body slider: "Headline 84 pt \u{00B7} 5.6\u{00D7}" (set in caps by its label style).
        static func footer(headline: Double, times: Double) -> String {
            "Headline \(Int(headline.rounded())) pt \u{00B7} " + String(format: "%.1f", times) + "\u{00D7}"
        }
        /// The sidebar's second line under Set: "15 pt \u{00B7} 1.333", or Auto while the scale is not locked.
        static func sidebarLine(_ scale: TypeScale) -> String {
            scale.locked ? "\(Int(scale.body.rounded())) pt \u{00B7} \(TypeScale.ratioLabel(scale.ratio))" : Lexicon.auto
        }

        /// The scale readout line at the top of the Text inspector: "15 \u{00B7} 1.333", or "Auto".
        static func readoutLine(_ scale: TypeScale) -> String {
            scale.locked ? "\(Int(scale.body.rounded())) \u{00B7} \(TypeScale.ratioLabel(scale.ratio))" : Lexicon.auto
        }
        static let readoutHelp = "Open Set to change the scale"
        static func readoutAccessibility(_ scale: TypeScale) -> String {
            scale.locked ? "Scale, \(Int(scale.body.rounded())) point, ratio \(TypeScale.ratioLabel(scale.ratio)), locked" : "Scale, Auto"
        }
        static let setSubtitle = "Type scale \u{00B7} both faces"
        static let needsText = "Choose a Text face to set the scale."

        static let sectionFace = "Spacing and features"
        static let trim = "Trim"
        static let trimHelp = "Nudges every size this face gets in the templates"
        /// "+8%", "0%", "-12%".
        static func trimReadout(_ trim: Double) -> String {
            let percent = Int(((trim - 1) * 100).rounded())
            return percent > 0 ? "+\(percent)%" : "\(percent)%"
        }
    }

    enum Colors {
        static let button = "Colors"
        static let buttonHelp = "Choose the colors the templates use"
        static let layoutLabel = "Layout"
        static let layoutHelp = "Show the template in a different layout"
        static let presets = "Presets"
        static let background = "Background"
        static let text = "Text"
        static let accent = "Accent"
        static let useBrand = "Use brand colors"
        static func contrast(_ ratio: String) -> String { "Text contrast \(ratio):1" }
        static func band(_ band: ContrastBand) -> String {
            switch band {
            case .fine: "Fine for body text"
            case .largeOnly: "Large text only"
            case .tooLow: "Too low to read"
            }
        }
        static func bandSymbol(_ band: ContrastBand) -> String {
            switch band {
            case .fine: "checkmark.circle.fill"
            case .largeOnly: "exclamationmark.circle.fill"
            case .tooLow: "xmark.octagon.fill"
            }
        }
        /// VoiceOver: "Background color, #FFFFFF".
        static func swatchLabel(_ role: String, _ hex: String) -> String { "\(role) color, \(hex)" }
        static func swatchHint(_ role: String) -> String { "Edit the \(role.lowercased()) color" }
        static func presetLabel(_ name: String, selected: Bool) -> String { selected ? "\(name) preset, selected" : "\(name) preset" }
        // Color field
        static let hexLabel = "Hex color"
        static let hexPlaceholder = "RRGGBB"
        static let hexInvalid = "Use 3 or 6 hex digits, like 2B5C93"
        static let eyedropper = "Pick a color from the screen"
        static let recent = "Recent"
        static let fromPresets = "Presets"
        static let done = "Done"
        static let areaLabel = "Saturation and brightness"
        static func areaValue(_ s: Int, _ b: Int) -> String { "Saturation \(s) percent, brightness \(b) percent" }
        static let hueLabel = "Hue"
        static func hueValue(_ degrees: Int) -> String { "\(degrees) degrees" }
        static func recentLabel(_ hex: String) -> String { "Recent color, \(hex)" }
        static func presetColorLabel(_ hex: String) -> String { "Preset color, \(hex)" }
    }
}

extension String {
    /// Uppercases the first letter only ("serif with sans" -> "Serif with sans").
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
