import FontDropCore
import Foundation
import Observation

enum BrowseMode: String, CaseIterable, Identifiable {
    case sidebar = "Sidebar list"
    case grid = "Family grid"
    case flat = "All fonts"
    var id: String { rawValue }
}

extension FamilySummary: @retroactive Identifiable { public var id: String { fontId } }
extension FontFile: @retroactive Identifiable { public var id: String { fontId } }

struct Timing: Sendable { var label: String; var ms: Double }

@MainActor @Observable
final class Store {
    var families: [FamilySummary] = []
    var fonts: [FontFile] = []
    var selection: FamilySummary.ID?
    var mode: BrowseMode = .sidebar
    var loadError: String?
    var timings: [Timing] = []

    var buckets: [PairBucket] = []
    var pairsLoading = false
    var pairsMs: Double?
    var pairsError: String?

    let dbPath: String
    /// Opened on first load. The core migrates the DB to the current schema as it opens.
    private var library: Library?
    var refreshing = false

    init(dbPath: String) { self.dbPath = dbPath }

    /// The shared engine handle (also used by the bench).
    var core: Library? { library }

    var selected: FamilySummary? { families.first { $0.id == selection } }

    /// All DB work runs on a background task; only the results land on the main actor.
    func load() async {
        let db = dbPath
        do {
            let lib: Library
            if let existing = library {
                lib = existing
            } else {
                lib = try await Task.detached(priority: .userInitiated) { try Library.open(path: db) }.value
                library = lib
            }
            let (fams, famMs, fonts, fontMs) = try await Task.detached(priority: .userInitiated) {
                let t0 = DispatchTime.now()
                let fams = try lib.listFamilies()
                let t1 = DispatchTime.now()
                let fonts = try lib.listFonts()
                let t2 = DispatchTime.now()
                return (fams, ms(t0, t1), fonts, ms(t1, t2))
            }.value
            families = fams
            self.fonts = fonts
            timings.append(Timing(label: "list_families (\(fams.count) families)", ms: famMs))
            timings.append(Timing(label: "list_fonts (\(fonts.count) fonts)", ms: fontMs))
            selection = selection ?? fams.first?.id
        } catch {
            loadError = "\(error)"
        }
    }

    /// Scan + classify off the main thread, then re-read the families.
    func refresh() async {
        guard let lib = library, !refreshing else { return }
        refreshing = true
        let t0 = DispatchTime.now()
        let result: Result<UInt32, Error> = await Task.detached(priority: .utility) {
            Result { try lib.refreshLibrary() }
        }.value
        let elapsed = ms(t0, DispatchTime.now())
        refreshing = false
        switch result {
        case .success(let n): timings.append(Timing(label: "refresh_library (\(n) fonts)", ms: elapsed))
        case .failure(let e): loadError = "\(e)"
        }
        await load()
    }

    func loadPairs(for family: FamilySummary) async {
        guard let lib = library else { return }
        pairsLoading = true
        let id = family.fontId
        let (result, elapsed, err): ([PairBucket], Double, String?) = await Task.detached(priority: .userInitiated) {
            let t0 = DispatchTime.now()
            do {
                let r = try lib.fontPairs(fontId: id, excludedIds: [], job: nil)
                return (r, ms(t0, DispatchTime.now()), nil)
            } catch {
                return ([], ms(t0, DispatchTime.now()), "\(error)")
            }
        }.value
        guard selection == family.id else { return }   // user moved on
        pairsError = err
        buckets = result
        pairsMs = elapsed
        pairsLoading = false
    }
}

func ms(_ a: DispatchTime, _ b: DispatchTime) -> Double {
    Double(b.uptimeNanoseconds - a.uptimeNanoseconds) / 1_000_000
}
