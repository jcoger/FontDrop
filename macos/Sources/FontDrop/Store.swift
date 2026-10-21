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

    init(dbPath: String) { self.dbPath = dbPath }

    var selected: FamilySummary? { families.first { $0.id == selection } }

    /// All DB work runs on a background task; only the results land on the main actor.
    func load() async {
        let db = dbPath
        do {
            let (fams, famMs, fonts, fontMs) = try await Task.detached(priority: .userInitiated) {
                let t0 = DispatchTime.now()
                let fams = try listFamilies(dbPath: db)
                let t1 = DispatchTime.now()
                let fonts = try listFonts(dbPath: db)
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

    func loadPairs(for family: FamilySummary) async {
        pairsLoading = true
        let db = dbPath
        let id = family.fontId
        let (result, elapsed, err): ([PairBucket], Double, String?) = await Task.detached(priority: .userInitiated) {
            let t0 = DispatchTime.now()
            do {
                let r = try fontPairs(dbPath: db, fontId: id, excludedIds: [], job: nil)
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
