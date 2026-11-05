import FontDropCore
import XCTest
@testable import FontDrop

/// Round R6: Export. Each exporter's output is pinned as a string, the license flags are pinned, and the Set screen's
/// face resolution (the style the designer chose) is pinned against the same store the Display inspector writes.
@MainActor
final class ExportTests: XCTestCase {
    // MARK: A fixed pair

    private func face(_ role: String, _ family: String, style: String, ps: String, full: String, weight: Int,
                      tracking: Double = 0, optical: Double? = nil, axes: [String: Double] = [:],
                      foundry: String? = nil, url: String? = nil, trial: Bool = false, google: Bool = false) -> ExportFace {
        ExportFace(role: role, family: family, style: style, postScript: ps, fullName: full, weight: weight, generic: "sans-serif",
                   tracking: tracking, trim: 1, opticalSize: optical, axes: axes, foundry: foundry, foundryURL: url,
                   isTrial: trial, isGoogle: google)
    }

    private var spec: ExportSpec {
        ExportSpec(brandName: "Acme",
                   display: face("Display", "Agrandir", style: "Grand Heavy", ps: "Agrandir-GrandHeavy", full: "Agrandir Grand Heavy",
                                 weight: 800, tracking: 0.0657, foundry: "Type Foundry", url: "https://example.com/agrandir"),
                   text: face("Text", "PP Neue Machina", style: "Regular", ps: "PPNeueMachina-Plain", full: "PP Neue Machina Regular",
                              weight: 400, tracking: -0.01, optical: 20, trial: true),
                   sizes: [.display: 63, .h1: 47, .h2: 36, .h3: 27, .lead: 20, .body: 15, .caption: 11],
                   leading: [.display: 1.05, .h1: 1.1, .h2: 1.15, .h3: 1.2, .lead: 1.3, .body: 1.45, .caption: 1.4],
                   measure: 66, bodyLineHeight: 1.45, ratio: 1.333, bodySize: 15, colors: nil)
    }

    // MARK: Snapshots

    func testCSSSnapshot() {
        let expected = """
        /* Acme type pair
           Display: Agrandir, Grand Heavy (Agrandir-GrandHeavy)
           Text: PP Neue Machina, Regular (PPNeueMachina-Plain)
           Sizes are px. A point in FontDrop is one CSS px. */

        @font-face {
          font-family: "Agrandir";
          font-weight: 800;
          src: local("Agrandir-GrandHeavy"), local("Agrandir Grand Heavy");
        }
        @font-face {
          font-family: "PP Neue Machina";
          font-weight: 400;
          src: local("PPNeueMachina-Plain"), local("PP Neue Machina Regular");
        }

        :root {
          --font-display: "Agrandir", sans-serif;
          --font-display-weight: 800;
          --tracking-display: 0.0657em;
          --font-text: "PP Neue Machina", sans-serif;
          --font-text-weight: 400;
          --tracking-text: -0.01em;
          --font-text-variation: "opsz" 20;
          --text-display: 63px;
          --text-h1: 47px;
          --text-h2: 36px;
          --text-h3: 27px;
          --text-lead: 20px;
          --text-body: 15px;
          --text-caption: 11px;
          --leading-display: 1.05;
          --leading-h1: 1.1;
          --leading-h2: 1.15;
          --leading-h3: 1.2;
          --leading-lead: 1.3;
          --leading-body: 1.45;
          --leading-caption: 1.4;
          --measure: 66ch;
        }

        /* Usage: <h1 class="t-display">, <p class="t-body">. One class per step. */
        .t-display {
          font-family: var(--font-display);
          font-weight: var(--font-display-weight);
          font-size: var(--text-display);
          line-height: var(--leading-display);
          letter-spacing: var(--tracking-display);
        }
        .t-h1 {
          font-family: var(--font-display);
          font-weight: var(--font-display-weight);
          font-size: var(--text-h1);
          line-height: var(--leading-h1);
          letter-spacing: var(--tracking-display);
        }
        .t-h2 {
          font-family: var(--font-display);
          font-weight: var(--font-display-weight);
          font-size: var(--text-h2);
          line-height: var(--leading-h2);
          letter-spacing: var(--tracking-display);
        }
        .t-h3 {
          font-family: var(--font-display);
          font-weight: var(--font-display-weight);
          font-size: var(--text-h3);
          line-height: var(--leading-h3);
          letter-spacing: var(--tracking-display);
        }
        .t-lead {
          font-family: var(--font-text);
          font-weight: var(--font-text-weight);
          font-size: var(--text-lead);
          line-height: var(--leading-lead);
          letter-spacing: var(--tracking-text);
          font-variation-settings: var(--font-text-variation);
        }
        .t-body {
          font-family: var(--font-text);
          font-weight: var(--font-text-weight);
          font-size: var(--text-body);
          line-height: var(--leading-body);
          letter-spacing: var(--tracking-text);
          font-variation-settings: var(--font-text-variation);
          max-width: var(--measure);
        }
        .t-caption {
          font-family: var(--font-text);
          font-weight: var(--font-text-weight);
          font-size: var(--text-caption);
          line-height: var(--leading-caption);
          letter-spacing: var(--tracking-text);
          font-variation-settings: var(--font-text-variation);
        }

        """
        XCTAssertEqual(Exporters.css(spec), expected)
    }

    private let themeBody = """
        @theme {
          --font-display: "Agrandir", sans-serif;
          --font-text: "PP Neue Machina", sans-serif;
          --font-weight-display-style: 800;
          --font-weight-text-style: 400;
          --text-display: 63px;
          --text-display--line-height: 1.05;
          --text-h1: 47px;
          --text-h1--line-height: 1.1;
          --text-h2: 36px;
          --text-h2--line-height: 1.15;
          --text-h3: 27px;
          --text-h3--line-height: 1.2;
          --text-lead: 20px;
          --text-lead--line-height: 1.3;
          --text-body: 15px;
          --text-body--line-height: 1.45;
          --text-caption: 11px;
          --text-caption--line-height: 1.4;
          --leading-display: 1.05;
          --leading-h1: 1.1;
          --leading-h2: 1.15;
          --leading-h3: 1.2;
          --leading-lead: 1.3;
          --leading-body: 1.45;
          --leading-caption: 1.4;
          --tracking-display: 0.0657em;
          --tracking-text: -0.01em;
        }

        """

    func testTailwindThemeSnapshot() {
        let out = Exporters.theme(spec)
        let block = String(out[out.range(of: "@theme {")!.lowerBound...])
        XCTAssertEqual(block, themeBody)
        XCTAssertTrue(out.hasPrefix("/* Acme type pair"), "the full theme carries the header and the font rules")
        XCTAssertTrue(out.contains("src: local(\"Agrandir-GrandHeavy\")"))
    }

    func testPaperTokensAreTheSameThemeTitledForPaper() {
        let out = Exporters.theme(spec, paper: true)
        XCTAssertTrue(out.hasPrefix("/* Acme type tokens for Paper. Paste into Paper's design tokens. */\n@theme {\n"))
        XCTAssertEqual(String(out[out.range(of: "@theme {")!.lowerBound...]), String(Exporters.theme(spec)[Exporters.theme(spec).range(of: "@theme {")!.lowerBound...]),
                       "Paper reads the same Tailwind v4 tokens")
        XCTAssertFalse(out.contains("@font-face"), "tokens only")
    }

    /// A browser counts the measure in `ch`, the width of a zero. The export converts from Set's characters so the column is as wide.
    func testMeasureExportsInChWhenKnownAndInCharactersOtherwise() {
        var s = spec
        XCTAssertTrue(Exporters.css(s).contains("--measure: 66ch;"))
        s.measureCh = 58
        XCTAssertTrue(Exporters.css(s).contains("--measure: 58ch;"))
    }

    func testNumbersLoseTrailingZeros() {
        XCTAssertEqual(Exporters.num(47.0), "47")
        XCTAssertEqual(Exporters.num(1.10), "1.1")
        XCTAssertEqual(Exporters.num(0.0657, places: 4), "0.0657")
        XCTAssertEqual(Exporters.num(0, places: 4), "0")
        XCTAssertEqual(Exporters.num(-0.00001, places: 4), "0")
    }

    // MARK: Licenses

    func testLicenseListFlagsTrialsAndGoogleAndNamesTheFoundry() {
        let expected = """
        Acme font licenses

        Display: Agrandir, Grand Heavy
          Foundry: Type Foundry
          Link: https://example.com/agrandir
          Check the foundry's terms for web and app use

        Text: PP Neue Machina, Regular
          Foundry: not named in the font file
          Link: no link in the font file
          License before you ship

        """
        XCTAssertEqual(Exporters.licenses(spec), expected)
    }

    func testLicenseFlagRules() {
        var f = face("Text", "A", style: "Regular", ps: "A", full: "A", weight: 400)
        XCTAssertEqual(Exporters.licenseFlag(f), "Check the foundry's terms for web and app use")
        f.isGoogle = true
        XCTAssertEqual(Exporters.licenseFlag(f), "Open license (Google Fonts)")
        f.isTrial = true
        XCTAssertEqual(Exporters.licenseFlag(f), "License before you ship", "a trial says license first, even when the name is in Google's list")
        f.isGoogle = false
        XCTAssertEqual(Exporters.licenseFlag(f), "License before you ship")
    }

    // MARK: Strings

    func testExportStringsHaveNoEmDashesAndTheDisabledReasonIsPlain() {
        let all = [Lexicon.Export.menu, Lexicon.Export.copyCSS, Lexicon.Export.copyTailwind, Lexicon.Export.copyPaper, Lexicon.Export.specPage,
                   Lexicon.Export.copyLicenses, Lexicon.Export.needsFaces, Lexicon.Export.cssCopied, Lexicon.Export.tailwindCopied,
                   Lexicon.Export.paperCopied, Lexicon.Export.licensesCopied, Lexicon.Export.specSaved, Lexicon.Export.helpCSS,
                   Lexicon.Export.helpTailwind, Lexicon.Export.helpPaper, Lexicon.Export.helpSpec, Lexicon.Export.helpLicenses,
                   Lexicon.Export.scaleNote, Lexicon.Export.noFoundry, Lexicon.Export.noLink,
                   Lexicon.Export.faceTuning(role: "Display", trim: 1, tracking: 0.02, opticalSize: nil)]
        for s in all { XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), s) }
        XCTAssertEqual(Lexicon.Export.needsFaces, "Pick a Display and a Text face to export")
        XCTAssertEqual(Lexicon.Export.cssCopied, "CSS copied")
        XCTAssertEqual(Lexicon.Export.faceTuning(role: "Display", trim: 1, tracking: 0.02, opticalSize: nil),
                       "Display: trim 1.00 \u{00B7} tracking 2.0% \u{00B7} optical size Auto")
    }

    // MARK: From a real library

    private func fixtureFolder() throws -> String {
        let source = "/System/Library/Fonts/Supplemental"
        let files = ["Arial", "Georgia"].flatMap { f in ["", " Bold", " Italic", " Bold Italic"].map { "\(f)\($0).ttf" } }
        for f in files where !FileManager.default.fileExists(atPath: "\(source)/\(f)") { throw XCTSkip("no system \(f)") }
        let dir = NSTemporaryDirectory() + "fontdrop-export-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for f in files { try FileManager.default.copyItem(atPath: "\(source)/\(f)", toPath: "\(dir)/\(f)") }
        return dir
    }

    private func makeModel(folder: String) async -> AppModel {
        let path = NSTemporaryDirectory() + "fontdrop-export-\(UUID().uuidString).db"
        let defaults = UserDefaults(suiteName: "fontdrop-export-\(UUID().uuidString)")!
        let model = AppModel(options: LaunchOptions(arguments: ["FontDrop", "--db", path, "--scan-folders", folder], environment: [:]), defaults: defaults)
        await model.bootstrap()
        await model.createBrand("Acme")
        return model
    }

    func testExportReadsTheChosenStyleFromALibrary() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = await makeModel(folder: dir)
        await model.choose("display", family: "Arial")
        await model.choose("reading", family: "Georgia")
        let plainMade = await ExportSpec.make(model: model)
        let plain = try XCTUnwrap(plainMade)
        XCTAssertEqual(plain.display.style, "Regular")
        XCTAssertEqual(plain.display.weight, 400)
        XCTAssertEqual(plain.display.postScript, "ArialMT")
        XCTAssertEqual(plain.text.family, "Georgia")
        let bold = try XCTUnwrap((model.fontsByFamily["Arial"] ?? []).first { $0.filePath.hasSuffix("Arial Bold.ttf") })
        model.typeSettings.update(model.settingsKey("display", "Arial"), job: "display") { $0.stylePath = bold.filePath }
        let tunedMade = await ExportSpec.make(model: model)
        let tuned = try XCTUnwrap(tunedMade)
        XCTAssertEqual(tuned.display.style, "Bold")
        XCTAssertEqual(tuned.display.weight, 700)
        XCTAssertEqual(tuned.display.postScript, "Arial-BoldMT")
        XCTAssertTrue(Exporters.css(tuned).contains("font-weight: 700;\n  src: local(\"Arial-BoldMT\")"))
    }

    func testExportIsOffWithAPlainReasonUntilBothFacesAreChosen() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = await makeModel(folder: dir)
        XCTAssertFalse(model.canExport)
        XCTAssertEqual(model.exportReason, "Pick a Display and a Text face to export")
        let none = await ExportSpec.make(model: model)
        XCTAssertNil(none)
        await model.choose("display", family: "Arial")
        XCTAssertFalse(model.canExport, "one face is not enough")
        await model.choose("reading", family: "Georgia")
        XCTAssertTrue(model.canExport)
        XCTAssertNil(model.exportReason)
    }

    // MARK: escaping

    func testABrandNameCannotCloseTheCommentOrBreakAString() {
        var spec = self.spec
        spec.brandName = "Evil */ .x { color: red } Co"
        spec.display.family = "Back\\slash \"Quote\""
        for out in [Exporters.css(spec), Exporters.theme(spec), Exporters.theme(spec, paper: true)] {
            // Every comment that opens also closes, and the injected rule never leaves the comment.
            let opens = out.components(separatedBy: "/*").count - 1
            let closes = out.components(separatedBy: "*/").count - 1
            XCTAssertEqual(opens, closes, out)
            XCTAssertTrue(out.contains("Evil * / .x { color: red } Co"), "the name stays inside the comment")
        }
        // The family inside a quoted string: the backslash and the quote are escaped.
        XCTAssertEqual(Exporters.quoted("Back\\slash \"Quote\""), "\"Back\\\\slash \\\"Quote\\\"\"")
        XCTAssertEqual(Exporters.quoted("a\nb"), "\"a\\a b\"")
        XCTAssertTrue(Exporters.css(spec).contains("font-family: \"Back\\\\slash \\\"Quote\\\"\";"))
    }

    func testThePNGNeverOverwritesAFileThatIsThere() {
        let taken: Set<String> = ["/t/Acme.png", "/t/Acme 2.png"]
        let free = SpecPage.freeURL(URL(fileURLWithPath: "/t/Acme.png"), exists: { taken.contains($0.path) })
        XCTAssertEqual(free.path, "/t/Acme 3.png")
        XCTAssertEqual(SpecPage.freeURL(URL(fileURLWithPath: "/t/Other.png"), exists: { taken.contains($0.path) }).path, "/t/Other.png")
    }

    func testTheSpecPageKeepsAnExistingPNG() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = await makeModel(folder: dir)
        await model.choose("display", family: "Georgia")
        await model.choose("reading", family: "Arial")
        let made = await ExportSpec.make(model: model)
        let spec = try XCTUnwrap(made)
        let d = try XCTUnwrap(model.displayFamily), r = try XCTUnwrap(model.readingFamily)
        let base = URL(fileURLWithPath: NSTemporaryDirectory() + "fontdrop-keep-\(UUID().uuidString)")
        let existing = base.appendingPathExtension("png")
        try Data("mine".utf8).write(to: existing)
        let out = try SpecPage.write(spec: spec, displayFace: model.face("display", d), textFace: model.face("reading", r), base: base)
        XCTAssertEqual(try Data(contentsOf: existing), Data("mine".utf8), "the file that was there is untouched")
        XCTAssertNotEqual(out.png, existing)
        XCTAssertEqual(Array(try Data(contentsOf: out.png).prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        for url in [existing, out.pdf, out.png] { try? FileManager.default.removeItem(at: url) }
    }

    func testTheSpecPageWritesAPDFAndAPNG() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = await makeModel(folder: dir)
        await model.choose("display", family: "Georgia")
        await model.choose("reading", family: "Arial")
        let made = await ExportSpec.make(model: model)
        let spec = try XCTUnwrap(made)
        let d = try XCTUnwrap(model.displayFamily), r = try XCTUnwrap(model.readingFamily)
        let base = URL(fileURLWithPath: NSTemporaryDirectory() + "fontdrop-spec-\(UUID().uuidString)")
        let out = try SpecPage.write(spec: spec, displayFace: model.face("display", d), textFace: model.face("reading", r), base: base)
        let pdf = try Data(contentsOf: out.pdf), png = try Data(contentsOf: out.png)
        XCTAssertEqual(String(decoding: pdf.prefix(5), as: UTF8.self), "%PDF-")
        XCTAssertGreaterThan(pdf.count, 3000)
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let image = try XCTUnwrap(NSImage(data: png))
        XCTAssertEqual(image.representations.first?.pixelsWide, Int(SpecPageView.width) * 2, "2x of the 720 pt page")
        try? FileManager.default.removeItem(at: out.pdf); try? FileManager.default.removeItem(at: out.png)
    }
}
