import FontDropCore
import Foundation

/// What a Set row draws: the face with the style the designer chose, named in the row. Set reads the same saved
/// settings the Display inspector's Style picker writes (`AppModel.face`), so what the row says is what it shows.
extension AppModel {
    /// The library file behind the style a face draws in (a .ttf twin counts for its .otf).
    func styleFile(_ face: FaceSpec, family: String) -> FontFile? {
        let files = fontsByFamily[family] ?? []
        let path = face.resolvedPath
        return files.first { $0.filePath == path }
            ?? StylePathRepair.repaired(path, valid: files.map(\.filePath)).flatMap { fixed in files.first { $0.filePath == fixed } }
    }

    /// The style as the font names it ("Grand Heavy"); "Regular" when the library has no name for it.
    func styleLabel(_ face: FaceSpec, family: String) -> String {
        styleFile(face, family: family).map { StyleNames.label($0, family: family) } ?? "Regular"
    }
}

extension Lexicon.SetScreen {
    /// "Agrandir \u{00B7} Grand Heavy": the row says which style it draws.
    static func faceAndStyle(_ family: String, _ style: String) -> String { "\(family) \u{00B7} \(style)" }
}

/// The sample line for each step of the scale (board 04). Body is a paragraph.
extension ScaleStep {
    var sampleLine: String {
        switch self {
        case .display: Lexicon.SetScreen.displayLine
        case .h1: Lexicon.SetScreen.h1Line
        case .h2: Lexicon.SetScreen.h2Line
        case .h3: Lexicon.SetScreen.h3Line
        case .lead: Lexicon.SetScreen.leadLine
        case .body: SampleCopy.paragraphs.joined(separator: " ")
        case .caption: Lexicon.SetScreen.captionLine
        }
    }
}
