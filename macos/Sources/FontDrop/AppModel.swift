import FontDropCore
import Foundation
import Observation

// MARK: - Launch options

/// Command-line options. All optional. Examples:
///   FontDrop --db /path/to/copy.db
///   FontDrop --db copy.db --screenshot out.png --screen reading --appearance dark
/// DB path order: --db, $FONTDROP_DB, the shared app-support DB the Tauri app uses.
struct LaunchOptions {
    var dbPath: String
    var bench = false
    var refresh = false
    var screenshot: String?
    var screen: Screen = .display
    var appearance: String?      // "light" | "dark"
    var brand: String?
    var select: String?          // family to select (Display) or candidate (Reading)

    init(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        dbPath = value("--db")
            ?? environment["FONTDROP_DB"]
            ?? NSHomeDirectory() + "/Library/Application Support/co.dynolabs.fontdrop/fontdrop.db"
        bench = arguments.contains("--bench")
        refresh = arguments.contains("--refresh")
        screenshot = value("--screenshot")
        if let s = value("--screen"), let sc = Screen(rawValue: s) { screen = sc }
        appearance = value("--appearance")
        brand = value("--brand")
        select = value("--select")
    }
}

// MARK: - Screens

enum Screen: String, Hashable, CaseIterable, Identifiable {
    case display, reading, ui, mono, set, colors
    var id: String { rawValue }

    /// The core's job name for the four "Type" screens.
    var job: String? {
        switch self {
        case .display, .reading, .ui, .mono: rawValue
        case .set, .colors: nil
        }
    }

    var title: String {
        switch self {
        case .display: "Display"
        case .reading: "Reading"
        case .ui: "UI"
        case .mono: "Mono"
        case .set: "Set"
        case .colors: "Colors"
        }
    }

    var symbol: String {
        switch self {
        case .display: "textformat.size"
        case .reading: "text.alignleft"
        case .ui: "rectangle.on.rectangle"
        case .mono: "chevron.left.forwardslash.chevron.right"
        case .set: "slider.horizontal.3"
        case .colors: "circle.lefthalf.filled"
        }
    }
}

enum FamilyCategory: String, CaseIterable, Identifiable {
    case all = "All", serif = "Serif", sans = "Sans"
    var id: String { rawValue }
}

extension FamilySummary: @retroactive Identifiable { public var id: String { fontId } }
extension Brand: @retroactive Identifiable {}

/// What the inspector shows for a family. Built off the main thread.
struct FamilyDetail {
    var family: String
    var styles: [FontFile]
    var axes: [FontLoader.Axis]
    var xHeight: Double?
    var canLoad: Bool
}

// MARK: - Model

enum Phase: Equatable { case loading, ready, failed(String) }

@MainActor @Observable
final class AppModel {
    let options: LaunchOptions
    var dbPath: String { options.dbPath }

    private(set) var core: Library?
    private(set) var phase: Phase = .loading

    // Navigation and search
    var screen: Screen = .display
    var search = ""
    var showInspector = true

    // Library (read once, then filtered in memory)
    private(set) var families: [FamilySummary] = []          // user-installed first, then by name
    private(set) var familyByName: [String: FamilySummary] = [:]
    private(set) var fontsByFamily: [String: [FontFile]] = [:]
    private(set) var fontCount = 0

    /// Bumps while fonts load in the background. Views take it as a plain value so they redraw.
    private(set) var fontTick = 0
    private(set) var fontsReady = false
    private(set) var timings: [(label: String, ms: Double)] = []

    // Brands and the designer's choices
    private(set) var brands: [Brand] = []
    private(set) var brandID: Int64?
    private(set) var choices: [String: String] = [:]         // job -> family
    private(set) var shortlists: [String: [String]] = [:]    // job -> families

    // Display (and UI, Mono) grid
    var category: FamilyCategory = .all
    var selectedFamily: String?

    // Reading
    var lenses = Lenses()
    private(set) var candidates: [Candidate] = []
    private(set) var candidatesLoading = false
    private(set) var candidatesError: String?
    var selectedCandidate: String?
    private var candidatesKey: String?

    var errorMessage: String?

    init(options: LaunchOptions) { self.options = options }

    // MARK: derived

    var brand: Brand? { brands.first { $0.id == brandID } }
    /// The text the Display cards draw. "Aa Bb" until there is a brand.
    var sampleText: String { brand?.name ?? "Aa Bb" }
    var displayFamily: FamilySummary? { choices["display"].flatMap { familyByName[$0] } }
    var readingFamily: FamilySummary? { choices["reading"].flatMap { familyByName[$0] } }

    func chosen(_ screen: Screen) -> String? { screen.job.flatMap { choices[$0] } }

    func shortlist(_ job: String) -> [String] { shortlists[job] ?? [] }

    /// Families for the grid: category + search. Nothing else is hidden.
    var visibleFamilies: [FamilySummary] {
        var list = families
        switch category {
        case .all: break
        case .serif: list = list.filter { $0.serif }
        case .sans: list = list.filter { !$0.serif }
        }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(q) } }
        return list
    }

    var readingResult: (shown: [Candidate], hidden: Int) {
        LensEngine.apply(candidates, lenses: lenses, search: search)
    }

    // MARK: background helper

    private func background<T: Sendable>(_ work: @escaping @Sendable (Library) throws -> T) async throws -> T {
        guard let lib = core else { throw CoreError.Invalid("library not open") }
        return try await Task.detached(priority: .userInitiated) { try work(lib) }.value
    }

    private func report(_ error: Error) { errorMessage = "\(error)" }

    // MARK: bootstrap

    func bootstrap() async {
        let db = dbPath
        setvbuf(stdout, nil, _IOLBF, 0); print("FONTDROP bootstrap start db=\(db) refresh=\(options.refresh)")
        do {
            let t0 = DispatchTime.now()
            let lib = try await Task.detached(priority: .userInitiated) { try Library.open(path: db) }.value
            core = lib
            let t1 = DispatchTime.now()
            if options.refresh { print("FONTDROP refreshing library...")
                _ = try await Task.detached(priority: .utility) { try lib.refreshLibrary() }.value
            }
            let t2 = DispatchTime.now()
            let (fams, fonts, brands) = try await Task.detached(priority: .userInitiated) {
                (try lib.listFamilies(), try lib.listFonts(), try lib.brandsList())
            }.value
            let t3 = DispatchTime.now()

            let home = NSHomeDirectory()
            families = fams.sorted {
                let a = Self.tier($0.filePath, home: home), b = Self.tier($1.filePath, home: home)
                return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            familyByName = Dictionary(fams.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            fontsByFamily = Dictionary(grouping: fonts, by: \.family)
            fontCount = fonts.count
            self.brands = brands
            timings.append(("open (migrate)", ms(t0, t1)))
            if options.refresh { timings.append(("refresh_library", ms(t1, t2))) }
            timings.append(("list_families + list_fonts + brands (\(fams.count) families)", ms(t2, t3)))

            let saved = UserDefaults.standard.object(forKey: "lastBrand") as? Int64
            let wanted = options.brand.flatMap { n in brands.first { $0.name == n }?.id }
            await selectBrand(wanted ?? brands.first { $0.id == saved }?.id ?? brands.first?.id)
            screen = options.screen
            phase = .ready

            // Fonts load here, off the main thread, in batches. Cards redraw as each batch lands.
            let p0 = DispatchTime.now()
            await FontLoader.shared.preload(paths: fams.map(\.filePath)) { n in
                Task { @MainActor [weak self] in self?.fontTick = n }
            }
            timings.append(("preload \(fams.count) family fonts", ms(p0, DispatchTime.now())))
            fontsReady = true
            fontTick += 1
            if options.bench || options.screenshot != nil { print("FONTDROP ready: \(families.count) families") }
        } catch {
            phase = .failed("\(error)")
            return
        }
        // Like the Tauri app: show what the DB already has, then rescan in the
        // background (new or removed fonts, classifier updates) and reload.
        // Skipped for --screenshot / --bench so those runs stay repeatable.
        if !options.refresh && !options.bench && options.screenshot == nil, let lib = core {
            await refreshInBackground(lib)
        }
    }

    private func refreshInBackground(_ lib: Library) async {
        do {
            _ = try await Task.detached(priority: .utility) { try lib.refreshLibrary() }.value
            let (fams, fonts) = try await Task.detached(priority: .userInitiated) {
                (try lib.listFamilies(), try lib.listFonts())
            }.value
            let home = NSHomeDirectory()
            families = fams.sorted {
                let a = Self.tier($0.filePath, home: home), b = Self.tier($1.filePath, home: home)
                return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            familyByName = Dictionary(fams.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            fontsByFamily = Dictionary(grouping: fonts, by: \.family)
            fontCount = fonts.count
            await FontLoader.shared.preload(paths: fams.map(\.filePath)) { n in
                Task { @MainActor [weak self] in self?.fontTick = n }
            }
            fontTick += 1
        } catch {
            // A failed rescan keeps the library as it was; nothing to show the user yet.
            print("FONTDROP background refresh failed: \(error)")
        }
    }

    /// 0 user-installed, 1 /Library, 2 other, 3 system.
    nonisolated static func tier(_ path: String, home: String) -> Int {
        if path.hasPrefix(home + "/Library/Fonts") { return 0 }
        if path.hasPrefix("/Library/Fonts") { return 1 }
        if path.hasPrefix("/System") { return 3 }
        return 2
    }

    // MARK: brands

    func selectBrand(_ id: Int64?) async {
        brandID = id
        if let id { UserDefaults.standard.set(id, forKey: "lastBrand") }
        candidates = []; candidatesKey = nil; selectedCandidate = nil
        await reloadBrandData()
    }

    private func reloadBrandData() async {
        guard let id = brandID else { choices = [:]; shortlists = [:]; return }
        do {
            let (cs, lists) = try await background { lib -> ([Choice], [String: [String]]) in
                var lists: [String: [String]] = [:]
                for job in jobs() { lists[job] = try lib.shortlistGet(brand: id, job: job) }
                return (try lib.choices(brand: id), lists)
            }
            choices = Dictionary(cs.map { ($0.job, $0.fontFamily) }, uniquingKeysWith: { _, b in b })
            shortlists = lists
            if selectedFamily == nil { selectedFamily = choices["display"] }
        } catch { report(error) }
    }

    func createBrand(_ name: String) async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        do {
            let b = try await background { try $0.brandCreate(name: n) }
            brands = try await background { try $0.brandsList() }
            await selectBrand(b.id)
        } catch { report(error) }
    }

    func renameBrand(_ brand: Brand, to name: String) async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != brand.name else { return }
        let id = brand.id, logo = brand.logoSvg
        do {
            try await background { try $0.brandUpdate(id: id, name: n, logoSvg: logo) }
            brands = try await background { try $0.brandsList() }
        } catch { report(error) }
    }

    // MARK: choices and shortlist

    func choose(_ job: String, family: String) async {
        guard let id = brandID else { errorMessage = "Create a brand first. Choices belong to a brand."; return }
        do {
            try await background { try $0.choose(brand: id, job: job, family: family) }
            choices[job] = family
            if job == "display" { candidates = []; candidatesKey = nil; selectedCandidate = nil }
        } catch { report(error) }
    }

    func setShortlist(_ job: String, family: String, on: Bool) async {
        guard let id = brandID else { errorMessage = "Create a brand first. Shortlists belong to a brand."; return }
        var list = shortlists[job] ?? []
        if on { if !list.contains(family) { list.append(family) } } else { list.removeAll { $0 == family } }
        shortlists[job] = list
        do {
            try await background { try $0.shortlistSet(brand: id, job: job, family: family, on: on) }
        } catch {
            report(error)
            await reloadBrandData()
        }
    }

    // MARK: reading candidates

    /// Asks the core for Reading partners of the chosen Display face. Fonts for every
    /// candidate are loaded before the list is shown, so the cards never write state.
    func loadCandidates() async {
        guard let display = displayFamily else { candidates = []; candidatesKey = nil; return }
        let key = "\(brandID ?? 0)/\(display.fontId)"
        if key == candidatesKey { return }
        candidatesLoading = true
        candidatesError = nil
        let id = display.fontId
        do {
            let buckets = try await background { try $0.fontPairs(fontId: id, excludedIds: [], job: "reading") }
            var seen = Set<String>()
            var list: [Candidate] = []
            for bucket in buckets {
                for p in bucket.pairs where !p.family.isEmpty && seen.insert(p.family).inserted {
                    // Show the family's regular upright face, not whichever file the engine matched.
                    let path = familyByName[p.family]?.filePath ?? p.filePath
                    list.append(Candidate(id: p.fontId, family: p.family, filePath: path,
                                          pairType: p.pairType, evidence: p.evidence, order: list.count))
                }
            }
            await FontLoader.shared.preload(paths: list.map(\.filePath))
            guard displayFamily?.fontId == id else { return }   // changed while loading
            candidates = list
            candidatesKey = key
            fontTick += 1
            if selectedCandidate == nil || !list.contains(where: { $0.id == selectedCandidate }) {
                selectedCandidate = options.select.flatMap { s in list.first { $0.family == s }?.id }
                    ?? readingResult.shown.first?.id
            }
        } catch {
            candidatesError = "\(error)"
        }
        candidatesLoading = false
    }

    func candidate(_ id: String?) -> Candidate? { candidates.first { $0.id == id } }

    // MARK: inspector detail

    func detail(for name: String) async -> FamilyDetail? {
        guard let fam = familyByName[name] else { return nil }
        let styles = (fontsByFamily[name] ?? []).sorted { ($0.weight, $0.name) < ($1.weight, $1.name) }
        let paths = styles.map(\.filePath)
        return await Task.detached(priority: .userInitiated) {
            await FontLoader.shared.preload(paths: paths + [fam.filePath])
            switch FontLoader.shared.cached(fam.filePath) {
            case .success(let l)?:
                return FamilyDetail(family: name, styles: styles, axes: l.axes, xHeight: l.xHeightRatio, canLoad: true)
            default:
                return FamilyDetail(family: name, styles: styles, axes: [], xHeight: nil, canLoad: false)
            }
        }.value
    }
}

func ms(_ a: DispatchTime, _ b: DispatchTime) -> Double {
    Double(b.uptimeNanoseconds - a.uptimeNanoseconds) / 1_000_000
}
