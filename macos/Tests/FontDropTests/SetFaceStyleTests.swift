import FontDropCore
import XCTest
@testable import FontDrop

/// Round R6, scope 0: Set draws each face in the style the designer chose.
@MainActor
final class SetFaceStyleTests: XCTestCase {
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

    /// Set draws each face with the style the designer chose (the same store the Display inspector's Style picker writes),
    /// and the family's default style when nothing was chosen. Export reads the same face.
    func testSetAndExportResolveTheChosenStyleAndFallBackToTheDefault() async throws {
        let dir = try fixtureFolder()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let model = await makeModel(folder: dir)
        await model.choose("display", family: "Arial")
        await model.choose("reading", family: "Georgia")
        let arial = try XCTUnwrap(model.familyByName["Arial"])
        let georgia = try XCTUnwrap(model.familyByName["Georgia"])

        // Nothing chosen: the family's default style, drawn by Set and named in its row.
        XCTAssertEqual(model.face("display", arial).resolvedPath, arial.filePath)
        XCTAssertEqual(model.styleLabel(model.face("display", arial), family: "Arial"), "Regular")

        // Bold chosen for Display, as the Style picker does: Set, the picker reads it.
        let bold = try XCTUnwrap((model.fontsByFamily["Arial"] ?? []).first { $0.filePath.hasSuffix("Arial Bold.ttf") })
        model.typeSettings.update(model.settingsKey("display", "Arial"), job: "display") { $0.stylePath = bold.filePath }
        let chosen = model.face("display", arial)
        XCTAssertEqual(chosen.resolvedPath, bold.filePath, "Set's face is the chosen style")
        XCTAssertEqual(model.styleLabel(chosen, family: "Arial"), "Bold")
        XCTAssertEqual(model.face("reading", georgia).resolvedPath, georgia.filePath, "the Text face is untouched")
        XCTAssertEqual(Lexicon.SetScreen.faceAndStyle("Arial", "Bold"), "Arial \u{00B7} Bold")
    }

}
