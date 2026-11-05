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
    var noBrand = false          // start with no brand selected (to see the "Name this brand" sheet)
    var demoChoose: String?      // with --no-brand: act as if "Use for Display" was pressed on this family
    var template: String?        // Reading template id: article | hero | appui | poster
    var openPlayground = false   // open every playground group
    var showHidden = false       // finder: include hidden families
    var savedOnly = false        // finder: only Saved
    var sources: String?         // finder: comma list of yours,google,system
    var sort: String?            // Reading sort: less-common
    var demoSave: String?        // comma list of families to star (on the DB copy), for screenshots
    var search: String?          // start with this in the search box
    var bgRefresh = false        // debug: run the background rescan in screenshot mode too (FD_BG_REFRESH=1)

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
        noBrand = arguments.contains("--no-brand")
        demoChoose = value("--demo-choose")
        if demoChoose != nil { noBrand = true }       // the sheet only shows when there is no brand
        template = value("--template")
        openPlayground = arguments.contains("--open-playground")
        showHidden = arguments.contains("--show-hidden")
        savedOnly = arguments.contains("--saved")
        sources = value("--sources")
        sort = value("--sort")
        demoSave = value("--demo-save")
        search = value("--search")
        bgRefresh = arguments.contains("--bg-refresh") || environment["FD_BG_REFRESH"] != nil
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
    var search = "" { didSet { if search != oldValue { scheduleFinder() } } }
    var showInspector = true

    // Library (read once, then filtered in memory)
    private(set) var families: [FamilySummary] = []          // user-installed first, then by name
    private(set) var familyByName: [String: FamilySummary] = [:]
    private(set) var fontsByFamily: [String: [FontFile]] = [:]
    private(set) var fontCount = 0

    /// Bumps while fonts load in the background. Views take it as a plain value so they redraw.
    private(set) var fontTick = 0
    private(set) var fontsReady = false
    /// True while the background rescan runs (and until it has swapped in its answer).
    private(set) var rescanning = false
    /// True once the background rescan has finished, with or without an error. Screenshot runs wait on it.
    private(set) var rescanDone = false
    private(set) var timings: [(label: String, ms: Double)] = []

    // Brands and the designer's choices
    private(set) var brands: [Brand] = []
    private(set) var brandID: Int64?
    private(set) var choices: [String: String] = [:]         // job -> family
    private(set) var shortlists: [String: [String]] = [:]    // job -> families

    // Display (and UI, Mono) grid
    var selectedFamily: String?

    /// Source, kind and trait chips, Saved and Show hidden. Remembered between launches.
    var filter: FinderFilter {
        didSet { if filter != oldValue { persistFilter(); scheduleFinder() } }
    }
    /// The core's answer to the current filter and search: families plus chip counts.
    private(set) var finderResults: FamilyResults?
    /// Every family with its Saved, Hidden and Google flags (hidden ones included), by name.
    private(set) var allEntries: [String: FamilyEntry] = [:]
    private var finderGeneration = 0
    private var finderTask: Task<Void, Never>?

    // Reading
    var lenses = Lenses()
    private(set) var candidates: [Candidate] = []
    private(set) var candidatesLoading = false
    private(set) var candidatesError: String?
    var selectedCandidate: String?
    private var candidatesKey: String?
    /// Whether the Reading list holds an answer for the current controls. For tests.
    var candidatesKey_forTests: String? { candidatesKey }
    /// Bumps whenever a candidate load starts or is thrown away. A load that finds it changed has been superseded
    /// and must not touch the list or the loading flag.
    private var candidateGeneration = 0
    /// How many candidate loads have started. Tests use it to see that a rescan reloads the list.
    private(set) var candidateLoadsStarted = 0
    /// Bumps when the background rescan swaps in a new library. Views that preload fonts take it in their task id.
    private(set) var libraryRevision = 0
    /// The stage shows the shortlisted faces side by side. Only counts while two or more are shortlisted.
    var compareMode = false
    /// How far the stage board is zoomed from Fit.
    var stageZoom = StageZoom()
    /// The designer opened or closed the inspector themselves, so the window size stops deciding.
    var inspectorTouched = false
    /// The window's width, for the inspector rule below.
    var windowWidth: CGFloat = 0
    private var inspectorAutoClosed = false

    /// Reading needs room for its list and stage. When the window is too narrow for the inspector as well, the
    /// inspector starts closed on Reading and comes back when you leave. Once the designer toggles it, their choice stands.
    func applyInspectorRule() {
        guard !inspectorTouched, windowWidth > 0 else { return }
        if screen == .reading {
            if !ReadingLayout.inspectorFits(windowWidth: windowWidth), showInspector { showInspector = false; inspectorAutoClosed = true }
            else if ReadingLayout.inspectorFits(windowWidth: windowWidth), inspectorAutoClosed { showInspector = true; inspectorAutoClosed = false }
        } else if inspectorAutoClosed {
            showInspector = true; inspectorAutoClosed = false
        }
    }

    /// How many candidates Reading asked the core for. "Show more" adds a page.
    static let candidatePage = 40
    private(set) var candidateLimit = AppModel.candidatePage
    private(set) var candidatesHasMore = false
    /// Off by default: Reading only offers faces made for long text. "Show them" turns the rule off.
    private(set) var includeUnfitFaces = false
    /// Families the long-text rule removes for the current Display face ("42 not made for long text").
    private(set) var notForLongText = 0

    func setIncludeUnfit(_ on: Bool) async {
        includeUnfitFaces = on
        candidateLimit = Self.candidatePage
        await loadCandidates()
    }

    /// Which presentation template Reading draws (Templates/Registry.swift).
    var templateID: String = UserDefaults.standard.string(forKey: "readingTemplate") ?? "article" {
        didSet { UserDefaults.standard.set(templateID, forKey: "readingTemplate") }
    }

    /// Playground settings per brand + job + family.
    let typeSettings: TypeSettingsStore
    /// Template colors per brand, the variant showing per template, recent colors.
    let brandStyle: BrandStyleStore

    /// An action that needs a brand and has none yet. The "Name this brand" sheet shows while this is set.
    enum PendingAction: Equatable {
        case choose(job: String, family: String)
        case shortlist(job: String, family: String, on: Bool)
    }
    var pending: PendingAction?

    /// What "Undo" restores for each job: the face chosen before the last choice (nil = nothing).
    private(set) var undoChoice: [String: String?] = [:]
    /// Bumps on every choice. The inspector watches it to play the success animation.
    private(set) var choicePulse = 0

    var errorMessage: String?

    init(options: LaunchOptions) {
        self.options = options
        typeSettings = TypeSettingsStore(dbPath: options.dbPath, persist: options.screenshot == nil && !options.bench)
        brandStyle = BrandStyleStore(dbPath: options.dbPath, persist: options.screenshot == nil && !options.bench)
        if let t = options.template { templateID = t }
        // Screenshot and bench runs start from the standard filter so they repeat.
        var f = options.screenshot == nil && !options.bench ? FinderFilter.load() : FinderFilter.standard
        if let list = options.sources { f.sources = Set(list.split(separator: ",").compactMap { Source(key: String($0)) }) }
        if options.showHidden { f.showHidden = true }
        if options.savedOnly { f.savedOnly = true }
        filter = f
        if options.sort == "less-common" { lenses.sort = .lessCommon }
        if let q = options.search { search = q }
    }

    // MARK: derived

    var brand: Brand? { brands.first { $0.id == brandID } }
    /// The text the Display cards draw. "Aa Bb" until there is a brand.
    var sampleText: String { brand?.name ?? "Aa Bb" }
    var displayFamily: FamilySummary? { choices["display"].flatMap { familyByName[$0] } }
    var readingFamily: FamilySummary? { choices["reading"].flatMap { familyByName[$0] } }

    func chosen(_ screen: Screen) -> String? { screen.job.flatMap { choices[$0] } }

    // Playground settings, keyed brand + job + family.
    func settingsKey(_ job: String, _ family: String) -> String {
        TypeSettingsStore.key(brand: brandID, job: job, family: family)
    }
    /// A face with the designer's playground settings for this job, ready for `FaceText`.
    func face(_ job: String, _ family: FamilySummary) -> FaceSpec {
        FaceSpec(path: family.filePath, settings: typeSettings.settings(settingsKey(job, family.name), job: job),
                 siblings: (fontsByFamily[family.name] ?? []).map(\.filePath),
                 weights: Dictionary((fontsByFamily[family.name] ?? []).map { ($0.filePath, Int($0.weight)) }, uniquingKeysWith: { a, _ in a }))
    }
    var displayFace: FaceSpec? { displayFamily.map { face("display", $0) } }

    func shortlist(_ job: String) -> [String] { shortlists[job] ?? [] }

    /// Families for the grid: the core's answer to the filter chips and the search box.
    /// Your fonts come first. Falls back to everything until the first answer arrives.
    var visibleFamilies: [FamilySummary] {
        guard let results = finderResults else { return families }
        return results.families.compactMap { familyByName[$0.name] }
    }

    var savedCount: Int { allEntries.values.filter(\.saved).count }
    func isSaved(_ name: String) -> Bool { allEntries[name]?.saved ?? false }
    func isHidden(_ name: String) -> Bool { allEntries[name]?.hidden ?? false }

    var readingResult: (shown: [Candidate], hidden: Int) {
        LensEngine.apply(candidates, lenses: effectiveLenses, search: search)
    }

    /// The lenses Reading really applies. With no Display face there is nothing to pair against, so the
    /// Difference, Structure and Foundry questions are off and the list sorts by name or by how common a face is.
    var effectiveLenses: Lenses {
        guard displayFamily == nil else { return lenses }
        var l = lenses
        l.contrast = .any; l.structure = .any; l.foundry = .any
        if !ReadingSort.withoutDisplay.contains(l.sort) { l.sort = .name }
        return l
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

            installLibrary(fams, fonts)
            self.brands = brands
            timings.append(("open (migrate)", ms(t0, t1)))
            if options.refresh { timings.append(("refresh_library", ms(t1, t2))) }
            timings.append(("list_families + list_fonts + brands (\(fams.count) families)", ms(t2, t3)))

            await reloadEntries()
            await refreshFinder()
            if let names = options.demoSave {
                for n in names.split(separator: ",") { await setFavorite(String(n), on: true) }
            }
            let saved = UserDefaults.standard.object(forKey: "lastBrand") as? Int64
            let wanted = options.brand.flatMap { n in brands.first { $0.name == n }?.id }
            await selectBrand(options.noBrand ? nil : (wanted ?? brands.first { $0.id == saved }?.id ?? brands.first?.id))
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
        if !options.refresh && !options.bench && (options.screenshot == nil || options.bgRefresh), let lib = core {
            await refreshInBackground(lib)
        }
    }

    /// Swaps in a library read from the core: families (user fonts first), the lookup by name and each family's files.
    func installLibrary(_ fams: [FamilySummary], _ fonts: [FontFile]) {
        let home = NSHomeDirectory()
        families = fams.sorted {
            let a = Self.tier($0.filePath, home: home), b = Self.tier($1.filePath, home: home)
            return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        familyByName = Dictionary(fams.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        fontsByFamily = Dictionary(grouping: fonts, by: \.family)
        fontCount = fonts.count
    }

    private func refreshInBackground(_ lib: Library) async {
        rescanning = true
        defer { rescanning = false; rescanDone = true }
        do {
            _ = try await Task.detached(priority: .utility) { try lib.refreshLibrary() }.value
            let (fams, fonts) = try await Task.detached(priority: .userInitiated) {
                (try lib.listFamilies(), try lib.listFonts())
            }.value
            await applyRescan(fams, fonts)
        } catch {
            // A failed rescan keeps the library as it was; nothing to show the user yet.
            print("FONTDROP background refresh failed: \(error)")
        }
    }

    /// What follows a finished rescan. Everything the old library fed (the finder, loaded fonts, the Reading list) is
    /// rebuilt from the new one. Choices, shortlists and the selection are keyed by family name, so they carry over.
    func applyRescan(_ fams: [FamilySummary], _ fonts: [FontFile]) async {
        installLibrary(fams, fonts)
        await reloadEntries()
        await refreshFinder()
        // A font that failed to load while the rescan was writing gets another try.
        FontLoader.shared.forgetFailures()
        await FontLoader.shared.preload(paths: fams.map(\.filePath)) { [weak self] n in
            Task { @MainActor in self?.fontTick = n }
        }
        // The chosen faces may use style files the old library did not list.
        await preloadStyles(of: [choices["display"], choices["reading"]].compactMap { $0 })
        libraryRevision += 1
        // Candidates were ranked against the old library. Drop them and rank again.
        candidatesKey = nil
        if screen == .reading { await loadCandidates() }
        fontTick += 1
    }

    /// 0 user-installed, 1 /Library, 2 other, 3 system.
    nonisolated static func tier(_ path: String, home: String) -> Int {
        if path.hasPrefix(home + "/Library/Fonts") { return 0 }
        if path.hasPrefix("/Library/Fonts") { return 1 }
        if path.hasPrefix("/System") { return 3 }
        return 2
    }

    // MARK: finding fonts

    private func persistFilter() {
        if options.screenshot == nil && !options.bench { filter.save() }
    }

    /// Asks the core again, soon. Typing in the search box calls this on every key; only the last answer is used.
    private func scheduleFinder() {
        finderTask?.cancel()
        finderTask = Task { await refreshFinder() }
    }

    /// Waits for the answer to the latest filter or search change (tests, screenshots).
    func finderSettled() async { await finderTask?.value }

    func refreshFinder() async {
        guard core != nil else { return }
        finderGeneration += 1
        let generation = finderGeneration
        let query = filter.query(text: search.trimmingCharacters(in: .whitespaces))
        do {
            let results = try await background { try $0.findFamilies(query: query) }
            if generation == finderGeneration { finderResults = results }
        } catch { report(error) }
    }

    /// Re-reads every family's flags (Saved, Hidden, Google rank). Cheap; run after any change to them.
    func reloadEntries() async {
        let everything = FamilyQuery(text: "", sources: [], kinds: [], traits: [], savedOnly: false, includeHidden: true)
        do {
            let all = try await background { try $0.findFamilies(query: everything) }
            allEntries = Dictionary(all.families.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        } catch { report(error) }
    }

    func setFavorite(_ family: String, on: Bool) async {
        do {
            try await background { try $0.setFavorite(family: family, on: on) }
            await reloadEntries()
            await refreshFinder()
        } catch { report(error) }
    }

    /// Hides or shows a family everywhere: the grid, Reading candidates and pairing.
    func setHidden(_ family: String, hidden: Bool) async {
        do {
            try await background { hidden ? try $0.hideFamily(family: family) : try $0.unhideFamily(family: family) }
            await reloadEntries()
            await refreshFinder()
            candidatesKey = nil
            if screen == .reading { await loadCandidates() }
        } catch { report(error) }
    }

    // MARK: brands

    func selectBrand(_ id: Int64?) async {
        brandID = id
        if let id { UserDefaults.standard.set(id, forKey: "lastBrand") }
        resetCandidates(); candidateLimit = Self.candidatePage
        undoChoice = [:]
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

    /// Creates a brand, selects it, then runs whatever was waiting for one. Returns the new brand's id.
    @discardableResult
    func createBrand(_ name: String) async -> Int64? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        do {
            let b = try await background { try $0.brandCreate(name: n) }
            brands = try await background { try $0.brandsList() }
            await selectBrand(b.id)
            return b.id
        } catch { report(error); return nil }
    }

    /// The "Name this brand" sheet's Create button: make the brand, then apply the choice that asked for it.
    func createBrandAndApplyPending(_ name: String) async {
        let action = pending
        guard await createBrand(name) != nil else { return }
        pending = nil
        switch action {
        case .choose(let job, let family)?: await choose(job, family: family)
        case .shortlist(let job, let family, let on)?: await setShortlist(job, family: family, on: on)
        case nil: break
        }
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

    /// Chooses `family` for `job`. With no brand yet this asks for a name first (the sheet), then comes back here.
    func choose(_ job: String, family: String) async {
        guard let id = brandID else { pending = .choose(job: job, family: family); return }
        do {
            let previous = choices[job]
            try await background { try $0.choose(brand: id, job: job, family: family) }
            if previous != family { undoChoice[job] = .some(previous) }
            choices[job] = family
            choicePulse += 1
            if job == "reading" { typeSettings.adoptSuggestion(settingsKey("reading", family), job: "reading") }
            if job == "display" { resetCandidates() }
        } catch { report(error) }
    }

    /// Takes the face off a job ("Clear Display face"). Undo puts it back. The brand's other choices stay.
    func clear(_ job: String) async {
        guard let id = brandID, let current = choices[job] else { return }
        do {
            try await background { try $0.choiceClear(brand: id, job: job) }
            choices[job] = nil
            undoChoice[job] = .some(current)
            if job == "display" { resetCandidates() }
            if job == "reading" { compareMode = false }
        } catch { report(error) }
    }

    func canClear(_ job: String) -> Bool { brandID != nil && choices[job] != nil }

    /// Throws away the Reading list and any load in flight, so nothing stale lands and no spinner sticks.
    private func resetCandidates() {
        candidates = []; candidatesKey = nil; selectedCandidate = nil
        candidateGeneration += 1
        candidatesLoading = false
    }

    /// Puts back the face chosen before, or clears the job when there was none.
    func undo(_ job: String) async {
        guard let id = brandID, let record = undoChoice[job] else { return }
        undoChoice[job] = nil
        do {
            if let previous = record {
                try await background { try $0.choose(brand: id, job: job, family: previous) }
                choices[job] = previous
            } else {
                try await background { try $0.choiceClear(brand: id, job: job) }
                choices[job] = nil
            }
            if job == "display" { resetCandidates() }
        } catch { report(error) }
    }

    func canUndo(_ job: String) -> Bool { undoChoice[job] != nil }

    func setShortlist(_ job: String, family: String, on: Bool) async {
        guard let id = brandID else { pending = .shortlist(job: job, family: family, on: on); return }
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
        guard let display = displayFamily else { await loadStandaloneCandidates(); return }
        let key = "\(brandID ?? 0)/\(display.fontId)/\(candidateLimit)/\(includeUnfitFaces)/\(sourcesKey)"
        if key == candidatesKey { return }
        candidateGeneration += 1; candidateLoadsStarted += 1
        let generation = candidateGeneration
        candidatesLoading = true
        candidatesError = nil
        // The loading flag always comes down, unless a newer load or a reset owns it now.
        defer { if generation == candidateGeneration { candidatesLoading = false } }
        let keepFamily = candidate(selectedCandidate)?.family
        let id = display.fontId, limit = UInt32(candidateLimit)
        let job: String? = includeUnfitFaces ? nil : "reading"
        // Reading browses the same sources as the Display filter; the long-text count follows it too.
        let outside = idsOutsideSources(keeping: display.name)
        do {
            let ranked = try await background {
                try $0.fontCandidates(fontId: id, excludedIds: outside, job: job, limit: limit)
            }
            let unfit = try await background { try $0.readingHiddenCount(fontId: id, excludedIds: outside) }
            var seen = Set<String>()
            var list: [Candidate] = []
            for p in ranked where !p.family.isEmpty && seen.insert(p.family).inserted {
                // Show the family's regular upright face, not whichever file the engine matched.
                let path = familyByName[p.family]?.filePath ?? p.filePath
                list.append(Candidate(id: p.fontId, family: p.family, filePath: path,
                                      pairType: p.pairType, evidence: p.evidence, order: list.count,
                                      googleRank: allEntries[p.family]?.googleRank.map(Int.init),
                                      bodyStyle: p.suggestedBodyStyle))
            }
            let allPaths = list.flatMap { c in (fontsByFamily[c.family] ?? []).map(\.filePath) + [c.filePath] }
            await FontLoader.shared.preload(paths: allPaths)
            guard generation == candidateGeneration else { return }   // superseded while loading
            candidates = list
            // A Same family card starts its body in the engine's suggested style, in the playground too.
            typeSettings.setSuggestedStyles(Dictionary(
                list.compactMap { c in c.bodyStyle.map { (settingsKey("reading", c.family), $0.filePath) } },
                uniquingKeysWith: { a, _ in a }))
            notForLongText = Int(unfit)
            candidatesHasMore = ranked.count >= candidateLimit
            candidatesKey = key
            fontTick += 1
            reselect(list, keeping: keepFamily)
        } catch {
            if generation == candidateGeneration { candidatesError = "\(error)" }
        }
    }

    /// Keeps the selection on the same family when the list is rebuilt (font ids can change when the library is
    /// rescanned; the family name does not). Falls back to the --select flag, then the first row.
    private func reselect(_ list: [Candidate], keeping family: String?) {
        let preferred = options.select.flatMap { s in list.first { $0.family == s }?.id }
        selectedCandidate = CandidateSelection.pick(list.map { ($0.id, $0.family) }, current: selectedCandidate,
                                                    keeping: family, preferred: preferred,
                                                    first: readingResult.shown.first?.id)
    }

    /// Reading as a starting point: no Display face yet, so the list is every family fit for long text
    /// (or every family, after "Show them") in the current source scope. No pairing, so no evidence.
    private func loadStandaloneCandidates() async {
        let key = "\(brandID ?? 0)/none/\(includeUnfitFaces)/\(sourcesKey)"
        if key == candidatesKey { return }
        candidateGeneration += 1; candidateLoadsStarted += 1
        let generation = candidateGeneration
        candidatesLoading = true
        candidatesError = nil
        defer { if generation == candidateGeneration { candidatesLoading = false } }
        let keepFamily = candidate(selectedCandidate)?.family
        let outside = idsOutsideSources(keeping: "")
        let fitOnly = !includeUnfitFaces
        do {
            let found = try await background { try $0.readingFamilies(excludedIds: outside, onlyFit: fitOnly) }
            guard generation == candidateGeneration else { return }   // superseded (a Display face was chosen, or a newer load)
            var list: [Candidate] = []
            for f in found.families {
                guard let family = familyByName[f.family] else { continue }
                list.append(Candidate(id: family.fontId, family: family.name, filePath: family.filePath,
                                      pairType: "", evidence: [], order: list.count,
                                      googleRank: allEntries[family.name]?.googleRank.map(Int.init), bodyStyle: nil))
            }
            candidates = list
            notForLongText = Int(found.notForLongText)
            candidatesHasMore = false
            candidatesKey = key
            fontTick += 1
            reselect(list, keeping: keepFamily)
        } catch {
            if generation == candidateGeneration { candidatesError = "\(error)" }
        }
    }

    /// True while Reading has no answer yet: a load is running, or none has started. Never true once there is an
    /// error or a list, so the screen shows a spinner, an error or rows, and never a blank.
    var readingIsLoading: Bool { candidatesLoading || (candidatesKey == nil && candidatesError == nil) }

    /// The active source chips as one string, so a change reloads the Reading list.
    var sourcesKey: String { Source.all.filter(filter.sources.contains).map(\.key).joined(separator: ",") }

    /// Font ids of every family outside the active source chips (none selected means all sources).
    /// Passed to the core as exclusions so Reading and its long-text count match the Display filter.
    /// `keeping` is the Display family, which stays whatever its source.
    private func idsOutsideSources(keeping display: String) -> [String] {
        guard !filter.sources.isEmpty else { return [] }
        return fontsByFamily.flatMap { name, files -> [String] in
            guard name != display, let entry = allEntries[name], !entry.sources.contains(where: filter.sources.contains) else { return [] }
            return files.map(\.fontId)
        }
    }

    /// Asks the core for another page of candidates. The list keeps its order; the new ones arrive at the end.
    func showMoreCandidates() async {
        candidateLimit += Self.candidatePage
        await loadCandidates()
    }

    func candidate(_ id: String?) -> Candidate? {
        candidates.first { $0.id == id } ?? (currentReadingCandidate.flatMap { $0.id == id ? $0 : nil })
    }

    /// The chosen Reading face as a candidate: the engine's own entry when it is loaded, else a plain one
    /// without evidence. The list pins it at the top, so it never hides behind a filter or a page.
    var currentReadingCandidate: Candidate? {
        guard let name = choices["reading"], let family = familyByName[name] else { return nil }
        if let hit = candidates.first(where: { $0.family == name }) { return hit }
        return Candidate(id: family.fontId, family: name, filePath: family.filePath, pairType: "", evidence: [], order: -1)
    }

    /// Families side by side in Compare, in order. Empty unless Compare is on and two are shortlisted.
    var comparedFamilies: [String] {
        guard compareMode, Compare.isAvailable(shortlistCount: shortlist("reading").count) else { return [] }
        return Compare.families(shortlist: shortlist("reading"), selected: candidate(selectedCandidate)?.family)
    }

    /// What a template draws for one Reading family next to the Display face. With no Display face yet the
    /// family sets the whole template, headline included, so it is judged on its own.
    func pairContext(reading name: String, fallbackPath: String? = nil) -> PairContext? {
        let body: FaceSpec
        if let family = familyByName[name] { body = face("reading", family) }
        else if let fallbackPath { body = FaceSpec(path: fallbackPath, settings: .defaults(job: "reading")) }
        else { return nil }
        let headline: FaceSpec
        if let display = displayFamily { headline = face("display", display) }
        else if let family = familyByName[name] { headline = face("display", family) }
        else { headline = FaceSpec(path: body.path, settings: .defaults(job: "display")) }
        return PairContext(brand: brand?.name ?? "Brand Name", display: headline, body: body, tick: fontTick)
    }

    /// Loads every style file of these families, so a face set to a non-regular style draws at once.
    func preloadStyles(of names: [String]) async {
        var paths = names.flatMap { n in (fontsByFamily[n] ?? []).map(\.filePath) + [familyByName[n]?.filePath].compactMap { $0 } }
        // A saved playground may point at a style file the library list does not carry (yet).
        for n in names { if let f = familyByName[n] { paths += ["display", "reading"].compactMap { face($0, f).settings.stylePath } } }
        await FontLoader.shared.preload(paths: paths)
        fontTick += 1
    }

    // MARK: inspector detail

    func detail(for name: String) async -> FamilyDetail? {
        guard let fam = familyByName[name] else { return nil }
        let styles = StyleNames.sorted(fontsByFamily[name] ?? [], family: name)
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
