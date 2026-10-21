import FontDropCore
import SQLite3
import XCTest
@testable import FontDrop

/// Finding fonts: the remembered filter, the new Reading sort, the words, and the app against a throwaway DB.
/// Fixtures use neutral names only.
@MainActor
final class FinderTests: XCTestCase {
    // MARK: filter state

    func testNewUserSeesYourFontsAndGoogleWithJunkHidden() {
        let f = FinderFilter.standard
        XCTAssertEqual(f.sources, [.yours, .google])
        XCTAssertTrue(f.kinds.isEmpty && f.traits.isEmpty)
        XCTAssertFalse(f.savedOnly)
        XCTAssertFalse(f.showHidden)
        XCTAssertTrue(f.isStandard)
        let q = f.query(text: "")
        XCTAssertEqual(q.sources, [.yours, .google])
        XCTAssertFalse(q.includeHidden)
    }

    func testFilterIsRemembered() {
        let suite = UserDefaults(suiteName: "fontdrop-tests-\(UUID().uuidString)")!
        XCTAssertEqual(FinderFilter.load(from: suite), .standard, "nothing saved yet: the standard filter")
        var f = FinderFilter.standard
        f.sources = [.system]
        f.kinds = [.serif, .mono]
        f.traits = [.variable]
        f.savedOnly = true
        f.showHidden = true
        f.save(to: suite)
        XCTAssertEqual(FinderFilter.load(from: suite), f)
        suite.set(Data("not json".utf8), forKey: FinderFilter.storageKey)
        XCTAssertEqual(FinderFilter.load(from: suite), .standard, "unreadable data falls back")
    }

    func testQueryListsGoOutInAFixedOrder() {
        var f = FinderFilter.standard
        f.sources = [.system, .yours]
        f.kinds = [.mono, .serif]
        f.traits = [.trial, .italic]
        let q = f.query(text: "acme")
        XCTAssertEqual(q.text, "acme")
        XCTAssertEqual(q.sources, [.yours, .system])
        XCTAssertEqual(q.kinds, [.serif, .mono])
        XCTAssertEqual(q.traits, [.italic, .trial])
    }

    // MARK: Less common first

    func testLessCommonFirstPutsFamiliesGoogleDoesNotListFirst() {
        func c(_ id: String, rank: Int?, order: Int) -> Candidate {
            Candidate(id: id, family: "Acme \(id)", pairType: "contrast", evidence: [], order: order, googleRank: rank)
        }
        let all = [c("popular", rank: 2, order: 0), c("middling", rank: 120, order: 1),
                   c("unlisted", rank: nil, order: 2), c("rare", rank: 900, order: 3), c("alsoUnlisted", rank: nil, order: 4)]
        var lenses = Lenses(); lenses.contrast = .any; lenses.sort = .lessCommon
        let ids = LensEngine.apply(all, lenses: lenses).shown.map(\.id)
        // Not on Google first (engine order between them), then the least used on Google, the most used last.
        XCTAssertEqual(ids, ["unlisted", "alsoUnlisted", "rare", "middling", "popular"])
    }

    func testWithoutPopularityDataLessCommonKeepsTheEnginesOrder() {
        let all = (0..<4).map { Candidate(id: "\($0)", family: "Acme \($0)", pairType: "contrast", evidence: [], order: $0) }
        var lenses = Lenses(); lenses.contrast = .any; lenses.sort = .lessCommon
        XCTAssertEqual(LensEngine.apply(all, lenses: lenses).shown.map(\.id), ["0", "1", "2", "3"])
    }

    // MARK: words

    func testChipWordsFollowTheLexicon() {
        XCTAssertEqual(Source.all.map(Lexicon.Finder.sourceLabel), ["Your fonts", "Google Fonts", "Mac system"])
        XCTAssertEqual(Kind.all.map(Lexicon.Finder.kindLabel), ["Serif", "Sans", "Script", "Display", "Mono"])
        XCTAssertEqual(Trait.all.map(Lexicon.Finder.traitLabel), ["Italic", "Variable", "Condensed", "Wide", "Trial"])
        XCTAssertEqual([Lexicon.Finder.hide, Lexicon.Finder.unhide, Lexicon.Finder.saved], ["Hide", "Unhide", "Saved"])
        XCTAssertEqual(Lexicon.Finder.notForLongText(42), "42 not made for long text")
        XCTAssertEqual(ReadingSort.lessCommon.rawValue, Lexicon.Finder.lessCommon)
        XCTAssertEqual(Lexicon.Finder.lessCommonHelp, "Faces fewer sites use. Families not on Google Fonts come first.")
    }

    func testNewStringsHaveNoEmDashesAndNoEngineWords() {
        let strings: [String] = Source.all.map(Lexicon.Finder.sourceLabel) + Kind.all.map(Lexicon.Finder.kindLabel)
            + Trait.all.map(Lexicon.Finder.traitLabel)
            + [Lexicon.Finder.more, Lexicon.Finder.moreHelp, Lexicon.Finder.traitsHeader, Lexicon.Finder.showHidden,
               Lexicon.Finder.hideHelp, Lexicon.Finder.unhideHelp, Lexicon.Finder.savedEmpty, Lexicon.Finder.searchPrompt,
               Lexicon.Finder.noMatches, Lexicon.Finder.lessCommonHelp, Lexicon.Finder.notForLongText(7)]
        for s in strings {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), "dash in: \(s)")
            XCTAssertFalse(s.contains("User") || s == "System", "engine word in: \(s)")
        }
    }

    // MARK: the app against a throwaway DB

    /// Three families, all drawn from a system font file so loading works. Names are neutral.
    private func makeModel() async throws -> AppModel {
        let path = NSTemporaryDirectory() + "fontdrop-finder-\(UUID().uuidString).db"
        _ = try Library.open(path: path)                   // creates the schema
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let rows = [("Acme Sans", "user"), ("Acme Serif", "library"), ("Acme System", "system"), ("Zapf Dingbats", "system")]
        for (i, (family, source)) in rows.enumerated() {
            let sql = """
            INSERT INTO fonts (font_id, name, file_path, file_name, source, font_family, created_at, updated_at)
            VALUES ('id\(i)', '\(family)', '/System/Library/Fonts/SFNS.ttf', 'Regular-\(i).otf', '\(source)', '\(family)', 'x', 'x')
            """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--bench"], environment: [:]))
        await model.bootstrap()
        return model
    }

    func testStandardFilterShowsYoursAndHidesJunk() async throws {
        let model = try await makeModel()
        XCTAssertEqual(model.visibleFamilies.map(\.name), ["Acme Sans", "Acme Serif"], "Your fonts only (Google list is empty offline), no system, no junk")
        let counts = try XCTUnwrap(model.finderResults?.counts)
        XCTAssertEqual(counts.sources.first { $0.source == .yours }?.count, 2)
        XCTAssertEqual(counts.sources.first { $0.source == .system }?.count, 1, "chips show what they would add: Acme System; the junk-list family stays out")
        XCTAssertEqual(counts.hidden, 0, "hidden counts follow the other filters: the junk family is a Mac system font")
        model.filter.sources = [.system]
        await model.finderSettled()
        XCTAssertEqual(model.finderResults?.counts.hidden, 1, "with Mac system on, Show hidden would add the junk-list family")
    }

    func testMacSystemChipAddsSystemFamilies() async throws {
        let model = try await makeModel()
        model.filter.sources = [.yours, .system]
        await model.finderSettled()
        XCTAssertEqual(Set(model.visibleFamilies.map(\.name)), ["Acme Sans", "Acme Serif", "Acme System"])
    }

    func testHideUnhideAndShowHidden() async throws {
        let model = try await makeModel()
        await model.setHidden("Acme Sans", hidden: true)
        XCTAssertEqual(model.visibleFamilies.map(\.name), ["Acme Serif"])
        XCTAssertTrue(model.isHidden("Acme Sans"))
        model.filter.showHidden = true
        await model.finderSettled()
        XCTAssertEqual(Set(model.visibleFamilies.map(\.name)), ["Acme Sans", "Acme Serif"], "Show hidden brings it back, still marked hidden")
        await model.setHidden("Acme Sans", hidden: false)
        XCTAssertFalse(model.isHidden("Acme Sans"))
        model.filter.showHidden = false
        await model.finderSettled()
        XCTAssertEqual(Set(model.visibleFamilies.map(\.name)), ["Acme Sans", "Acme Serif"])
    }

    func testSavedFilterAndCount() async throws {
        let model = try await makeModel()
        XCTAssertEqual(model.savedCount, 0)
        await model.setFavorite("Acme Serif", on: true)
        XCTAssertEqual(model.savedCount, 1)
        XCTAssertTrue(model.isSaved("Acme Serif"))
        model.filter.savedOnly = true
        await model.finderSettled()
        XCTAssertEqual(model.visibleFamilies.map(\.name), ["Acme Serif"])
        await model.setFavorite("Acme Serif", on: false)
        XCTAssertTrue(model.visibleFamilies.isEmpty)
    }

    func testSearchMatchesNames() async throws {
        let model = try await makeModel()
        model.search = "serif"
        await model.finderSettled()
        XCTAssertEqual(model.visibleFamilies.map(\.name), ["Acme Serif"])
    }
}
