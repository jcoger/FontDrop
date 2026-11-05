import Foundation
import Observation

/// What the templates look like for a brand: the three colors (per brand), which variant of each
/// template is showing (per template), and the recent colors (one list for every brand).
///
/// Saved the way the playground saves: colors go to a small JSON file next to the library DB,
/// so a test DB copy gets its own file. Screenshot and bench runs read but never write.
/// React: a small store with `localStorage` behind it.
@MainActor @Observable
final class BrandStyleStore {
    private(set) var palettes: [String: TemplatePalette] = [:]
    private(set) var variants: [String: String]
    private(set) var recents: [HexColor]

    /// UI state for the Colors popover. Lives here so the screenshot runner can open it.
    var showColors = false
    var editingRole: ColorRole?

    private let url: URL
    private let persist: Bool
    private let defaults: UserDefaults
    private var saveTask: Task<Void, Never>?

    static let variantsKey = "readingVariants"
    static let recentsKey = "recentColors"
    static let recentLimit = 8

    init(dbPath: String, persist: Bool = true, defaults: UserDefaults = .standard) {
        url = URL(fileURLWithPath: dbPath + ".colors.json")
        self.persist = persist
        self.defaults = defaults
        variants = (defaults.dictionary(forKey: Self.variantsKey) as? [String: String]) ?? [:]
        recents = (defaults.stringArray(forKey: Self.recentsKey) ?? []).compactMap { HexColor(hex: $0) }
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: TemplatePalette].self, from: data) {
            palettes = decoded
        }
    }

    static func key(brand: Int64?) -> String { "\(brand ?? 0)" }

    // MARK: Colors

    func palette(brand: Int64?) -> TemplatePalette { palettes[Self.key(brand: brand)] ?? .paper }

    func setPalette(_ palette: TemplatePalette, brand: Int64?) {
        palettes[Self.key(brand: brand)] = palette == .paper ? nil : palette
        scheduleSave()
    }

    func setColor(_ role: ColorRole, _ color: HexColor, brand: Int64?) {
        var p = palette(brand: brand)
        p[keyPath: role.keyPath] = color
        setPalette(p, brand: brand)
    }

    /// Adds to the front of the recent list: newest first, no repeats, last 8.
    func remember(_ color: HexColor) {
        var list = recents.filter { $0 != color }
        list.insert(color, at: 0)
        recents = Array(list.prefix(Self.recentLimit))
        if persist { defaults.set(recents.map(\.hex), forKey: Self.recentsKey) }
    }

    // MARK: Variants

    /// The variant showing for a template. The first one the template lists until one is picked.
    func variant(_ template: TemplateDescriptor) -> String {
        if let id = variants[template.id], template.variants.contains(where: { $0.id == id }) { return id }
        return template.variants.first?.id ?? ""
    }

    func setVariant(_ id: String, template: TemplateDescriptor) {
        variants[template.id] = id
        if persist { defaults.set(variants, forKey: Self.variantsKey) }
    }

    // MARK: Saving

    private func scheduleSave() {
        guard persist else { return }
        let url = self.url
        saveTask?.cancel()
        let snapshot = palettes
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))      // a color drag is many updates; write once
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
