import AppKit
import SwiftUI

/// System, Light or Dark. The one setting for the whole app: the View menu and the sidebar's sun/moon button both write it.
/// System (the default) follows macOS. Light and Dark pin the app's appearance, which flows into every window and into
/// SwiftUI's color scheme, so `ThemeRoot` picks the matching theme with no other change.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    static let key = "appearance"

    var title: String {
        switch self {
        case .system: Lexicon.R9.appearanceSystem
        case .light: Lexicon.R9.appearanceLight
        case .dark: Lexicon.R9.appearanceDark
        }
    }

    /// What `NSApp.appearance` is set to. Nil means follow the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func apply() { NSApp?.appearance = nsAppearance }

    /// The sun/moon button flips between Light and Dark, from what is showing now.
    func toggled(showingDark: Bool) -> AppearanceChoice { showingDark ? .light : .dark }
}

/// View > Appearance: System, Light, Dark, with a check beside the one in use.
struct AppearanceMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu(Lexicon.R9.appearanceMenu) {
            ForEach(AppearanceChoice.allCases) { choice in
                Toggle(choice.title, isOn: Binding(get: { model.appearance == choice }, set: { if $0 { model.appearance = choice } }))
            }
        }
    }
}

/// A small sun or moon at the foot of the sidebar. Shows what the app looks like now; pressing it switches to the other.
struct AppearanceToggle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Button { model.appearance = model.appearance.toggled(showingDark: dark) } label: {
            Image(systemName: dark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 14))
                .foregroundStyle(theme.textPrimary.color)
                .frame(width: 40, height: 40)
                .pill()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(dark ? Lexicon.R9.switchToLight : Lexicon.R9.switchToDark)
        .accessibilityLabel(Lexicon.R9.appearanceAccessibility)
        .accessibilityValue(model.appearance.title)
    }
}
