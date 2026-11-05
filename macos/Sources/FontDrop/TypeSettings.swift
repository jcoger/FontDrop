import CoreText
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
    /// Base size in points. Templates scale their other sizes from it.
    var size: Double
    /// Letter spacing in em (0.02 = 2% of the font size).
    var tracking: Double = 0
    /// Line height as a multiple of the font size (1.5 = 150%).
    var lineHeight: Double
    /// Feature choices. Toggle: key "type.selector" -> 1 on, 0 off. Choice: key "type" -> selector.
    var features: [String: Int] = [:]

    static func defaults(job: String) -> TypeSettings {
        job == "display"
            ? TypeSettings(size: 40, lineHeight: 1.1)
            : TypeSettings(size: 15, lineHeight: 1.5)
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
        for axis in axisInfo {
            if let v = axes[axis.tag] { variation[NSNumber(value: axis.identifier)] = min(max(v, axis.min), axis.max) }
        }
        if !variation.isEmpty { attrs[kCTFontVariationAttribute] = variation }
        let feats = featureAttribute
        if !feats.isEmpty { attrs[kCTFontFeatureSettingsAttribute] = feats }
        let size = CGFloat(self.size) * ratio
        guard !attrs.isEmpty else { return CTFontCreateWithFontDescriptor(loaded.descriptor, size, nil) }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(loaded.descriptor, attrs as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

// MARK: - Store

/// Settings per brand + job + family. Saved as JSON next to the library DB, so a test
/// DB copy gets its own file and never touches the live one. A candidate to move into
/// the core (and the DB) later, once the Set screen needs the same numbers.
@MainActor @Observable
final class TypeSettingsStore {
    private(set) var map: [String: TypeSettings] = [:]
    private let url: URL
    private let persist: Bool
    private var saveTask: Task<Void, Never>?

    init(dbPath: String, persist: Bool = true) {
        url = URL(fileURLWithPath: dbPath + ".playground.json")
        self.persist = persist
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: TypeSettings].self, from: data) {
            map = decoded
        }
    }

    static func key(brand: Int64?, job: String, family: String) -> String { "\(brand ?? 0)/\(job)/\(family)" }

    func settings(_ key: String, job: String) -> TypeSettings { map[key] ?? .defaults(job: job) }

    func isModified(_ key: String, job: String) -> Bool { (map[key] ?? .defaults(job: job)) != .defaults(job: job) }

    func update(_ key: String, job: String, _ change: (inout TypeSettings) -> Void) {
        var s = settings(key, job: job)
        change(&s)
        map[key] = s
        scheduleSave()
    }

    func reset(_ key: String) {
        map[key] = nil
        scheduleSave()
    }

    private func scheduleSave() {
        guard persist else { return }       // screenshot and bench runs read settings but never write them
        let url = self.url
        saveTask?.cancel()
        let snapshot = map
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))      // a slider drag is many updates; write once
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
