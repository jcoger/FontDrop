import AppKit
import CoreText
import SwiftUI

// Helpers a template uses to ask a face for something it was not set to: its italic, a heavier
// weight, tabular or proportional figures. Each returns a new `FaceSpec`. Nothing is faked unless
// the caller says so: when the family has no real italic, `italic()` returns nil.

/// Which way a template wants numbers spaced.
enum Figures {
    case inherit        // whatever the playground set
    case proportional   // display numbers: the comma and point stay narrow
    case tabular        // tables, times, prices: every digit one width
}

extension TypeSettings {
    /// Core Text "Number spacing" is feature type 6 (`kNumberSpacingType`): selector 0 is tabular
    /// (`kMonospacedNumbersSelector`), 1 is proportional (`kProportionalNumbersSelector`).
    static let figureSpacingKey = "\(kNumberSpacingType)"

    func figures(_ f: Figures) -> TypeSettings {
        var s = self
        switch f {
        case .inherit: break
        case .proportional: s.features[Self.figureSpacingKey] = Int(kProportionalNumbersSelector)
        case .tabular: s.features[Self.figureSpacingKey] = Int(kMonospacedNumbersSelector)
        }
        return s
    }
}

/// What Core Text says about one font file, read once. Weight is on the CSS 100...900 scale.
struct StyleTraits: Sendable {
    var weight: Double
    var italic: Bool

    private static let lock = NSLock()
    nonisolated(unsafe) private static var memo: [String: StyleTraits] = [:]

    /// Reads the loaded probe font. Nil until the file is loaded.
    static func of(path: String) -> StyleTraits? {
        lock.lock()
        if let hit = memo[path] { lock.unlock(); return hit }
        lock.unlock()
        guard case .success(let loaded)? = FontLoader.shared.cached(path) else { return nil }
        let traits = CTFontCopyTraits(loaded.probe) as? [CFString: Any] ?? [:]
        let raw = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
        let italic = CTFontGetSymbolicTraits(loaded.probe).contains(.traitItalic)
        let result = StyleTraits(weight: cssWeight(fromTrait: raw), italic: italic)
        lock.lock(); memo[path] = result; lock.unlock()
        return result
    }

    /// Core Text's -1...1 weight trait to CSS weights, by the table Apple documents for its named weights.
    static func cssWeight(fromTrait t: Double) -> Double {
        let table: [(Double, Double)] = [(-1, 100), (-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400),
                                         (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900), (1, 900)]
        for i in 1..<table.count where t <= table[i].0 {
            let (x0, y0) = table[i - 1], (x1, y1) = table[i]
            return x1 == x0 ? y1 : y0 + (y1 - y0) * (t - x0) / (x1 - x0)
        }
        return 900
    }
}

extension FaceSpec {
    func figures(_ f: Figures) -> FaceSpec {
        var copy = self
        copy.settings = settings.figures(f)
        return copy
    }

    private var axisInfo: [FontLoader.Axis] { FontLoader.shared.info(resolvedPath)?.axes ?? [] }
    private func axis(_ tag: String) -> FontLoader.Axis? { axisInfo.first { $0.tag == tag } }

    /// The weight of one file: what the library recorded, else what Core Text reports.
    func fileWeight(_ p: String) -> Double? {
        if let w = weights[p] { return Double(w) }
        return StyleTraits.of(path: p)?.weight
    }

    /// The weight this face draws at now, CSS scale.
    var weightValue: Double {
        if let a = axis("wght") { return settings.axes["wght"] ?? a.defaultValue }
        return fileWeight(resolvedPath) ?? 400
    }

    /// Where the weight sits in the range this face offers, 0...1. Variable: its wght axis. Static: 100...900.
    var weightPosition: Double {
        if let a = axis("wght"), a.max > a.min { return (weightValue - a.min) / (a.max - a.min) }
        return (weightValue - 100) / 800
    }

    /// True when the face being drawn is an italic style (an italic file, or the ital / slnt axis turned on).
    var isItalic: Bool {
        if let v = settings.axes["ital"], v > 0.5 { return true }
        if let v = settings.axes["slnt"], v < -0.5 { return true }
        return StyleTraits.of(path: resolvedPath)?.italic ?? false
    }

    /// The same face at a weight: the wght axis when it has one, otherwise the nearest sibling file with the same slant.
    func weighted(_ weight: Double) -> FaceSpec {
        var copy = self
        if let a = axis("wght") {
            copy.settings.axes["wght"] = min(max(weight, a.min), a.max)
            return copy
        }
        let wantItalic = isItalic
        let candidates = siblings.compactMap { p -> (String, Double)? in
            guard let t = StyleTraits.of(path: p), t.italic == wantItalic else { return nil }
            return (p, abs((fileWeight(p) ?? t.weight) - weight))
        }
        // A family can ship the same weight in several widths ("Compact", "Wide", "Tall"). Stay in the width the
        // face is drawn in, so a label in semibold is not suddenly a different shape from the text around it.
        let key = StyleVariant.key(path: resolvedPath, family: familyName)
        let sameWidth = candidates.filter { StyleVariant.key(path: $0.0, family: familyName) == key }
        let best = (sameWidth.isEmpty ? candidates : sameWidth).min { ($0.1, $0.0) < ($1.1, $1.0) }
        if let best { copy.settings.stylePath = best.0 == path ? nil : best.0 }
        return copy
    }

    /// A real italic of this face, or nil when the family has none. Uses the ital or slnt axis if there is
    /// one, otherwise the sibling italic file closest in weight.
    func italic() -> FaceSpec? {
        var copy = self
        if isItalic { return self }
        if axis("ital") != nil { copy.settings.axes["ital"] = 1; return copy }
        if let a = axis("slnt") { copy.settings.axes["slnt"] = a.min; return copy }
        let w = weightValue
        let best = siblings.compactMap { p -> (String, Double)? in
            guard let t = StyleTraits.of(path: p), t.italic else { return nil }
            return (p, abs((fileWeight(p) ?? t.weight) - w))
        }.min { $0.1 < $1.1 }
        guard let best else { return nil }
        copy.settings.stylePath = best.0 == path ? nil : best.0
        return copy
    }
}

/// What a style file name says beyond weight and slant: "PP Right Serif - Compact Dark" -> "compact".
enum StyleVariant {
    private static let plain: Set<String> = [
        "thin", "hairline", "fine", "extralight", "ultralight", "light", "book", "regular", "normal", "roman", "medium",
        "semibold", "demibold", "bold", "extrabold", "ultrabold", "heavy", "dark", "black", "extra", "ultra", "semi", "demi",
        "italic", "oblique", "kursiv", "it",
    ]

    static func key(path: String, family: String) -> String {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let compactFamily = family.lowercased().filter { $0.isLetter || $0.isNumber }
        var words = StyleNames.spaced(stem).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        // Drop the family name from the front, however the file name spaces it ("PPRightSerif" or "PP Right Serif").
        var joined = ""
        while let first = words.first, joined.count < compactFamily.count, compactFamily.hasPrefix(joined + first) {
            joined += first
            words.removeFirst()
        }
        return words.filter { !plain.contains($0) }.joined(separator: " ")
    }
}

extension FaceSpec {
    /// The family name as the font file reports it. For labels like "PP Museum with Timeless Sans".
    var familyName: String {
        guard case .success(let loaded)? = FontLoader.shared.cached(resolvedPath) else { return "" }
        return CTFontCopyFamilyName(loaded.probe) as String
    }
}

/// A paragraph made of runs. Line height comes from the first run's face.
struct FaceParagraph: View {
    let runs: [TextRun]
    let ratio: CGFloat
    let base: HexColor
    let leading: Double

    var body: some View {
        if let first = runs.first, let font = FontLoader.shared.styledFont(first.face, ratio: ratio) {
            let size = CTFontGetSize(font)
            let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            Text(InlineRuns.attributed(runs, ratio: ratio, base: base))
                .exactLineHeight(CGFloat(leading) * size, natural: natural, fallbackSpacing: CGFloat(leading) * size - natural)
        } else {
            Text(runs.map(\.text).joined()).opacity(0)
        }
    }
}

// MARK: - Inline runs

/// One styled stretch of a paragraph: a word in italic, a phrase in bold, a link.
struct TextRun {
    var text: String
    var face: FaceSpec
    var color: HexColor?
    var underline = false
}

enum InlineRuns {
    /// One `AttributedString` out of runs, each in its own font. SwiftUI draws it as one paragraph that wraps normally.
    static func attributed(_ runs: [TextRun], ratio: CGFloat, base: HexColor) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if let font = FontLoader.shared.styledFont(run.face, ratio: ratio) {
                piece.font = Font(font)
                piece.tracking = CGFloat(run.face.settings.tracking) * CTFontGetSize(font)
            }
            piece.foregroundColor = (run.color ?? base).color
            if run.underline {
                piece.underlineStyle = .single
                let c = run.color ?? base
                piece.underlineColor = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
            }
            out += piece
        }
        return out
    }
}
