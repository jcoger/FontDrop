import CoreText
import FontDropCore
import SwiftUI

// Stylistic sets as glyphs. A designer picks an alternate "a" by looking at it, not by reading "ss01".
// For each set the font ships we shape a probe string with the set off and on, and keep the letters whose
// glyph changed. The tile draws those letters with the set on.

/// What one stylistic set changes in a face.
struct StylisticAlternate: Identifiable, Equatable, Sendable {
    /// 1 for ss01, 2 for ss02 ...
    let number: Int
    /// The Core Text selector that switches the set on (type 35).
    let onSelector: Int
    /// The font's own name for the set ("Alt a"), or "" when the font only says "Stylistic set 3".
    let name: String
    /// The letters whose shaped glyph changes with the set on, the most telling first.
    let letters: [String]
    var id: Int { number }
    var code: String { String(format: "ss%02d", number) }
    /// The key `TypeSettings.features` stores the switch under.
    var featureKey: String { "35.\(onSelector)" }
}

enum Alternates {
    /// Letters tried, in the order a designer checks them: the ones that most often change come first.
    static let probe: [Character] = Array("agyGRQJKMWSfrtkeBDEPUZ&?@0123456789")
    /// A tile shows at most this many changed letters.
    static let lettersPerTile = 2

    private static let lock = NSLock()
    nonisolated(unsafe) private static var memo: [String: [StylisticAlternate]] = [:]

    /// The sets a file ships that change at least one probe letter. Memoised per file: shaping the probe is not free.
    /// Safe from any thread, and the font must be loaded (`FontLoader`).
    static func read(path: String) -> [StylisticAlternate] {
        lock.lock()
        if let hit = memo[path] { lock.unlock(); return hit }
        lock.unlock()
        guard case .success(let loaded)? = FontLoader.shared.cached(path), let info = FontLoader.shared.info(path) else { return [] }
        let result = compute(loaded: loaded, info: info)
        lock.lock(); memo[path] = result; lock.unlock()
        return result
    }

    static func compute(loaded: FontLoader.Loaded, info: FaceInfo) -> [StylisticAlternate] {
        let base = loaded.font(size: 40)
        let baseGlyphs = Dictionary(uniqueKeysWithValues: probe.map { ($0, glyphs(of: String($0), in: base)) })
        var out: [StylisticAlternate] = []
        for control in info.features where control.group == "Stylistic sets" {
            guard case .toggle(let type, let on, _, _) = control.kind, type == 35 else { continue }
            let font = withSet(base, selector: on)
            let changed = probe.filter { glyphs(of: String($0), in: font) != baseGlyphs[$0] }
            guard !changed.isEmpty else { continue }
            let number = on / 2
            // "ss03 · Alt a" carries the font's name after the dot. A bare "ss03" has none.
            let name = control.label.components(separatedBy: " \u{00B7} ").dropFirst().joined(separator: " \u{00B7} ")
            out.append(StylisticAlternate(number: number, onSelector: on, name: name, letters: changed.map(String.init)))
        }
        return out.sorted { $0.number < $1.number }
    }

    /// The glyph ids a single-character string shapes to. Shaping, not the cmap, so substitutions show.
    static func glyphs(of text: String, in font: CTFont) -> [CGGlyph] {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        var out: [CGGlyph] = []
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            var buffer = [CGGlyph](repeating: 0, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &buffer)
            out += buffer
        }
        return out
    }

    private static func withSet(_ font: CTFont, selector: Int) -> CTFont {
        let feature: [String: Int] = [kCTFontFeatureTypeIdentifierKey as String: 35, kCTFontFeatureSelectorIdentifierKey as String: selector]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(font),
                                                                  [kCTFontFeatureSettingsAttribute: [feature]] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
    }
}

// MARK: - The module

/// Display inspector module 03: one tile per stylistic set that changes letters. A tile shows the changed
/// letters, set in the face with the set on. Tapping switches the set. The code and the font's own name are in the hover help.
struct AlternatesModule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let job: String
    let family: FamilySummary
    @State private var sets: [StylisticAlternate] = []
    @State private var loadedPath = ""
    @State private var showAll = false

    private static let firstRow = 8

    var body: some View {
        let face = model.face(job, family)
        let key = model.settingsKey(job, family.name)
        let s = model.typeSettings.settings(key, job: job)
        let shown = showAll ? sets : Array(sets.prefix(Self.firstRow))
        VStack(alignment: .leading, spacing: 10) {
            if sets.isEmpty {
                Text(loadedPath == face.resolvedPath ? Lexicon.R4.noAlternates : "")
                    .font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: 8)], spacing: 8) {
                    ForEach(shown) { alt in tile(alt, face: face, settings: s, key: key) }
                }
                if sets.count > Self.firstRow {
                    Button { withAnimationIfAllowed { showAll.toggle() } } label: {
                        Text(showAll ? Lexicon.R4.showFewer : Lexicon.R4.showAllAlternates(sets.count))
                    }
                    .buttonStyle(.themeLink).font(.system(size: 13))
                }
                Text(Lexicon.R4.alternatesHint).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
            }
        }
        .task(id: face.resolvedPath) {
            let path = face.resolvedPath
            await FontLoader.shared.preload(paths: [path])
            let found = await Task.detached { Alternates.read(path: path) }.value
            sets = found
            loadedPath = path
        }
    }

    private func tile(_ alt: StylisticAlternate, face: FaceSpec, settings s: TypeSettings, key: String) -> some View {
        let on = (s.features[alt.featureKey] ?? 0) == 1
        var shownFace = FaceSpec(path: face.path, settings: face.settings)
        shownFace.settings.features = [alt.featureKey: 1]       // the tile always shows the set on
        let letters = alt.letters.prefix(Alternates.lettersPerTile).joined()
        let ratio = CGFloat(26 / max(face.settings.size, 1))
        return Button {
            model.typeSettings.update(key, job: job) { settings in
                if on { settings.features[alt.featureKey] = nil } else { settings.features[alt.featureKey] = 1 }
            }
        } label: {
            FaceText(face: shownFace, text: letters, ratio: ratio, tick: model.fontTick, useLineHeight: false)
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(theme.textPrimary.color)
                .frame(maxWidth: .infinity).frame(height: 56)
                .recessed(radius: 10)
                .overlay {
                    if on { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.textPrimary.color, lineWidth: 1.5) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(Lexicon.R4.alternateHelp(name: alt.name, code: alt.code))
        .accessibilityLabel(Lexicon.R4.alternateAccessibility(set: alt.number, letters: alt.letters.prefix(Alternates.lettersPerTile).map { $0 }, name: alt.name))
        .accessibilityValue(on ? "on" : "off")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
