import Foundation
import SwiftUI

/// The three colors a brand sets for the templates. Everything else is derived from them,
/// so a template never holds a raw color of its own.
struct TemplatePalette: Codable, Hashable, Sendable {
    var background: HexColor
    var text: HexColor
    var accent: HexColor

    static func hex(_ h: String) -> HexColor { HexColor(hex: h) ?? HexColor(r: 0, g: 0, b: 0) }

    static let paper = TemplatePalette(background: hex("FFFFFF"), text: hex("0A0A0A"), accent: hex("E5341D"))
    static let night = TemplatePalette(background: hex("101312"), text: hex("E8E8E4"), accent: hex("E5341D"))
    static let bone = TemplatePalette(background: hex("E9E6DC"), text: hex("0A0A0A"), accent: hex("2B5C93"))
    static let signal = TemplatePalette(background: hex("E5341D"), text: hex("0A0A0A"), accent: hex("FFFFFF"))

    struct Preset: Identifiable {
        let id: String
        let name: String
        let palette: TemplatePalette
    }

    static let presets: [Preset] = [
        Preset(id: "paper", name: "Paper", palette: .paper),
        Preset(id: "night", name: "Night", palette: .night),
        Preset(id: "bone", name: "Bone", palette: .bone),
        Preset(id: "signal", name: "Signal", palette: .signal),
    ]

    /// The preset these three colors match exactly, if any.
    var presetID: String? { Self.presets.first { $0.palette == self }?.id }

    // MARK: Derived colors. The mix amounts come from the Paper boards (#6B6B6B on white is 60% of the text color).

    /// Secondary text: the text color at reduced strength.
    var secondary: HexColor { background.mixed(with: text, amount: 0.6) }
    /// Third level text: captions, small print.
    var tertiary: HexColor { background.mixed(with: text, amount: 0.42) }
    /// Hairlines.
    var rule: HexColor { background.mixed(with: text, amount: 0.10) }
    /// A slightly tinted ground for UI surfaces that sit on the background.
    var ground: HexColor { background.mixed(with: text, amount: 0.045) }
    /// The readout poster's field: a visible step from the background.
    var field: HexColor { background.mixed(with: text, amount: 0.165) }
    /// Big ghost type behind other text.
    var ghost: HexColor { background.mixed(with: text, amount: 0.36) }

    /// Text on top of `color`: the text or background role, whichever reads better.
    func onColor(_ color: HexColor) -> HexColor { color.mostReadable(of: [text, background]) }

    /// Poster D: the accent, then four fixed hues each pulled 18% toward the accent so they sit with it.
    var blocks: [HexColor] {
        let fixed = ["E2B9A7", "B57E93", "D4452E", "7C7A1E"].map(Self.hex)
        return [accent] + fixed.map { $0.mixed(with: accent, amount: 0.18) }
    }

    // MARK: Contrast line

    var contrastRatio: Double { text.contrast(with: background) }
    var contrastBand: ContrastBand { ContrastBand(ratio: contrastRatio) }
}

extension HexColor {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

/// Which of the three roles a control edits.
enum ColorRole: String, CaseIterable, Identifiable {
    case background, text, accent
    var id: String { rawValue }
    var title: String {
        switch self { case .background: Lexicon.Colors.background; case .text: Lexicon.Colors.text; case .accent: Lexicon.Colors.accent }
    }
    var keyPath: WritableKeyPath<TemplatePalette, HexColor> {
        switch self { case .background: \.background; case .text: \.text; case .accent: \.accent }
    }
}
