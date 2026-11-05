import CoreText
import FontDropCore
import Foundation
import Observation

// The live type playground's data. Three parts:
//   TypeSettings       what the designer set for one face (a plain Codable struct)
//   FaceInfo           what a font file offers: styles' axes and OpenType features, read with Core Text
//   TypeSettingsStore  settings per brand + job + family, saved to a small JSON file
//
// Nothing here registers a font with the system. The settings become a CTFontDescriptor
// (variation + feature attributes) and that descriptor becomes the font that gets drawn.

/// What the designer set for one face. Empty dictionaries mean "the font's own defaults".
struct TypeSettings: Codable, Hashable, Sendable {
    /// File of the chosen style. Nil is the family's regular upright face.
    var stylePath: String?
    /// Variable axis values by 4-letter tag (wght, wdth, opsz, STYL ...).
    var axes: [String: Double] = [:]
    /// The size previews outside the templates draw at (list rows, the playground specimen, Set), in points.
    /// Not saved and not a setting: it is the job's base size. Templates solve their own sizes (TypeFit.swift)
    /// and the designer's lever is `trim`.
    var size: Double
    /// Letter spacing in em (0.02 = 2% of the font size).
    var tracking: Double = 0
    /// Line height as a multiple of the font size (1.5 = 150%).
    var lineHeight: Double
    /// Feature choices. Toggle: key "type.selector" -> 1 on, 0 off. Choice: key "type" -> selector.
    var features: [String: Int] = [:]
    /// A multiplier on every size a template solves for this face (1.08 = 8% bigger). The designer's nudge
    /// on top of Fit or the locked scale, 0.75 to 1.35.
    var trim: Double = 1

    static let trimRange: ClosedRange<Double> = 0.75...1.35

    /// Everything but `size` is saved. An older file may hold a `size` (a point size that meant something else
    /// before sizes were solved from the font); it is ignored.
    private enum CodingKeys: String, CodingKey {
        case stylePath, axes, tracking, lineHeight, features, trim
    }

    static func defaults(job: String) -> TypeSettings {
        job == "display"
            ? TypeSettings(size: 40, lineHeight: 1.1)
            : TypeSettings(size: 15, lineHeight: 1.5)
    }
}

extension TypeSettings {
    /// Forgiving on purpose: a missing or odd field takes its default, so an older settings file never fails to load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let trim = (try? c.decodeIfPresent(Double.self, forKey: .trim)) ?? 1
        self.init(stylePath: (try? c.decodeIfPresent(String.self, forKey: .stylePath)) ?? nil,
                  axes: (try? c.decodeIfPresent([String: Double].self, forKey: .axes)) ?? [:],
                  size: Self.defaults(job: "reading").size,         // the store sets the job's own base size after loading
                  tracking: (try? c.decodeIfPresent(Double.self, forKey: .tracking)) ?? 0,
                  lineHeight: (try? c.decodeIfPresent(Double.self, forKey: .lineHeight)) ?? 1.3,
                  features: (try? c.decodeIfPresent([String: Int].self, forKey: .features)) ?? [:],
                  trim: min(max(trim, Self.trimRange.lowerBound), Self.trimRange.upperBound))
    }
}

// MARK: - What a font file offers

/// One OpenType feature the font ships, shaped into a control.
struct FeatureControl: Identifiable, Sendable {
    enum Kind: Sendable {
        /// One switch. `on` / `off` are the selector ids Core Text wants.
        case toggle(type: Int, on: Int, off: Int, defaultOn: Bool)
        /// Pick one: Default, then these.
        case choice(type: Int, options: [(selector: Int, label: String)])
    }
    let id: String
    let group: String
    let label: String
    let kind: Kind
}

struct FaceInfo: Sendable {
    var axes: [FontLoader.Axis]       // visible axes only
    var features: [FeatureControl]
}

enum FaceInspector {
    /// Reads axes and features from a loaded face. Cheap enough to call from a view, and memoised by `FontLoader`.
    static func read(_ loaded: FontLoader.Loaded) -> FaceInfo {
        FaceInfo(axes: loaded.axes.filter { !$0.hidden && $0.max > $0.min },
                 features: features(of: loaded.probe))
    }

    /// The groups the playground shows. Core Text reports every OpenType feature as an
    /// AAT type + selector pair, so "ss05" arrives as type 35, selector 10.
    static func features(of font: CTFont) -> [FeatureControl] {
        guard let raw = CTFontCopyFeatures(font) as? [[String: Any]] else { return [] }
        var byType: [Int: [(selector: Int, name: String, isDefault: Bool)]] = [:]
        for t in raw {
            guard let type = (t[kCTFontFeatureTypeIdentifierKey as String] as? NSNumber)?.intValue,
                  let sels = t[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] else { continue }
            byType[type] = sels.compactMap { s in
                guard let id = (s[kCTFontFeatureSelectorIdentifierKey as String] as? NSNumber)?.intValue else { return nil }
                let name = s[kCTFontFeatureSelectorNameKey as String] as? String ?? ""
                let def = (s[kCTFontFeatureSelectorDefaultKey as String] as? NSNumber)?.intValue == 1
                return (id, name, def)
            }
        }
        var out: [FeatureControl] = []
        func has(_ type: Int, _ selector: Int) -> Bool { byType[type]?.contains { $0.selector == selector } ?? false }

        // Stylistic sets: type 35. Even selectors switch a set on (2 = ss01, 4 = ss02 ...); the next odd one switches it off.
        for s in (byType[35] ?? []).sorted(by: { $0.selector < $1.selector }) where s.selector % 2 == 0 {
            let n = s.selector / 2
            let generic = s.name.isEmpty || s.name.lowercased().hasPrefix("stylistic set")
            let label = generic ? String(format: "ss%02d", n) : String(format: "ss%02d \u{00B7} %@", n, s.name)
            out.append(FeatureControl(id: "35.\(s.selector)", group: "Stylistic sets", label: label,
                                      kind: .toggle(type: 35, on: s.selector, off: s.selector + 1, defaultOn: false)))
        }
        if has(37, 1) {
            out.append(FeatureControl(id: "37.1", group: "Letters", label: "Small caps",
                                      kind: .toggle(type: 37, on: 1, off: 0, defaultOn: false)))
        }
        if has(38, 1) {
            out.append(FeatureControl(id: "38.1", group: "Letters", label: "Capitals to small caps",
                                      kind: .toggle(type: 38, on: 1, off: 0, defaultOn: false)))
        }
        if has(36, 0) {
            out.append(FeatureControl(id: "36.0", group: "Letters", label: "Contextual alternates",
                                      kind: .toggle(type: 36, on: 0, off: 1, defaultOn: true)))
        }
        if has(1, 2) {
            out.append(FeatureControl(id: "1.2", group: "Letters", label: "Common ligatures",
                                      kind: .toggle(type: 1, on: 2, off: 3, defaultOn: true)))
        }
        // Figures: case (old-style / lining) and spacing (tabular / proportional).
        var figures: [(Int, String)] = []
        if has(21, 0) { figures.append((0, "Old-style")) }
        if has(21, 1) { figures.append((1, "Lining")) }
        if !figures.isEmpty {
            out.append(FeatureControl(id: "21", group: "Figures", label: "Figure style",
                                      kind: .choice(type: 21, options: figures.map { (selector: $0.0, label: $0.1) })))
        }
        var spacing: [(Int, String)] = []
        if has(6, 0) { spacing.append((0, "Tabular")) }
        if has(6, 1) { spacing.append((1, "Proportional")) }
        if !spacing.isEmpty {
            out.append(FeatureControl(id: "6", group: "Figures", label: "Figure spacing",
                                      kind: .choice(type: 6, options: spacing.map { (selector: $0.0, label: $0.1) })))
        }
        return out
    }
}

// MARK: - Settings -> a font

extension TypeSettings {
    /// The Core Text feature settings for the choices in `features`.
    var featureAttribute: [[String: Int]] {
        var list: [[String: Int]] = []
        for (key, value) in features.sorted(by: { $0.key < $1.key }) {
            let parts = key.split(separator: ".").compactMap { Int($0) }
            func pair(_ type: Int, _ selector: Int) -> [String: Int] {
                [kCTFontFeatureTypeIdentifierKey as String: type, kCTFontFeatureSelectorIdentifierKey as String: selector]
            }
            if parts.count == 2 {
                // Toggle. Off is the "on" selector + 1 for stylistic sets and ligatures, and fixed pairs for the rest.
                let (type, on) = (parts[0], parts[1])
                let off: Int
                switch (type, on) {
                case (37, 1), (38, 1): off = 0
                case (36, 0): off = 1
                default: off = on + 1
                }
                list.append(pair(type, value == 1 ? on : off))
            } else if parts.count == 1 {
                list.append(pair(parts[0], value))
            }
        }
        return list
    }

    /// Builds the font to draw. `ratio` scales the base size (a template's role: headline 1.0, caption 0.8 ...).
    func font(from loaded: FontLoader.Loaded, axisInfo: [FontLoader.Axis], ratio: CGFloat = 1) -> CTFont {
        var attrs: [CFString: Any] = [:]
        var variation: [NSNumber: Double] = [:]
        let size = CGFloat(self.size) * ratio
        for axis in axisInfo {
            if let v = axes[axis.tag] {
                variation[NSNumber(value: axis.identifier)] = min(max(v, axis.min), axis.max)
            } else if axis.tag == "opsz" {
                // Optical size follows the size drawn, unless the designer moved the slider. Core Text does this itself
                // for Apple's fonts, but a third-party font can stay at its default (12 for one, 96 for another).
                variation[NSNumber(value: axis.identifier)] = min(max(Double(size), axis.min), axis.max)
            }
        }
        if !variation.isEmpty { attrs[kCTFontVariationAttribute] = variation }
        let feats = featureAttribute
        if !feats.isEmpty { attrs[kCTFontFeatureSettingsAttribute] = feats }
        guard !attrs.isEmpty else { return CTFontCreateWithFontDescriptor(loaded.descriptor, size, nil) }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(loaded.descriptor, attrs as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

/// What to do with a saved style file path that may no longer exist.
enum StylePathRepair {
    /// The path itself when the library lists it; else the listed file with the same name (any folder, any
    /// extension: a font manager moves files, and a style may now be listed as .otf instead of .ttf); else nil.
    static func repaired(_ path: String, valid: [String]) -> String? {
        if valid.contains(path) { return path }
        func stem(_ p: String) -> String { URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent.lowercased() }
        let wanted = stem(path)
        // Prefer .otf, as the library's own de-duplication does.
        let same = valid.filter { stem($0) == wanted }
        return same.first { $0.lowercased().hasSuffix(".otf") } ?? same.first
    }
}

// MARK: - Store

/// Settings per brand + job + family, kept in memory and saved in the library database (the core's `face_settings`
/// table). The key is "brand/job/family". Settings made with no brand yet stay in memory: there is no brand row to
/// hang them on. Screenshot, bench and test runs read the database but never write it.
@MainActor @Observable
final class TypeSettingsStore {
    private(set) var map: [String: TypeSettings] = [:]
    private let writer: WriteBehind<String>

    init(persist: Bool = true) {
        var read: (@MainActor (String) -> TypeSettings?)?
        writer = WriteBehind(persist: persist) { key in
            guard let (brand, job, family) = Self.split(key), brand != 0 else { return nil }
            guard let s = read?(key) else { return { try $0.faceClear(brand: brand, job: job, family: family) } }
            let row = FaceSettings(brandId: brand, job: job, family: family, stylePath: s.stylePath, tracking: s.tracking,
                                   lineHeight: s.lineHeight, trim: s.trim,
                                   axesJson: Self.json(s.axes), featuresJson: Self.json(s.features))
            return { try $0.faceSet(face: row) }
        }
        read = { [weak self] key in self?.map[key] }
    }

    /// The library is open: read every brand's face settings from it, and write changes to it from now on.
    func attach(_ library: Library) {
        writer.library = library
        let rows = (try? library.facesList()) ?? []
        for row in rows {
            let decoder = JSONDecoder()
            var s = TypeSettings.defaults(job: row.job)         // `size` is the job's base size, never saved
            s.stylePath = row.stylePath
            s.tracking = row.tracking
            s.lineHeight = row.lineHeight
            s.trim = min(max(row.trim, TypeSettings.trimRange.lowerBound), TypeSettings.trimRange.upperBound)
            s.axes = (try? decoder.decode([String: Double].self, from: Data(row.axesJson.utf8))) ?? [:]
            s.features = (try? decoder.decode([String: Int].self, from: Data(row.featuresJson.utf8))) ?? [:]
            map[Self.key(brand: row.brandId, job: row.job, family: row.family)] = s
        }
    }

    private static func json<V: Encodable>(_ value: V) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// "1/display/Acme Serif" -> (1, "display", "Acme Serif"). The family may itself hold a slash.
    nonisolated static func split(_ key: String) -> (Int64, String, String)? {
        let parts = key.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let brand = Int64(parts[0]) else { return nil }
        return (brand, String(parts[1]), String(parts[2]))
    }

    /// The brand is gone (the database already dropped its rows).
    func forget(brand: Int64) {
        for key in map.keys where Self.split(key)?.0 == brand { map[key] = nil }
    }

    /// The first brand was just made: settings made with no brand yet ("0/job/family") move onto it and are saved.
    /// What the brand already holds (from the database) stays.
    func adoptUnbranded(into brand: Int64) {
        for (key, settings) in map {
            guard let (b, job, family) = Self.split(key), b == 0 else { continue }
            map[key] = nil
            let target = Self.key(brand: brand, job: job, family: family)
            if map[target] == nil { map[target] = settings; writer.mark(target) }
        }
    }

    func flush() { writer.flush() }

    static func key(brand: Int64?, job: String, family: String) -> String { "\(brand ?? 0)/\(job)/\(family)" }

    /// Where a face's Style picker starts when the designer has not set anything: the engine's
    /// suggested body style for a "Same family" pair. Never saved on its own (see `adoptSuggestion`).
    private(set) var suggestedStyle: [String: String] = [:]

    private func defaults(_ key: String, job: String) -> TypeSettings {
        var d = TypeSettings.defaults(job: job)
        d.stylePath = suggestedStyle[key]
        return d
    }

    func settings(_ key: String, job: String) -> TypeSettings { map[key] ?? defaults(key, job: job) }

    func isModified(_ key: String, job: String) -> Bool { (map[key] ?? defaults(key, job: job)) != defaults(key, job: job) }

    /// Replaces the suggested starting styles (one per Same family card on screen).
    func setSuggestedStyles(_ styles: [String: String]) {
        if styles != suggestedStyle { suggestedStyle = styles }
    }

    /// The designer chose this face: keep the suggested style as their setting so it survives a relaunch.
    func adoptSuggestion(_ key: String, job: String) {
        guard map[key] == nil, let path = suggestedStyle[key] else { return }
        update(key, job: job) { $0.stylePath = path }
    }

    func update(_ key: String, job: String, _ change: (inout TypeSettings) -> Void) {
        var s = settings(key, job: job)
        change(&s)
        map[key] = s
        writer.mark(key)
    }

    func reset(_ key: String) {
        map[key] = nil
        writer.mark(key)
    }

    /// A saved Style is a file path. When the file moved or was replaced, the path points at nothing and every
    /// preview in that family draws blank. After the library changes, remap such a path to the family's file
    /// with the same name (a .ttf twin of a style listed as .otf counts), or drop it so the family's regular shows.
    /// `files`: every file the library lists, by family. `regular`: each family's own regular file. Returns how many changed.
    @discardableResult
    func repairStylePaths(files: [String: [String]], regular: [String: String]) -> Int {
        var changed = 0
        for (key, settings) in map {
            guard let path = settings.stylePath else { continue }
            // The key is "brand/job/family"; the family may itself hold a slash.
            let parts = key.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let family = String(parts[2])
            guard let listed = files[family] else { continue }      // family not in the library: keep what was saved
            var valid = listed
            if let r = regular[family] { valid.append(r) }
            let fixed = StylePathRepair.repaired(path, valid: valid)
            guard fixed != path else { continue }
            map[key]?.stylePath = fixed         // nil drops it
            writer.mark(key)
            changed += 1
        }
        return changed
    }
}
