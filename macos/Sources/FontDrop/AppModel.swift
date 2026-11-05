import FontDropCore
import SwiftUI
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
    var screenGiven = false      // --screen was passed: it beats the remembered screen
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
    var sort: String?            // Reading sort: less-common, character-first
    var difference: String?      // Reading Difference lens: close, distinct, strong, any
    var page: Int?               // how many candidates Reading asks the core for (default 40)
    var demoSave: String?        // comma list of families to star (on the DB copy), for screenshots
    var search: String?          // start with this in the search box
    var bgRefresh = false        // debug: run the background rescan in screenshot mode too (FD_BG_REFRESH=1)
    /// Scan these folders instead of the three font folders (--scan-folders a,b or FD_SCAN_FOLDERS). Tests scan a fixture.
    var scanFolders: [String]?

    /// True when the process is an XCTest host (the test bundle runs inside the app).
    static func isTestHost(_ environment: [String: String]) -> Bool { environment["XCTestConfigurationFilePath"] != nil }

    init(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let explicitDB = value("--db") ?? environment["FONTDROP_DB"]
        // A test host never opens the live library: with no DB named, it gets a throwaway one and the bench rules.
        let hostWithoutDB = Self.isTestHost(environment) && explicitDB == nil
        dbPath = explicitDB
            ?? (hostWithoutDB ? NSTemporaryDirectory() + "fontdrop-testhost-\(ProcessInfo.processInfo.processIdentifier).db" : nil)
            ?? NSHomeDirectory() + "/Library/Application Support/co.dynolabs.fontdrop/fontdrop.db"
        bench = arguments.contains("--bench") || Self.isTestHost(environment)   // a test host never rescans, saves preferences or opens the live DB
        if let folders = value("--scan-folders") ?? environment["FD_SCAN_FOLDERS"] {
            scanFolders = folders.split(separator: ",").map(String.init)
        }
        refresh = arguments.contains("--refresh")
        screenshot = value("--screenshot")
        if let s = value("--screen"), let sc = Screen(rawValue: s) { screen = sc; screenGiven = true }
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
        difference = value("--difference")
        page = value("--page").flatMap(Int.init)
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
        case .reading: "Text"
        case .ui: "UI"
        case .mono: "Mono"
        case .set: "Set"
        case .colors: "Colors"
        }
    }

    /// The rows the sidebar shows, in order. UI and Mono stay in the code, off the screen (ship plan R1).
    /// Saved is a filter on Display, and Colors lives in the Text stage's Colors button.
    static let sidebar: [Screen] = [.display, .reading, .set]

    /// The key that opens this screen with command: 1 Display, 2 Text, 3 Set.
    var shortcutKey: KeyEquivalent? {
        switch self {
        case .display: "1"
        case .reading: "2"
        case .set: "3"
        case .ui, .mono, .colors: nil
        }
    }

    var symbol: String {
        switch self {
        case .display: "textformat.size"
        case .reading: "text.alignleft"
        case .ui: "rectangle.on.rectangle"
        case .mono: "chevron.left.forwardslash.chevron.right"
        case .set: "square.stack"
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
    var screen: Screen = .display { didSet { if screen != oldValue { rememberBrandState() } } }
    var search = "" { didSet { if search != oldValue { scheduleFinder() } } }
    var showInspector = true
    var showSidebar = true

    // Library (read once, then filtered in memory)
    private(set) var families: [FamilySummary] = []          // user-installed first, then by name
    private(set) var familyByName: [String: FamilySummary] = [:]
    private(set) var fontsByFamily: [String: [FontFile]] = [:]
    private(set) var fontCount = 0

    /// Bumps while fonts load in the background. Views take it as a plain value so they redraw.
    private(set) var fontTick = 0
    private(set) var fontsReady = false
    /// Where the background rescan stands. The sidebar footer shows it; an empty library shows "Scanning your fonts".
    enum ScanState: Equatable { case idle, running, failed(String) }
    private(set) var scanState: ScanState = .idle
    /// True while the background rescan runs (and until it has swapped in its answer).
    var rescanning: Bool { scanState == .running }
    /// The library has no fonts yet and a scan is working on it: show "Scanning your fonts", not an empty state.
    var scanningEmptyLibrary: Bool { families.isEmpty && scanState == .running }
    /// `bootstrap` ran. A second window (or a repeated task) must not open the library and rescan again.
    private var didBootstrap = false
    /// Where small preferences live: the standard defaults for a real run, a throwaway suite for tests and screenshots.
    let defaults: UserDefaults
    /// True once the background rescan has finished, with or without an error. Screenshot runs wait on it.
    private(set) var rescanDone = false
    private(set) var timings: [(label: String, ms: Double)] = []

    // Brands and the designer's choices
    private(set) var brands: [Brand] = []
    private(set) var brandID: Int64?
    private(set) var choices: [String: String] = [:]         // job -> family
    private(set) var shortlists: [String: [String]] = [:]    // job -> families

    // Display (and UI, Mono) grid
    var selectedFamily: String? { didSet { if selectedFamily != oldValue { rememberBrandState() } } }

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
    var selectedCandidate: String? { didSet { if selectedCandidate != oldValue { rememberBrandState() } } }
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
    /// The large preview of a face (Space), or nil.
    var preview: FacePreviewState?
    /// Each bump asks the search box (command-F) or the list (Escape in the search box) to take the keyboard.
    var focusSearchTick = 0
    var focusListTick = 0
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

    /// Which presentation template Reading draws (`TemplateDescriptor.all` in Templates/Template.swift).
    var templateID: String = "article" {
        didSet { defaults.set(templateID, forKey: "readingTemplate"); if templateID != oldValue { rememberBrandState() } }
    }

    // MARK: per-brand memory (launch)

    /// True while a brand is being switched to or restored: the changes it makes are not the designer's.
    private var restoringBrand = false
    /// The family to put the Text selection back on once the candidate list arrives.
    private var restoreCandidateFamily: String?

    /// Saves where this brand stands: screen, Display selection, Text selection, template.
    private func rememberBrandState() {
        guard !restoringBrand, phase == .ready, let id = brandID else { return }
        var memory = LaunchMemory.load(defaults, brand: id) ?? BrandMemory()
        memory.screen = screen.rawValue
        if let f = selectedFamily { memory.display = f }
        if let c = candidate(selectedCandidate)?.family { memory.candidate = c }
        memory.template = templateID
        LaunchMemory.save(memory, defaults, brand: id)
    }

    /// Puts this brand's last screen, selections and template back. A brand with nothing stored opens on Display.
    private func restoreBrandState(_ id: Int64) {
        let memory = LaunchMemory.load(defaults, brand: id)
        screen = LaunchMemory.landingScreen(stored: memory?.screen.flatMap(Screen.init(rawValue:)),
                                            hasDisplay: choices["display"] != nil, hasText: choices["reading"] != nil)
        if let t = memory?.template, Templates.all.contains(where: { $0.id == t }) { templateID = t }
        selectedFamily = memory?.display ?? choices["display"]
        restoreCandidateFamily = memory?.candidate
    }

    // MARK: first run and empty library

    /// How far the scan has got, polled from the core while it runs.
    private(set) var scanProgressNow = (fraction: 0.0, files: 0, families: 0)
    /// "Start with Display" or "Start with Text" was pressed: the scan screen is done for this launch.
    private(set) var scanScreenDismissed = false

    /// First run: no brands and no fonts read yet, while the library scans. The content area shows the scan screen.
    var showsScanScreen: Bool {
        phase == .ready && brands.isEmpty && families.isEmpty && scanState == .running && !scanScreenDismissed
    }

    /// The scan finished and found no fonts at all. A screenshot or bench run never scans, so for those the library as
    /// opened is the final answer.
    var libraryIsEmpty: Bool {
        phase == .ready && families.isEmpty && scanState == .idle && (rescanDone || options.bench || options.screenshot != nil)
    }

    /// No inspector on first run or with no fonts: there is nothing to inspect.
    var hidesInspector: Bool { showsScanScreen || libraryIsEmpty }

    func startWith(_ screen: Screen) {
        scanScreenDismissed = true
        self.screen = screen
    }

    /// The brand chose this face for the job, and the library no longer has it.
    func isMissing(_ screen: Screen) -> Bool {
        guard phase == .ready, !families.isEmpty, let name = chosen(screen) else { return false }
        return familyByName[name] == nil
    }

    /// Playground settings per brand + job + family.
    let typeSettings: TypeSettingsStore
    /// The brand's type scale (body size, ratio, locked or not), shared by the Display and Reading faces.
    let scaleStore: ScaleStore
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
    /// One face choice or clear, for the Edit menu's Undo and Redo (command-Z, shift-command-Z). `before` and `after`
    /// are family names, nil meaning no face.
    struct ChoiceStep: Equatable { let job: String; let before: String?; let after: String? }
    private(set) var choiceHistory: [ChoiceStep] = []
    private(set) var choiceRedo: [ChoiceStep] = []
    /// Bumps on every choice. The inspector watches it to play the success animation.
    private(set) var choicePulse = 0

    var errorMessage: String?
    /// A short line in the Set bar after an export ("CSS copied"). Clears itself.
    var exportNotice: String?
    var exportNoticeTask: Task<Void, Never>?

    /// A suite shared by every throwaway run, emptied each time it is opened, so a test or screenshot run never
    /// reads or writes the real app's preferences (last brand, remembered template, filters, variants).
    static func throwawayDefaults() -> UserDefaults {
        let name = "co.dynolabs.fontdrop.throwaway"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }

    /// `defaults` is for tests that want their own suite. Left out, a bench or screenshot run gets a throwaway one.
    init(options: LaunchOptions, defaults: UserDefaults? = nil) {
        self.options = options
        let isolated = options.screenshot != nil || options.bench
        let store = defaults ?? (isolated ? Self.throwawayDefaults() : .standard)
        self.defaults = store
        typeSettings = TypeSettingsStore(persist: !isolated)
        scaleStore = ScaleStore(persist: !isolated)
        brandStyle = BrandStyleStore(persist: !isolated, defaults: store)
        templateID = store.string(forKey: "readingTemplate") ?? "article"
        if let t = options.template { templateID = t }
        // Screenshot and bench runs start from the standard filter so they repeat.
        var f = isolated ? FinderFilter.standard : FinderFilter.load(from: store)
        if let list = options.sources { f.sources = Set(list.split(separator: ",").compactMap { Source(key: String($0)) }) }
        if options.showHidden { f.showHidden = true }
        if options.savedOnly { f.savedOnly = true }
        filter = f
        sampleOverrides = store.dictionary(forKey: "displaySamples") as? [String: String] ?? [:]
        if options.sort == "less-common" { lenses.sort = .lessCommon }
        if options.sort == "character-first" { lenses.sort = .characterFirst }
        if let d = options.difference, let l = ContrastLens.allCases.first(where: { $0.rawValue.lowercased() == d }) { lenses.contrast = l }
        if let q = options.search { search = q }
        // A setting changed in the last moment before quitting is still waiting for its save.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushBrandSettings() }
        }
    }

    // MARK: derived

    var brand: Brand? { brands.first { $0.id == brandID } }
    /// The text the Display cards draw: the line the designer typed in the inspector's Sample module, else the brand name.
    /// "Aa Bb" until there is a brand.
    var sampleText: String { customSample ?? brand?.name ?? "Aa Bb" }

    /// The line typed for the current brand, per brand and kept between launches. Nil: use the brand name.
    var customSample: String? { brandID.flatMap { sampleOverrides[String($0)] } }
    private(set) var sampleOverrides: [String: String] = [:]

    /// Sets the Display sample line for this brand. An empty line puts the brand name back.
    func setSample(_ text: String) {
        guard let id = brandID else { return }
        let line = text.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { sampleOverrides[String(id)] = nil } else { sampleOverrides[String(id)] = text }
        defaults.set(sampleOverrides, forKey: "displaySamples")
    }
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

    // MARK: Either way in (Display ranked against the Text face)

    /// How the Display grid is ordered. `.library` is the finder's order (your fonts first). `.pairsWith` ranks every
    /// family as a headline for the chosen Text face, with the same pairing engine run the other way.
    enum DisplaySort: String, Equatable { case library, pairsWith }

    /// One family's place in the Display list for the chosen Text face.
    struct DisplayPair: Equatable {
        let rank: Int
        let pairType: String
    }

    /// What the designer picked in the Sort menu. Nil: automatic, see `displaySort`.
    var displaySortChoice: DisplaySort?
    private(set) var displayPairs: [String: DisplayPair] = [:]
    /// Each ranked family's card line (see `DisplayReasons`), for the Text face the ranks are for.
    private(set) var displayLines: [String: String] = [:]
    private var displayPairsKey: String?
    private var displayPairsGeneration = 0

    /// The sort the Display grid really uses. With no Text face there is nothing to pair against, so the library order.
    /// With a Text face and no Display face yet, Pairs with is the default (the Text face came first). Once a Display
    /// face is chosen the grid keeps the library order unless the designer asks for Pairs with.
    var displaySort: DisplaySort {
        guard readingFamily != nil else { return .library }
        return displaySortChoice ?? (displayFamily == nil ? .pairsWith : .library)
    }

    /// The Display grid's families in order. Families the engine gave no rank (the Text face's own family) follow the ranked ones.
    var displayGridFamilies: [FamilySummary] {
        let base = visibleFamilies
        guard displaySort == .pairsWith, displayPairsAreCurrent, !displayPairs.isEmpty else { return base }
        return base.enumerated()
            .sorted { (displayPairs[$0.element.name]?.rank ?? Int.max, $0.offset) < (displayPairs[$1.element.name]?.rank ?? Int.max, $1.offset) }
            .map(\.element)
    }

    /// The one line under a Display card's name while Pairs with is on: the pair's kind, in the Text face's name.
    func displayReason(for family: String) -> String? {
        guard displaySort == .pairsWith, displayPairsAreCurrent else { return nil }
        return displayLines[family]
    }

    /// The ranks held are for the Text face chosen now (not a face chosen a moment ago).
    var displayPairsAreCurrent: Bool { readingFamily.map { displayPairsKey == displayKey($0) } ?? false }

    private func displayKey(_ text: FamilySummary) -> String { "\(brandID ?? 0)/\(text.fontId)/\(libraryRevision)" }

    /// True while Pairs with is the sort and its ranks are not here yet.
    var displayPairsLoading: Bool { displaySort == .pairsWith && !displayPairsAreCurrent }

    /// Asks the core for every family's rank as a Display partner of the chosen Text face. The Text-only rules do not
    /// apply, so every family is ranked. The grid shows the result only while Pairs with is the sort.
    func loadDisplayPairs() async {
        guard let text = readingFamily else {
            displayPairs = [:]; displayLines = [:]; displayPairsKey = nil; displayPairsGeneration += 1
            return
        }
        let key = displayKey(text)
        if key == displayPairsKey { return }
        displayPairsGeneration += 1
        let generation = displayPairsGeneration
        let id = text.fontId
        do {
            let ranked = try await background { try $0.displayCandidates(fontId: id, excludedIds: [], excludedFamilies: [], limit: 100_000) }
            guard generation == displayPairsGeneration else { return }       // the Text face changed while this ran
            var map: [String: DisplayPair] = [:]
            var entries: [DisplayReasons.Entry] = []
            for (i, p) in ranked.enumerated() where !p.family.isEmpty && map[p.family] == nil {
                map[p.family] = DisplayPair(rank: i, pairType: p.pairType)
                entries.append(DisplayReasons.Entry(family: p.family, pairType: p.pairType, evidence: p.evidence))
            }
            displayPairs = map
            displayLines = DisplayReasons.lines(entries, text: text.name)
            displayPairsKey = key
        } catch { report(error) }
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
        guard !didBootstrap else { return }      // one open and one rescan, however many windows ask
        didBootstrap = true
        let db = dbPath
        setvbuf(stdout, nil, _IOLBF, 0); print("FONTDROP bootstrap start db=\(db) refresh=\(options.refresh)")
        do {
            let t0 = DispatchTime.now()
            let lib = try await Task.detached(priority: .userInitiated) { try Library.open(path: db) }.value
            core = lib
            // The per-brand stores read the database now (the core imported the old JSON files when it opened),
            // and write to it from here on.
            typeSettings.attach(lib); scaleStore.attach(lib); brandStyle.attach(lib)
            let t1 = DispatchTime.now()
            if options.refresh { print("FONTDROP refreshing library...")
                _ = try await Task.detached(priority: .utility) { try lib.refreshLibrary() }.value
            }
            let t2 = DispatchTime.now()
            let (fams, fonts, brands) = try await Task.detached(priority: .userInitiated) {
                (try lib.listFamilies(), try lib.listFonts(), try lib.brandsList())
            }.value
            let t3 = DispatchTime.now()

            self.brands = brands
            timings.append(("open (migrate)", ms(t0, t1)))
            if options.refresh { timings.append(("refresh_library", ms(t1, t2))) }
            timings.append(("list_families + list_fonts + brands (\(fams.count) families)", ms(t2, t3)))

            await applyLibrary(fams, fonts)
            if let names = options.demoSave {
                for n in names.split(separator: ",") { await setFavorite(String(n), on: true) }
            }
            let saved = defaults.object(forKey: "lastBrand") as? Int64
            let wanted = options.brand.flatMap { n in brands.first { $0.name == n }?.id }
            await selectBrand(options.noBrand ? nil : (wanted ?? brands.first { $0.id == saved }?.id ?? brands.first?.id))
            if options.screenGiven { screen = options.screen }
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
        // A saved style file the library no longer lists (moved, replaced) is remapped or dropped.
        typeSettings.repairStylePaths(files: fontsByFamily.mapValues { $0.map(\.filePath) }, regular: familyByName.mapValues(\.filePath))
    }

    /// The one place a library read from the core is swapped in: the lists, then the finder's flags and answer.
    /// Bootstrap and the background rescan both come through here.
    func applyLibrary(_ fams: [FamilySummary], _ fonts: [FontFile]) async {
        installLibrary(fams, fonts)
        await reloadEntries()
        await refreshFinder()
    }

    private func refreshInBackground(_ lib: Library) async {
        scanState = .running
        defer { rescanDone = true }
        let folders = options.scanFolders
        // The core counts files as it works. Ask it a few times a second while the scan runs.
        let poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let p = FontDropCore.scanProgress()
                self?.scanProgressNow = (p.fraction, Int(p.files), Int(p.families))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poll.cancel() }
        do {
            try await Task.detached(priority: .utility) {
                if let folders { _ = try lib.refreshLibraryFolders(folders: folders) } else { _ = try lib.refreshLibrary() }
            }.value
            let (fams, fonts) = try await Task.detached(priority: .userInitiated) {
                (try lib.listFamilies(), try lib.listFonts())
            }.value
            await applyRescan(fams, fonts)
            scanState = .idle
        } catch {
            // A failed rescan keeps the library as it was. The sidebar says so, with a Retry.
            print("FONTDROP background refresh failed: \(error)")
            scanState = .failed("\(error)")
        }
    }

    /// The sidebar's Retry after a failed rescan.
    func retryScan() async {
        guard let lib = core, scanState != .running else { return }
        await refreshInBackground(lib)
    }

    /// The Reading list was ranked against something that changed. Throw it away and, when Reading is showing, rank again.
    private func reloadReading() async {
        candidatesKey = nil
        if screen == .reading { await loadCandidates() }
    }

    /// What follows a finished rescan. Everything the old library fed (the finder, loaded fonts, the Reading list) is
    /// rebuilt from the new one. Choices, shortlists and the selection are keyed by family name, so they carry over.
    func applyRescan(_ fams: [FamilySummary], _ fonts: [FontFile]) async {
        await applyLibrary(fams, fonts)
        // A font that failed to load while the rescan was writing gets another try.
        FontLoader.shared.forgetFailures()
        await FontLoader.shared.preload(paths: fams.map(\.filePath)) { [weak self] n in
            Task { @MainActor in self?.fontTick = n }
        }
        // The chosen faces may use style files the old library did not list.
        await preloadStyles(of: [choices["display"], choices["reading"]].compactMap { $0 })
        libraryRevision += 1
        // Candidates were ranked against the old library. Drop them and rank again.
        await reloadReading()
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
        if options.screenshot == nil && !options.bench { filter.save(to: defaults) }
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
            await reloadReading()
        } catch { report(error) }
    }

    // MARK: brands

    /// Switches brand. `restore` puts back that brand's last screen, selections and template (the default). A brand
    /// just made for a choice in progress keeps the screen it was made on.
    func selectBrand(_ id: Int64?, restore: Bool = true) async {
        restoringBrand = true
        defer { restoringBrand = false }
        brandID = id
        if let id { defaults.set(id, forKey: "lastBrand") }
        resetCandidates(); candidateLimit = Self.candidatePage
        undoChoice = [:]; choiceHistory = []; choiceRedo = []
        restoreCandidateFamily = nil
        await reloadBrandData()
        if restore, let id { restoreBrandState(id) }
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
            await selectBrand(b.id, restore: false)
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

    /// Deletes a brand and everything saved for it: picks, shortlist, scale, colors, face settings, the sample line
    /// and where it was left. Fonts are not touched. Selects the next brand, or none.
    func deleteBrand(_ brand: Brand) async {
        let id = brand.id
        do {
            try await background { try $0.brandDelete(id: id) }
            typeSettings.forget(brand: id); scaleStore.forget(brand: id); brandStyle.forget(brand: id)
            brands = try await background { try $0.brandsList() }
            if brandID == id {
                restoringBrand = true; selectedFamily = nil; restoringBrand = false     // the old brand's selection is not the next one's
                await selectBrand(brands.first?.id)
            }
            defaults.removeObject(forKey: LaunchMemory.key(id))
            if sampleOverrides.removeValue(forKey: String(id)) != nil { defaults.set(sampleOverrides, forKey: "displaySamples") }
            if defaults.object(forKey: "lastBrand") as? Int64 == id { defaults.removeObject(forKey: "lastBrand") }
        } catch { report(error) }
    }

    /// Writes any per-brand setting still waiting for its save (the app is quitting).
    func flushBrandSettings() {
        typeSettings.flush(); scaleStore.flush(); brandStyle.flush()
    }

    // MARK: choices and shortlist

    /// Chooses `family` for `job`. With no brand yet this asks for a name first (the sheet), then comes back here.
    func choose(_ job: String, family: String) async {
        guard let id = brandID else { pending = .choose(job: job, family: family); return }
        do {
            let previous = choices[job]
            try await background { try $0.choose(brand: id, job: job, family: family) }
            if previous != family {
                undoChoice[job] = .some(previous)
                choiceHistory.append(ChoiceStep(job: job, before: previous, after: family)); choiceRedo = []
            }
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
            choiceHistory.append(ChoiceStep(job: job, before: current, after: nil)); choiceRedo = []
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
            if let i = choiceHistory.lastIndex(where: { $0.job == job }) { choiceRedo.append(choiceHistory.remove(at: i)) }
        } catch { report(error) }
    }

    func canUndo(_ job: String) -> Bool { undoChoice[job] != nil }

    // MARK: undo and redo across both faces (Edit menu)

    var canUndoLast: Bool { brandID != nil && !choiceHistory.isEmpty }
    var canRedoLast: Bool { brandID != nil && !choiceRedo.isEmpty }
    /// What the Edit menu says it will undo: "Undo Display face" and so on. Nil when there is nothing.
    var undoLastLabel: String? { choiceHistory.last.map { Lexicon.Keyboard.undoItem(job: $0.job, cleared: $0.after == nil) } }
    var redoLastLabel: String? { choiceRedo.last.map { Lexicon.Keyboard.redoItem(job: $0.job, cleared: $0.after == nil) } }

    /// Writes one job's face (or no face) without recording history. The caller moves the step between the stacks.
    private func setChoice(_ job: String, to family: String?) async throws {
        guard let id = brandID else { return }
        if let family { try await background { try $0.choose(brand: id, job: job, family: family) } }
        else { try await background { try $0.choiceClear(brand: id, job: job) } }
        choices[job] = family
        if job == "display" { resetCandidates() }
        if job == "reading", family == nil { compareMode = false }
    }

    /// Command-Z: takes back the latest choice or clear, whichever face it was on.
    func undoLast() async {
        guard let step = choiceHistory.last else { return }
        do {
            try await setChoice(step.job, to: step.before)
            choiceHistory.removeLast(); choiceRedo.append(step)
            undoChoice[step.job] = nil
        } catch { report(error) }
    }

    /// Shift-command-Z: does the step again.
    func redoLast() async {
        guard let step = choiceRedo.last else { return }
        do {
            try await setChoice(step.job, to: step.after)
            choiceRedo.removeLast(); choiceHistory.append(step)
            if step.job == "reading", let f = step.after { typeSettings.adoptSuggestion(settingsKey("reading", f), job: "reading") }
            choicePulse += 1
        } catch { report(error) }
    }

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
        let key = "\(brandID ?? 0)/\(display.fontId)/\(candidateLimit)/\(includeUnfitFaces)/\(sourcesKey)/\(lenses.sort == .characterFirst)"
        if key == candidatesKey { return }
        let generation = beginCandidateLoad()
        // The loading flag always comes down, unless a newer load or a reset owns it now.
        defer { if generation == candidateGeneration { candidatesLoading = false } }
        let keepFamily = candidate(selectedCandidate)?.family
        let id = display.fontId, limit = UInt32(candidateLimit)
        let characterFirst = lenses.sort == .characterFirst      // the core flips its two groups, so the page holds the right ones
        let job: String? = includeUnfitFaces ? nil : "reading"
        // Reading browses the same sources as the Display filter; the long-text count follows it too.
        let outside = familiesOutsideSources(keeping: display.name)
        do {
            let ranked = try await background {
                try $0.fontCandidates(fontId: id, excludedIds: [], excludedFamilies: outside, job: job, characterFirst: characterFirst, limit: limit)
            }
            let unfit = try await background { try $0.readingHiddenCount(fontId: id, excludedIds: [], excludedFamilies: outside) }
            var seen = Set<String>()
            var list: [Candidate] = []
            for p in ranked where !p.family.isEmpty && seen.insert(p.family).inserted {
                // Show the family's regular upright face, not whichever file the engine matched.
                let path = familyByName[p.family]?.filePath ?? p.filePath
                list.append(Candidate(id: p.fontId, family: p.family, filePath: path,
                                      pairType: p.pairType, evidence: p.evidence, order: list.count,
                                      googleRank: allEntries[p.family]?.googleRank.map(Int.init),
                                      bodyStyle: p.suggestedBodyStyle, workhorse: p.workhorse))
            }
            let allPaths = list.flatMap { c in (fontsByFamily[c.family] ?? []).map(\.filePath) + [c.filePath] }
            await FontLoader.shared.preload(paths: allPaths)
            guard generation == candidateGeneration else { return }   // superseded while loading
            // A Same family card starts its body in the engine's suggested style, in the playground too.
            typeSettings.setSuggestedStyles(Dictionary(
                list.compactMap { c in c.bodyStyle.map { (settingsKey("reading", c.family), $0.filePath) } },
                uniquingKeysWith: { a, _ in a }))
            commitCandidates(list, key: key, notForLongText: Int(unfit), hasMore: ranked.count >= candidateLimit, keeping: keepFamily)
        } catch {
            if generation == candidateGeneration { candidatesError = "\(error)" }
        }
    }

    /// The start of a candidate load: a new generation, the loading flag up, the old error gone.
    private func beginCandidateLoad() -> Int {
        candidateGeneration += 1; candidateLoadsStarted += 1
        candidatesLoading = true
        candidatesError = nil
        return candidateGeneration
    }

    /// The end of a candidate load that was not superseded: the list, its counts, the cache key and the selection.
    private func commitCandidates(_ list: [Candidate], key: String, notForLongText: Int, hasMore: Bool, keeping family: String?) {
        candidates = list
        self.notForLongText = notForLongText
        candidatesHasMore = hasMore
        candidatesKey = key
        fontTick += 1
        reselect(list, keeping: family)
    }

    /// Keeps the selection on the same family when the list is rebuilt (font ids can change when the library is
    /// rescanned; the family name does not). Falls back to the --select flag, then the first row.
    private func reselect(_ list: [Candidate], keeping family: String?) {
        let preferred = options.select.flatMap { s in list.first { $0.family == s }?.id }
        let keeping = family ?? restoreCandidateFamily.flatMap { r in list.contains { $0.family == r } ? r : nil }
        restoreCandidateFamily = nil
        selectedCandidate = CandidateSelection.pick(list.map { ($0.id, $0.family) }, current: selectedCandidate,
                                                    keeping: keeping, preferred: preferred,
                                                    first: readingResult.shown.first?.id)
    }

    /// Reading as a starting point: no Display face yet, so the list is every family fit for long text
    /// (or every family, after "Show them") in the current source scope. No pairing, so no evidence.
    private func loadStandaloneCandidates() async {
        let key = "\(brandID ?? 0)/none/\(includeUnfitFaces)/\(sourcesKey)"
        if key == candidatesKey { return }
        let generation = beginCandidateLoad()
        defer { if generation == candidateGeneration { candidatesLoading = false } }
        let keepFamily = candidate(selectedCandidate)?.family
        let outside = familiesOutsideSources(keeping: "")
        let fitOnly = !includeUnfitFaces
        do {
            let found = try await background { try $0.readingFamilies(excludedIds: [], excludedFamilies: outside, onlyFit: fitOnly) }
            guard generation == candidateGeneration else { return }   // superseded (a Display face was chosen, or a newer load)
            var list: [Candidate] = []
            for f in found.families {
                guard let family = familyByName[f.family] else { continue }
                list.append(Candidate(id: family.fontId, family: family.name, filePath: family.filePath,
                                      pairType: "", evidence: [], order: list.count,
                                      googleRank: allEntries[family.name]?.googleRank.map(Int.init), bodyStyle: nil))
            }
            commitCandidates(list, key: key, notForLongText: Int(found.notForLongText), hasMore: false, keeping: keepFamily)
        } catch {
            if generation == candidateGeneration { candidatesError = "\(error)" }
        }
    }

    /// True while Reading has no answer yet: a load is running, or none has started. Never true once there is an
    /// error or a list, so the screen shows a spinner, an error or rows, and never a blank.
    var readingIsLoading: Bool { candidatesLoading || (candidatesKey == nil && candidatesError == nil) }

    /// The active source chips as one string, so a change reloads the Reading list.
    var sourcesKey: String { Source.all.filter(filter.sources.contains).map(\.key).joined(separator: ",") }

    /// Names of the families outside the active source chips (none selected means all sources).
    /// Passed to the core as exclusions so Reading and its long-text count match the Display filter.
    /// The core expands a name to every file of the family, so twin .ttf/.otf files cannot leak through.
    /// `keeping` is the Display family, which stays whatever its source.
    func familiesOutsideSources(keeping display: String) -> [String] {
        guard !filter.sources.isEmpty else { return [] }
        return fontsByFamily.keys.filter { name in
            guard name != display, let entry = allEntries[name] else { return false }
            return !entry.sources.contains(where: filter.sources.contains)
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
        return PairContext(brand: brand?.name ?? "Brand Name", display: headline, body: body, tick: fontTick,
                           scale: scaleStore.scale(brand: brandID))
    }

    // MARK: type scale

    /// The brand's scale as it stands.
    var scale: TypeScale { scaleStore.scale(brand: brandID) }

    func updateScale(_ change: (inout TypeScale) -> Void) { scaleStore.update(brand: brandID, change) }

    /// The solved sizes of the template on stage for one Reading family: the main headline and the body text, in points.
    /// Nil when the template has no anchor or the face is not loaded yet.
    func solvedSizes(reading name: String, fallbackPath: String? = nil) -> (headline: Double, body: Double, headlineStep: Int)? {
        guard let ctx = pairContext(reading: name, fallbackPath: fallbackPath) else { return nil }
        let template = Templates.descriptor(templateID)
        guard let anchor = TemplateAnchors.anchor(template: template.id, variant: brandStyle.variant(template)) else { return nil }
        return ctx.solvedSizes(anchor)
    }

    /// Turns the lock on, starting from what Fit gives the template on stage so nothing jumps: the body size Fit
    /// produced, and the standard ratio closest to headline / body over the headline's steps.
    func lockScale(reading name: String, fallbackPath: String? = nil) {
        var unlocked = scale
        unlocked.locked = false
        if var ctx = pairContext(reading: name, fallbackPath: fallbackPath) {
            ctx.scale = unlocked
            let template = Templates.descriptor(templateID)
            if let anchor = TemplateAnchors.anchor(template: template.id, variant: brandStyle.variant(template)) {
                let s = ctx.solvedSizes(anchor)
                if s.body > 0, s.headline > 0, s.headlineStep > 0 {
                    let body = min(max(s.body.rounded(), TypeScale.bodyRange.lowerBound), TypeScale.bodyRange.upperBound)
                    let ratio = TypeScale.nearestRatio(pow(s.headline / body, 1 / Double(s.headlineStep)))
                    updateScale { $0.body = body; $0.ratio = ratio; $0.locked = true }
                    return
                }
            }
        }
        updateScale { $0.locked = true }
    }

    /// The dial turned to a stop. Turning locks the scale; the first turn starts from what Auto gave, so nothing jumps.
    func setRatio(_ ratio: Double, reading name: String, fallbackPath: String? = nil) {
        if !scale.locked { lockScale(reading: name, fallbackPath: fallbackPath) }
        updateScale { $0.ratio = ratio }
    }

    /// Pressing the dial: the sizes go back to Auto. The saved body and ratio stay for the next lock.
    func returnToAuto() { updateScale { $0.locked = false } }

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
