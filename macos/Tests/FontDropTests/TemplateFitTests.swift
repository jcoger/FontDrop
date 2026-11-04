import CoreText
import FontDropCore
import SQLite3
import SwiftUI
import XCTest
@testable import FontDrop

/// Type Fit: the sizes every template variant solves to, checked on real families from a DB copy.
///
///   TEST_RUNNER_FONTDROP_DB=<copy of the library DB> xcodebuild test ... -only-testing:FontDropTests/TemplateFitTests
///   TEST_RUNNER_FONTDROP_CONTACT_DIR=<folder>  also writes the contact sheets there
///
/// Without FONTDROP_DB the DB tests skip. The pure ones (scale math, old settings JSON) always run.
@MainActor
final class TemplateFitTests: XCTestCase {
    // MARK: Pure

    func testDefaultStepsMatchTheBoards() {
        XCTAssertEqual(TypeScale.defaultStep(px: 88), 6)
        XCTAssertEqual(TypeScale.defaultStep(px: 64), 5)
        XCTAssertEqual(TypeScale.defaultStep(px: 44), 4)
        XCTAssertEqual(TypeScale.defaultStep(px: 20), 1)
        XCTAssertEqual(TypeScale.defaultStep(px: 15), 0)
        XCTAssertEqual(TypeScale.defaultStep(px: 13), -1)
        XCTAssertEqual(TypeScale.defaultStep(px: 12), -1)
    }

    func testScaleSizeAndNearestRatio() {
        let s = TypeScale(body: 15, ratio: 1.333, locked: true)
        XCTAssertEqual(s.size(step: 0), 15, accuracy: 0.001)
        XCTAssertEqual(s.size(step: 5), 15 * pow(1.333, 5), accuracy: 0.001)
        XCTAssertEqual(TypeScale.nearestRatio(1.3), 1.333)
        XCTAssertEqual(TypeScale.nearestRatio(1.9), 1.618)
        XCTAssertEqual(TypeScale.nearestRatio(1.0), 1.2)
    }

    func testTrimReadout() {
        XCTAssertEqual(Lexicon.Scale.trimReadout(1.08), "+8%")
        XCTAssertEqual(Lexicon.Scale.trimReadout(1), "0%")
        XCTAssertEqual(Lexicon.Scale.trimReadout(0.88), "-12%")
    }

    /// The saved playground file from before Fit: it holds a `size` (63.15) and no `trim`. It loads, `size` is ignored,
    /// the style path and tracking survive, and trim is 1.
    func testOldSettingsJSONLoadsAndIgnoresSize() throws {
        let json = """
        {"1\\/display\\/Agrandir":{"size":63.152857236204675,"axes":{},"lineHeight":1.1237757651146405,"tracking":0.0657,
         "stylePath":"\\/Fonts\\/Agrandir-GrandHeavy.otf","features":{}},
         "1\\/reading\\/PP Right Slab":{"size":14.2,"axes":{},"lineHeight":1.5,"tracking":0,"features":{}},
         "1\\/reading\\/Odd":{"size":"big","lineHeight":"x"}}
        """
        let map = try JSONDecoder().decode([String: TypeSettings].self, from: Data(json.utf8))
        let d = try XCTUnwrap(map["1/display/Agrandir"])
        XCTAssertEqual(d.trim, 1)
        XCTAssertEqual(d.stylePath, "/Fonts/Agrandir-GrandHeavy.otf")
        XCTAssertEqual(d.tracking, 0.0657, accuracy: 0.0001)
        XCTAssertEqual(d.size, TypeSettings.defaults(job: "reading").size, "size is not read from the file")
        XCTAssertNotNil(map["1/reading/Odd"], "a malformed field takes its default instead of failing the file")
        // Size is not written back.
        let out = String(decoding: try JSONEncoder().encode(d), as: UTF8.self)
        XCTAssertFalse(out.contains("\"size\""))
        XCTAssertTrue(out.contains("\"trim\""))
    }

    func testStoreGivesLoadedFacesTheirJobsBaseSize() throws {
        let path = NSTemporaryDirectory() + "fontdrop-fit-\(UUID().uuidString).db"
        try Data("{\"1\\/display\\/A\":{\"size\":63,\"lineHeight\":1.1},\"1\\/reading\\/B\":{\"size\":9,\"lineHeight\":1.5}}".utf8)
            .write(to: URL(fileURLWithPath: path + ".playground.json"))
        defer { try? FileManager.default.removeItem(atPath: path + ".playground.json") }
        let store = TypeSettingsStore(dbPath: path, persist: false)
        XCTAssertEqual(store.settings("1/display/A", job: "display").size, 40)
        XCTAssertEqual(store.settings("1/reading/B", job: "reading").size, 15)
        XCTAssertFalse(store.isModified("1/display/A", job: "display"))
    }

    func testScaleStoreRoundTripsAndClampsBody() throws {
        let path = NSTemporaryDirectory() + "fontdrop-scale-\(UUID().uuidString).db"
        let store = ScaleStore(dbPath: path, persist: false)
        XCTAssertFalse(store.scale(brand: 1).locked)
        store.update(brand: 1) { $0.body = 99; $0.locked = true }
        XCTAssertEqual(store.scale(brand: 1).body, 24)
        XCTAssertEqual(store.scale(brand: 2).body, 15, "per brand")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".scale.json"), "persist false never writes")
    }

    // MARK: Samples from a DB copy

    struct Sample {
        let name: String
        let face: FaceSpec          // the Display face
        /// The Reading face, when it is not the Display face itself.
        let body: FaceSpec?
    }

    /// Families the core's built-in junk list hides (picture fonts, symbol sets), so they are not in a real Display or Reading list.
    private static let hiddenFamilies: Set<String> = ["apple symbols", "bodoni ornaments", "webdings", "wingdings", "wingdings 2", "wingdings 3", "zapf dingbats", "apple chancery"]

    private struct Row { let family: String; let path: String; let weight: Int; let category: String; let name: String }

    private func dbPath() throws -> String {
        guard let p = ProcessInfo.processInfo.environment["FONTDROP_DB"], FileManager.default.fileExists(atPath: p) else {
            throw XCTSkip("set TEST_RUNNER_FONTDROP_DB to a copy of the library DB")
        }
        return p
    }

    private func rows(_ path: String) -> [Row] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT font_family, file_path, COALESCE(weight, 400), COALESCE(category, ''), COALESCE(name, '') FROM fonts WHERE covers_latin = 1 AND font_family <> ''"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [Row] = []
        func text(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Row(family: text(0), path: text(1), weight: Int(sqlite3_column_int(stmt, 2)), category: text(3), name: text(4)))
        }
        return out.filter { !Self.hiddenFamilies.contains($0.family.lowercased()) }
    }

    /// Wide, narrow, heavy, hairline and script faces, plus Agrandir (regular and GrandHeavy), PP Museum and Timeless,
    /// topped up to at least 20 with evenly spaced others. Sorted, so a run repeats.
    private func samples(_ dbFile: String) async -> [Sample] {
        let all = rows(dbFile)
        let byFamily = Dictionary(grouping: all, by: \.family)
        func isItalic(_ r: Row) -> Bool { r.name.lowercased().contains("italic") || r.path.lowercased().contains("italic") }
        func regular(_ list: [Row]) -> Row? {
            list.filter { !isItalic($0) }.min { abs($0.weight - 400) < abs($1.weight - 400) } ?? list.first
        }
        let reps = byFamily.compactMapValues(regular)
        await FontLoader.shared.preload(paths: reps.values.map(\.path))
        func face(_ r: Row, family: String, style: Row? = nil) -> FaceSpec {
            var s = TypeSettings.defaults(job: "display")
            s.stylePath = style.map(\.path)
            let files = byFamily[family] ?? []
            return FaceSpec(path: r.path, settings: s, siblings: files.map(\.path),
                            weights: Dictionary(files.map { ($0.path, $0.weight) }, uniquingKeysWith: { a, _ in a }))
        }
        // Average width of a word, per em: wide faces are high, narrow ones low.
        func width(_ r: Row) -> Double? {
            guard case .success(let loaded)? = FontLoader.shared.cached(r.path), loaded.canDraw("Hamburgefonstiv") else { return nil }
            let font = loaded.font(size: 100)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hamburgefonstiv", attributes: [.font: font]))
            return CTLineGetTypographicBounds(line, nil, nil, nil) / 100 / 15
        }
        let measured: [(family: String, row: Row, w: Double)] = reps.compactMap { f, r in width(r).map { (f, r, $0) } }
            .sorted { $0.family < $1.family }
        var picked: [String: Sample] = [:]
        func add(_ name: String, _ family: String, _ r: Row, style: Row? = nil) {
            guard picked[name] == nil, case .success? = FontLoader.shared.cached((style ?? r).path) else { return }
            picked[name] = Sample(name: name, face: face(r, family: family, style: style), body: nil)
        }
        // Forced: the reference faces and the face that showed the problem.
        for fam in ["PP Museum", "Timeless Sans", "Timeless Serif", "Agrandir"] {
            if let r = reps[fam] { add(fam, fam, r) }
        }
        if let files = byFamily["Agrandir"], let heavy = files.first(where: { $0.path.hasSuffix("Agrandir-GrandHeavy.otf") }), let r = reps["Agrandir"] {
            await FontLoader.shared.preload(paths: [heavy.path])
            add("Agrandir GrandHeavy", "Agrandir", r, style: heavy)
        }
        let byWidth = measured.sorted { $0.w < $1.w }
        for m in byWidth.prefix(3) { add(m.family + " (narrow)", m.family, m.row) }
        for m in byWidth.suffix(3) { add(m.family + " (wide)", m.family, m.row) }
        // Heavy and hairline: the family's heaviest and lightest single file.
        let heavyFiles = all.filter { $0.weight >= 900 && !isItalic($0) }.sorted { $0.family < $1.family }
        let hairFiles = all.filter { $0.weight <= 100 && !isItalic($0) }.sorted { $0.family < $1.family }
        await FontLoader.shared.preload(paths: (heavyFiles.prefix(40) + hairFiles.prefix(40)).map(\.path))
        func pickFiles(_ files: [Row], label: String, count: Int) {
            var n = 0
            for r in files.prefix(80) where n < count {
                guard let rep = reps[r.family], width(r) != nil else { continue }
                add("\(r.family) (\(label))", r.family, rep, style: r); n += 1
            }
        }
        pickFiles(heavyFiles, label: "heavy", count: 3)
        pickFiles(hairFiles, label: "hairline", count: 3)
        for m in measured where m.row.category == "script" && picked.keys.filter({ $0.hasSuffix("(script)") }).count < 3 {
            add(m.family + " (script)", m.family, m.row)
        }
        // Top up with evenly spaced others.
        let others = measured.filter { m in !picked.values.contains { $0.face.path == m.row.path } }
        var i = 0
        let step = max(others.count / 12, 1)
        while picked.count < 22, i < others.count {
            add(others[i].family, others[i].family, others[i].row)
            i += step
        }
        // A display face is never the Reading face in real use: every one is paired with Timeless Sans as body.
        let body = picked["Timeless Sans"]?.face
        return picked.values.sorted { $0.name < $1.name }.map { Sample(name: $0.name, face: $0.face, body: body) }
    }

    /// Real Reading candidates: the families the core's Reading list keeps (junk list out, not unfit for long text),
    /// each as the body face under PP Museum as the Display face. Evenly spaced, 22 of them.
    private func readingSamples(_ dbFile: String, museum: FaceSpec) async throws -> [Sample] {
        let lib = try Library.open(path: dbFile)
        let ok = Set(try lib.readingFamilies(excludedIds: [], excludedFamilies: [], onlyFit: true).families.map(\.family))
        let all = rows(dbFile).filter { ok.contains($0.family) }
        let byFamily = Dictionary(grouping: all, by: \.family)
        func isItalic(_ r: Row) -> Bool { r.name.lowercased().contains("italic") || r.path.lowercased().contains("italic") }
        var reps: [String: Row] = [:]
        for (f, list) in byFamily {
            reps[f] = list.filter { !isItalic($0) }.min { abs($0.weight - 400) < abs($1.weight - 400) } ?? list.first
        }
        await FontLoader.shared.preload(paths: reps.values.map(\.path))
        let usable = reps.keys.sorted().filter { f in
            if case .success(let l)? = FontLoader.shared.cached(reps[f]!.path) { return l.canDraw("Hamburgefonstiv") }
            return false
        }
        var names = Array(Set(usable.enumerated().filter { $0.offset % max(usable.count / 20, 1) == 0 }.map(\.element)))
        for f in ["Timeless Sans", "Agrandir"] where usable.contains(f) && !names.contains(f) { names.append(f) }
        return names.sorted().map { f in
            let r = reps[f]!
            let files = byFamily[f] ?? []
            var s = TypeSettings.defaults(job: "reading")
            s.stylePath = nil
            let body = FaceSpec(path: r.path, settings: s, siblings: files.map(\.path),
                                weights: Dictionary(files.map { ($0.path, $0.weight) }, uniquingKeysWith: { a, _ in a }))
            return Sample(name: "reading · \(f)", face: museum, body: body)
        }
    }

    private func context(_ sample: Sample, recorder: FitRecorder? = nil, scale: TypeScale = TypeScale()) -> PairContext {
        let face = sample.face
        var body = sample.body ?? face
        body.settings = TypeSettings.defaults(job: "reading")
        body.settings.stylePath = nil
        var c = PairContext(brand: "Acme", display: face, body: body, tick: 0, scale: scale)
        c.recorder = recorder
        return c
    }

    private func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = 1) -> CGImage? {
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        r.scale = scale
        return r.cgImage
    }

    // MARK: Reference metrics

    /// The constants in TypeFit were measured on these two faces. If the files change, this says so.
    func testReferenceMetricsMatch() async throws {
        let db = try dbPath()
        let list = await samples(db)
        func metrics(_ name: String) -> TypeFit.Metrics? { list.first { $0.name == name }.flatMap { TypeFit.metrics($0.face) } }
        guard let museum = metrics("PP Museum"), let timeless = metrics("Timeless Sans") else { throw XCTSkip("PP Museum and Timeless Sans are not in this library") }
        XCTAssertEqual(museum.cap, TypeFit.refCapHeight, accuracy: 0.01)
        XCTAssertEqual(timeless.xHeight, TypeFit.refXHeight, accuracy: 0.01)
    }

    // MARK: Every variant

    private struct Check { var failures: [String] = []; var clamped: [String] = []; var rows: [String] = []; var limited: [String] = []; var measured: [String] = [] }

    /// Renders each template variant for each sample and checks what the views solved.
    func testEveryVariantFitsEverySample() async throws {
        let db = try dbPath()
        let stress = await samples(db)
        XCTAssertGreaterThanOrEqual(stress.count, 20, "need 20 families to test")
        // And the other direction: real Reading candidates under PP Museum.
        let museum = try XCTUnwrap(stress.first { $0.name == "PP Museum" }, "PP Museum is in the library").face
        let list = stress + (try await readingSamples(db, museum: museum))
        let strictFaces: Set<String> = ["PP Museum", "Timeless Sans", "Timeless Serif", "Agrandir", "Agrandir GrandHeavy"]
        var check = Check()
        var museumRatios: [String: CGFloat] = [:]
        for sample in list {
            for template in Templates.all {
                for variant in template.variants {
                    let recorder = FitRecorder()
                    let d = template.configured(palette: .paper, variant: variant.id)
                    var ctx = context(sample, recorder: recorder)
                    ctx.palette = .paper
                    _ = render(d.make(ctx), size: CGSize(width: 600, height: 900))
                    let tag = "\(sample.name) | \(template.id).\(variant.id)"
                    var seen = Set<String>()
                    for r in recorder.records {
                        guard seen.insert("\(r.kind)|\(r.text)|\(r.px)|\(r.size)").inserted else { continue }
                        // 0. a poster word fills the sheet: inside its inner width, and at least half of it
                        if r.fillWord, let width = r.width, let w = r.lineWidths.first {
                            if w > width + 1 { check.failures.append("\(tag): poster word \"\(r.text)\" is \(Int(w)) wide in \(Int(width))") }
                            // The word's box holds its ink, so a descender never reaches the line under it and the top never
                            // reaches the bars above it; and the stack of fill words fits the board (narrow faces too).
                            if let ink = r.inkHeight, let frame = r.frameHeight, frame < ink - 0.01 {
                                check.failures.append("\(tag): poster word \"\(r.text)\" box \(Int(frame)) is shorter than its ink \(Int(ink))")
                            }
                            if let frame = r.frameHeight, frame > 800 {
                                check.failures.append("\(tag): poster word \"\(r.text)\" is \(Int(frame)) tall on an 800 board")
                            }
                            if w < width * 0.5 {
                                if strictFaces.contains(sample.name) {
                                    check.failures.append("\(tag): poster word \"\(r.text)\" fills only \(Int(w / width * 100))%")
                                } else {
                                    check.limited.append("\(tag): poster word \"\(r.text)\" fill \(Int(w / width * 100))% (height)")
                                }
                            }
                            check.rows.append("\(sample.name) | \(template.id).\(variant.id) | poster word \"\(r.text)\" \(Int(r.px)) -> \(String(format: "%.0f", r.size)) | fill \(Int(w / width * 100))%")
                        }
                        // 1. no word is split
                        if let width = r.width, !r.lines.isEmpty {
                            let joined = r.lines.joined(separator: " ").split(separator: " ").joined(separator: " ")
                            let original = r.text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ")
                            if joined != original { check.failures.append("\(tag): word split in \"\(r.text)\" -> \(r.lines)") }
                            if r.kind == .headline, let w = r.lineWidths.max(), w > width + 1 {
                                check.failures.append("\(tag): headline line \(Int(w)) wider than the column \(Int(width))")
                            }
                        }
                        // 2. headline lines do not overlap
                        if r.kind == .headline, r.lines.count > 1, let pitch = r.pitch, let need = r.need, pitch < need - 0.01 {
                            check.failures.append("\(tag): lines overlap, pitch \(pitch) < need \(need)")
                        }
                        // 3. a headline fills 75 to 100% of its column (unless the board's height or the ceiling stopped it)
                        if r.kind == .headline, r.width != nil, let fill = r.fill {
                            if r.heightLimited || r.capped {
                                check.limited.append("\(tag): \"\(r.text.prefix(24))\" fill \(Int(fill * 100))% (\(r.heightLimited ? "height" : "ceiling"))")
                            } else if fill < 0.75 || fill > 1.005 {
                                check.failures.append("\(tag): headline fill \(Int(fill * 100))%")
                            }
                            if sample.name == "PP Museum", template.id != "poster" { museumRatios["\(template.id).\(variant.id)"] = r.size / r.px }
                            check.rows.append("\(sample.name) | \(template.id).\(variant.id) | headline \(Int(r.px)) -> \(String(format: "%.1f", r.size)) | \(r.lines.count) lines | fill \(Int(fill * 100))%")
                        }
                        // 5. Reading in a column keeps at least 18 characters a line (smaller type, then a wider column)
                        if r.kind == .reading, let chars = r.charsPerLine {
                            if chars < TypeFit.minCharsPerLine - 0.5 {
                                check.failures.append("\(tag): \"\(r.text.prefix(24))\" only \(String(format: "%.1f", chars)) characters a line")
                            }
                            check.measured.append("\(sample.name) | \(template.id).\(variant.id) | \(String(format: "%.1f", chars)) chars a line at \(String(format: "%.1f", r.size)) pt")
                        }
                        // 4. body x-height within 5% of the target (unless clamped)
                        if r.kind == .reading, let t = r.xTarget, let a = r.xActual, t > 0 {
                            if r.clamped {
                                check.clamped.append("\(tag): reading \(Int(r.px)) -> \(String(format: "%.1f", r.size)) (clamped)")
                            } else if abs(a / t - 1) > 0.05 {
                                check.failures.append("\(tag): x-height off by \(Int((a / t - 1) * 100))% at \(Int(r.px))px")
                            }
                        }
                    }
                }
            }
        }
        print("FIT TABLE\n" + check.rows.sorted().joined(separator: "\n"))
        print("FIT LIMITED (\(check.limited.count))\n" + Set(check.limited).sorted().joined(separator: "\n"))
        print("FIT MEASURE\n" + Set(check.measured).sorted().joined(separator: "\n"))
        print("FIT CLAMPED (\(Set(check.clamped).count))\n" + Set(check.clamped).sorted().joined(separator: "\n"))
        print("FIT SAMPLES: " + list.map(\.name).joined(separator: ", "))
        print("FIT PP MUSEUM size/px: \(museumRatios.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.2f", $0.value))" }.joined(separator: " "))")
        for (k, v) in museumRatios { XCTAssertTrue((0.75...1.3).contains(v), "PP Museum \(k) solved to \(v)x its board size") }
        XCTAssertEqual(check.failures, [])
    }

    /// Locked: every role takes body x ratio^step. Headlines still wrap and keep words whole.
    func testLockedScaleSizesAndKeepsWordsWhole() async throws {
        let db = try dbPath()
        let list = await samples(db)
        let locked = TypeScale(body: 15, ratio: 1.333, locked: true)
        var failures: [String] = []
        for sample in list.prefix(8) {
            for template in Templates.all where template.id != "poster" {
                for variant in template.variants {
                    let recorder = FitRecorder()
                    let d = template.configured(palette: .paper, variant: variant.id)
                    _ = render(d.make(context(sample, recorder: recorder, scale: locked)), size: CGSize(width: 600, height: 900))
                    for r in recorder.records where r.kind == .reading {
                        let expect = locked.size(step: TypeScale.defaultStep(px: r.px))
                        if abs(Double(r.size) - expect) > 0.01 { failures.append("\(sample.name) \(template.id).\(variant.id): \(r.px) -> \(r.size), want \(expect)") }
                    }
                    for r in recorder.records where r.width != nil && !r.lines.isEmpty {
                        let joined = r.lines.joined(separator: " ").split(separator: " ").joined(separator: " ")
                        if joined != r.text.split(whereSeparator: { $0 == " " || $0 == "\n" }).joined(separator: " ") { failures.append("\(sample.name): split \(r.text)") }
                    }
                }
            }
        }
        XCTAssertEqual(failures, [])
    }

    /// Counts pictorial families (ornaments, dingbats, symbol sets) among the Latin-covering families the Display and
    /// Reading lists draw from. By name only; it prints, it does not assert, and nothing is filtered.
    func testCountPictorialFamilies() throws {
        let db = try dbPath()
        let words = ["ornament", "dingbat", "webdings", "wingdings", "symbol", "emoji", "picto", "bats", "glyphs", "fleuron"]
        let families = Set(rows(db).map(\.family)).sorted()
        let hits = families.filter { f in words.contains { f.lowercased().contains($0) } }
        print("FIT PICTORIAL \(hits.count) of \(families.count) families: \(hits.joined(separator: ", "))")
    }

    /// Draws a two-line headline and reads the pixels: there must be a blank row between the lines. This checks what is
    /// on screen, not the numbers the solver used, so a mismatch between Core Text's line height and SwiftUI's shows up.
    func testHeadlineLinesHaveAirOnScreen() async throws {
        let db = try dbPath()
        let list = await samples(db)
        var failures: [String] = []
        var report: [String] = []
        let black = HexColor(r: 0, g: 0, b: 0)
        for name in ["PP Museum", "Timeless Sans", "Agrandir", "Agrandir GrandHeavy", "FREE FAT FONT", "ABC Repro Unlicensed Trial (heavy)", "Monument Extended (wide)", "Humane (narrow)"] {
            guard let sample = list.first(where: { $0.name == name }) else { continue }
            for (label, spec) in [("feature", ArticleFeature.headline), ("essay", ArticleEssay.headline), ("product", HeroProduct.headline)] {
                let recorder = FitRecorder()
                let ctx = context(sample, recorder: recorder)
                let view = ctx.headline(spec, color: black).frame(width: spec.width, alignment: .leading).fixedSize().padding(24).background(Color.white)
                let r = ImageRenderer(content: view)
                r.scale = 1
                guard let image = r.cgImage, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { continue }
                let (w, h, bpr) = (image.width, image.height, image.bytesPerRow)
                var inkRows: [Bool] = []
                for y in 0..<h {
                    var ink = false
                    for x in stride(from: 0, to: w, by: 1) where bytes[y * bpr + x * 4] < 128 { ink = true; break }
                    inkRows.append(ink)
                }
                guard let first = inkRows.firstIndex(of: true), let last = inkRows.lastIndex(of: true) else { continue }
                // The blank bands between ink: one for every pair of lines, each at least a pixel tall.
                var bands: [Int] = [], gap = 0
                for y in first...last { if inkRows[y] { if gap > 0 { bands.append(gap) }; gap = 0 } else { gap += 1 } }
                let expected = max((recorder.records.last { $0.kind == .headline }?.lines.count ?? 1) - 1, 0)
                report.append("\(name) | \(label) | \(expected) gaps, bands \(bands) px")
                if bands.count < expected { failures.append("\(name) \(label): \(expected) gaps wanted, \(bands.count) found: lines touch") }
            }
        }
        print("FIT AIR\n" + report.joined(separator: "\n"))
        XCTAssertEqual(failures, [])
    }

    // MARK: Contact sheets

    /// Landing hero . Statement and Article . Essay for every sample, in a grid. Written when a folder is given.
    func testContactSheets() async throws {
        let db = try dbPath()
        guard let dir = ProcessInfo.processInfo.environment["FONTDROP_CONTACT_DIR"] else { throw XCTSkip("set TEST_RUNNER_FONTDROP_CONTACT_DIR to write the sheets") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stress = await samples(db)
        let museum = try XCTUnwrap(stress.first { $0.name == "PP Museum" }, "PP Museum is in the library").face
        let reading = try await readingSamples(db, museum: museum)
        // Set 1: each Display stress face under Timeless Sans. Set 2: each real Reading candidate under PP Museum.
        let sets: [(String, [Sample], [(String, TypeScale)])] = [
            ("", stress, [("", TypeScale()), ("-locked", TypeScale(body: 15, ratio: 1.333, locked: true))]),
            ("reading-", reading, [("", TypeScale())]),
        ]


        // Every variant, Fit and locked. Cell heights follow the boards: hero 640, poster 750 to 800, the rest grow with their text.
        let all: [(String, String, CGFloat)] = Templates.all.flatMap { t in
            t.variants.map { v in (t.id, v.id, t.id == "hero" ? 352 : t.id == "poster" ? 440 : 560) }
        }
        for (id, variant, cellHeight) in all {
            for (prefix, list, scales) in sets { for (suffix, scale) in scales {
                let template = Templates.descriptor(id).configured(palette: .paper, variant: variant)
                let cell: CGFloat = 330
                let cols = 5
                let sheet = LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 12), count: cols), spacing: 14) {
                    ForEach(list, id: \.name) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            template.make(self.context(s, scale: scale))
                                .frame(width: cell, height: cellHeight, alignment: .top).clipped()
                                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.15)))
                        }
                    }
                }
                .padding(16).frame(width: CGFloat(cols) * (cell + 12) + 20, alignment: .topLeading).background(Color.white)
                let r = ImageRenderer(content: sheet)
                r.scale = 1
                let image = try XCTUnwrap(r.cgImage)
                let url = URL(fileURLWithPath: dir).appendingPathComponent("contact-\(prefix)\(id)-\(variant)\(suffix).png")
                let rep = NSBitmapImageRep(cgImage: image)
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
            } }
        }
    }
}
