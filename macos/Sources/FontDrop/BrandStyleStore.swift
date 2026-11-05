import FontDropCore
import Foundation
import Observation

/// What the templates look like for a brand: the three colors (per brand), which variant of each
/// template is showing (per template), and the recent colors (one list for every brand).
///
/// Colors are saved in the library database (the core's `brand_colors` table), per brand. Variants and recent colors
/// stay in the app's preferences. Screenshot and bench runs read but never write.
/// React: a small store with `localStorage` behind it.
@MainActor @Observable
final class BrandStyleStore {
    private(set) var palettes: [Int64: TemplatePalette] = [:]
    /// Colors set with no brand yet: in memory only.
    private var unbranded: TemplatePalette?
    private(set) var variants: [String: String]
    private(set) var recents: [HexColor]

    /// UI state for the Colors popover. Lives here so the screenshot runner can open it.
    var showColors = false
    var editingRole: ColorRole?

    private let persist: Bool
    private let defaults: UserDefaults
    private let writer: WriteBehind<Int64>

    static let variantsKey = "readingVariants"
    static let recentsKey = "recentColors"
    static let recentLimit = 8

    init(persist: Bool = true, defaults: UserDefaults = .standard) {
        self.persist = persist
        self.defaults = defaults
        variants = (defaults.dictionary(forKey: Self.variantsKey) as? [String: String]) ?? [:]
        recents = (defaults.stringArray(forKey: Self.recentsKey) ?? []).compactMap { HexColor(hex: $0) }
        var read: (@MainActor (Int64) -> TemplatePalette?)?
        writer = WriteBehind(persist: persist) { id in
            guard let p = read?(id) else { return { try $0.colorsClear(brand: id) } }
            let row = BrandColors(brandId: id, background: p.background.hex, text: p.text.hex, accent: p.accent.hex)
            return { try $0.colorsSet(colors: row) }
        }
        read = { [weak self] id in self?.palettes[id] }
    }

    /// The library is open: read every brand's colors from it, and write changes to it from now on.
    func attach(_ library: Library) {
        writer.library = library
        for row in (try? library.colorsList()) ?? [] {
            guard let b = HexColor(hex: row.background), let t = HexColor(hex: row.text), let a = HexColor(hex: row.accent) else { continue }
            palettes[row.brandId] = TemplatePalette(background: b, text: t, accent: a)
        }
    }

    /// The brand is gone (the database already dropped its colors).
    func forget(brand: Int64) { palettes[brand] = nil }

    func flush() { writer.flush() }

    // MARK: Colors

    func palette(brand: Int64?) -> TemplatePalette {
        guard let brand else { return unbranded ?? .paper }
        return palettes[brand] ?? .paper
    }

    func setPalette(_ palette: TemplatePalette, brand: Int64?) {
        guard let brand else { unbranded = palette == .paper ? nil : palette; return }
        palettes[brand] = palette == .paper ? nil : palette
        writer.mark(brand)
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
}
