import CoreText
import FontDropCore
import Foundation

// Round R6: Export. One plain value (`ExportSpec`) holds everything the brand's pair says. The exporters are pure
// functions from that value to a string, so tests pin their output without loading a font.
//
//   ExportSpec.make(model:)   reads the same faces, sizes and settings the Set screen draws
//   Exporters                 CSS, Tailwind v4 theme, Paper tokens, license list
//   SpecPage (SpecPage.swift) the one-page PDF and PNG

/// One face as the exports describe it.
struct ExportFace: Equatable {
    /// "Display" or "Text".
    var role: String
    var family: String
    /// The style as the font names it ("Grand Heavy"), "Regular" when it has no style of its own.
    var style: String
    var postScript: String
    var fullName: String
    /// CSS weight of the chosen style file.
    var weight: Int
    /// The generic family the stack ends with: "serif" or "sans-serif".
    var generic: String
    /// Letter spacing in em.
    var tracking: Double
    /// The multiplier the designer set on templates (1 when untouched). Reported on the spec page only: Set draws the scale as it is.
    var trim: Double
    /// Optical size, when the designer moved it off Auto.
    var opticalSize: Double?
    /// Every other axis the designer set, by tag.
    var axes: [String: Double]
    var foundry: String?
    var foundryURL: String?
    var isTrial: Bool
    var isGoogle: Bool
}

struct ExportSpec: Equatable {
    var brandName: String
    var display: ExportFace
    var text: ExportFace
    /// Points (CSS px) per step.
    var sizes: [ScaleStep: Double]
    /// Unitless line height per step.
    var leading: [ScaleStep: Double]
    var measure: Int
    /// The measure in CSS `ch` (the width of a zero in the Text face), which is how a browser counts. Nil: same as `measure`.
    var measureCh: Int?
    var bodyLineHeight: Double
    var ratio: Double
    var bodySize: Double
    /// Brand colors as "#RRGGBB", only when the designer set them.
    var colors: Colors?

    struct Colors: Equatable {
        var background: String
        var text: String
        var accent: String
    }

    func size(_ step: ScaleStep) -> Double { sizes[step] ?? bodySize }
    func lineHeight(_ step: ScaleStep) -> Double { leading[step] ?? bodyLineHeight }
}

extension ExportSpec {
    /// The pair as Set draws it, or nil while either face is missing. Loads the style files first, so the PostScript
    /// names come from the files themselves.
    @MainActor
    static func make(model: AppModel) async -> ExportSpec? {
        guard let display = model.displayFamily, let reading = model.readingFamily else { return nil }
        await model.preloadStyles(of: [display.name, reading.name])
        let sizes = SetSizes.resolve(model: model, reading: reading)
        var size: [ScaleStep: Double] = [:], lead: [ScaleStep: Double] = [:]
        for step in ScaleStep.allCases {
            size[step] = (sizes.size(step)).rounded()
            lead[step] = step == .body ? sizes.lineHeight : TextRules.headingLeading(step: step.rawValue)
        }
        let colors = model.brandID.flatMap { model.brandStyle.palettes[$0] }.map {
            Colors(background: $0.background.hex, text: $0.text.hex, accent: $0.accent.hex)
        }
        return ExportSpec(brandName: model.brand?.name ?? "Brand",
                          display: exportFace(model, job: "display", family: display),
                          text: exportFace(model, job: "reading", family: reading),
                          sizes: size, leading: lead, measure: sizes.measure,
                          measureCh: measureInCh(model: model, reading: reading, sizes: sizes), bodyLineHeight: sizes.lineHeight,
                          ratio: sizes.ratio, bodySize: sizes.body.rounded(), colors: colors)
    }

    /// Set counts the measure in characters of the real text. CSS `ch` is the width of a zero. The column is the same
    /// width either way, so this converts: column width over the Text face's zero.
    @MainActor
    private static func measureInCh(model: AppModel, reading: FamilySummary, sizes: SetSizes) -> Int? {
        let face = model.face("reading", reading)
        guard let font = FontLoader.shared.styledFont(face, ratio: CGFloat(sizes.body / max(face.settings.size, 1))) else { return nil }
        let advance = TextRules.averageAdvance(of: ScaleStep.body.sampleLine, font: font, trackingEm: face.settings.tracking)
        let zero = TextRules.lineWidth("0", font: font, trackingEm: face.settings.tracking)
        guard advance > 0, zero > 0 else { return nil }
        return Int((TextRules.columnWidth(measure: sizes.measure, advance: advance) / zero).rounded())
    }

    @MainActor
    private static func exportFace(_ model: AppModel, job: String, family: FamilySummary) -> ExportFace {
        let face = model.face(job, family)
        let path = face.resolvedPath
        let file = model.styleFile(face, family: family.name)
        let style = model.styleLabel(face, family: family.name)
        var postScript = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        var fullName = "\(family.name) \(style)"
        if case .success(let loaded)? = FontLoader.shared.cached(path) {
            postScript = CTFontCopyPostScriptName(loaded.probe) as String
            fullName = CTFontCopyFullName(loaded.probe) as String
        }
        var axes = face.settings.axes
        let optical = axes.removeValue(forKey: "opsz")
        let entry = model.allEntries[family.name]
        let foundry = family.foundry?.trimmingCharacters(in: .whitespaces)
        return ExportFace(role: job == "display" ? "Display" : "Text", family: family.name, style: style,
                          postScript: postScript, fullName: fullName,
                          weight: face.weights[path] ?? Int(file?.weight ?? 400),
                          generic: family.serif ? "serif" : "sans-serif",
                          tracking: face.settings.tracking, trim: face.settings.trim, opticalSize: optical, axes: axes,
                          foundry: (foundry?.isEmpty ?? true) ? nil : foundry,
                          foundryURL: family.foundryUrl.flatMap { $0.isEmpty ? nil : $0 },
                          isTrial: family.isTrial, isGoogle: entry?.googleRank != nil)
    }
}

// MARK: - Exporters

enum Exporters {
    /// 47, 1.05, 0.0657: as many digits as the number needs, to `places`.
    static func num(_ v: Double, places: Int = 2) -> String {
        var s = String(format: "%.\(places)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    static func token(_ step: ScaleStep) -> String { step.label.lowercased() }

    /// A CSS string. Backslash first (or the escapes added after it would double), then the quote. A raw line break
    /// cannot sit in a CSS string, so it becomes the escape for it.
    static func quoted(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\a ")
            .replacingOccurrences(of: "\n", with: "\\a ")
            .replacingOccurrences(of: "\r", with: "\\a ")
        return "\"" + escaped + "\""
    }

    /// Text that sits inside a CSS comment. A `*/` in a brand name would close the comment early, so it is broken apart.
    static func inComment(_ s: String) -> String { s.replacingOccurrences(of: "*/", with: "* /") }

    private static func stack(_ f: ExportFace) -> String { "\(quoted(f.family)), \(f.generic)" }

    /// Rules that point the family name at the chosen style by its PostScript name, so the stack finds the real file.
    private static func fontFaces(_ spec: ExportSpec) -> String {
        [spec.display, spec.text].map { f in
            """
            @font-face {
              font-family: \(quoted(f.family));
              font-weight: \(f.weight);
              src: local(\(quoted(f.postScript))), local(\(quoted(f.fullName)));
            }
            """
        }.joined(separator: "\n")
    }

    private static func variation(_ f: ExportFace) -> String? {
        var parts: [(String, Double)] = f.axes.map { ($0.key, $0.value) }
        if let o = f.opticalSize { parts.append(("opsz", o)) }
        guard !parts.isEmpty else { return nil }
        return parts.sorted { $0.0 < $1.0 }.map { "\(quoted($0.0)) \(num($0.1))" }.joined(separator: ", ")
    }

    private static func header(_ spec: ExportSpec) -> String {
        """
        /* \(inComment(spec.brandName)) type pair
           Display: \(inComment(spec.display.family)), \(inComment(spec.display.style)) (\(inComment(spec.display.postScript)))
           Text: \(inComment(spec.text.family)), \(inComment(spec.text.style)) (\(inComment(spec.text.postScript)))
           Sizes are px. A point in FontDrop is one CSS px. */
        """
    }

    // MARK: CSS

    static func css(_ spec: ExportSpec) -> String {
        var out = [header(spec), "", fontFaces(spec), "", ":root {"]
        for (name, f) in [("display", spec.display), ("text", spec.text)] {
            out.append("  --font-\(name): \(stack(f));")
            out.append("  --font-\(name)-weight: \(f.weight);")
            out.append("  --tracking-\(name): \(num(f.tracking, places: 4))em;")
            if let v = variation(f) { out.append("  --font-\(name)-variation: \(v);") }
        }
        for step in ScaleStep.stageOrder { out.append("  --text-\(token(step)): \(num(spec.size(step)))px;") }
        for step in ScaleStep.stageOrder { out.append("  --leading-\(token(step)): \(num(spec.lineHeight(step)));") }
        out.append("  --measure: \(spec.measureCh ?? spec.measure)ch;")
        out.append("}")
        out.append("")
        out.append("/* Usage: <h1 class=\"t-display\">, <p class=\"t-body\">. One class per step. */")
        for step in ScaleStep.stageOrder {
            let name = step.isDisplayFace ? "display" : "text"
            let face = step.isDisplayFace ? spec.display : spec.text
            var rule = ".t-\(token(step)) {\n"
            rule += "  font-family: var(--font-\(name));\n"
            rule += "  font-weight: var(--font-\(name)-weight);\n"
            rule += "  font-size: var(--text-\(token(step)));\n"
            rule += "  line-height: var(--leading-\(token(step)));\n"
            rule += "  letter-spacing: var(--tracking-\(name));\n"
            if variation(face) != nil { rule += "  font-variation-settings: var(--font-\(name)-variation);\n" }
            if step == .body { rule += "  max-width: var(--measure);\n" }
            rule += "}"
            out.append(rule)
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Tailwind v4

    /// The `@theme` block. `paper` titles it for Paper, which reads the same tokens.
    static func theme(_ spec: ExportSpec, paper: Bool = false) -> String {
        var out: [String] = []
        if paper {
            out.append("/* \(inComment(spec.brandName)) type tokens for Paper. Paste into Paper's design tokens. */")
        } else {
            out.append(header(spec))
            out.append("")
            out.append(fontFaces(spec))
            out.append("")
        }
        out.append("@theme {")
        for (name, f) in [("display", spec.display), ("text", spec.text)] {
            out.append("  --font-\(name): \(stack(f));")
        }
        // The weight tokens are named "-style" on purpose. Tailwind builds `font-display` from --font-display (the family),
        // and a --font-weight-display token would claim the same class name and produce no utility. These make
        // `font-display-style` and `font-text-style`.
        for (name, f) in [("display", spec.display), ("text", spec.text)] {
            out.append("  --font-weight-\(name)-style: \(f.weight);")
        }
        for step in ScaleStep.stageOrder {
            out.append("  --text-\(token(step)): \(num(spec.size(step)))px;")
            out.append("  --text-\(token(step))--line-height: \(num(spec.lineHeight(step)));")
        }
        for step in ScaleStep.stageOrder { out.append("  --leading-\(token(step)): \(num(spec.lineHeight(step)));") }
        for (name, f) in [("display", spec.display), ("text", spec.text)] {
            out.append("  --tracking-\(name): \(num(f.tracking, places: 4))em;")
        }
        out.append("}")
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: License list

    static let trialFlag = "License before you ship"
    static let googleFlag = "Open license (Google Fonts)"
    static let ownedFlag = "Check the foundry's terms for web and app use"

    /// The flag a face carries. A trial always says license first, even when the name also sits in Google's list.
    static func licenseFlag(_ f: ExportFace) -> String {
        if f.isTrial { return trialFlag }
        if f.isGoogle { return googleFlag }
        return ownedFlag
    }

    static func licenseLine(_ f: ExportFace) -> [String] {
        var lines = ["\(f.role): \(f.family), \(f.style)"]
        lines.append("  Foundry: \(f.foundry ?? "not named in the font file")")
        lines.append("  Link: \(f.foundryURL ?? "no link in the font file")")
        lines.append("  \(licenseFlag(f))")
        return lines
    }

    static func licenses(_ spec: ExportSpec) -> String {
        (["\(spec.brandName) font licenses", ""] + licenseLine(spec.display) + [""] + licenseLine(spec.text)).joined(separator: "\n") + "\n"
    }
}
