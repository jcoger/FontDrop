import AppKit
import SwiftUI

// The Instrument look: one token layer. Values come from docs/design/2026-11-05-instrument-look.md.
// Views read `@Environment(\.theme)`. Only `Theme.resolve` looks at the color scheme.
//
// React: this is a design-token object chosen once at the root and passed down through context.

/// A color with its alpha kept, so the contrast test can composite it over what it sits on.
struct RGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ hex: UInt32, _ alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// This color painted over an opaque background.
    func over(_ bg: RGBA) -> RGBA {
        RGBA(r: r * a + bg.r * (1 - a), g: g * a + bg.g * (1 - a), b: b * a + bg.b * (1 - a), a: 1)
    }

    private init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }

    /// WCAG 2 relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG 2 contrast ratio between two opaque colors, unrounded.
    static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let hi = max(a.luminance, b.luminance), lo = min(a.luminance, b.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }
}

struct ShadowSpec: Equatable {
    var color: RGBA
    var radius: CGFloat
    var y: CGFloat
}

struct Theme {
    let isDark: Bool

    // The window behind the panels.
    let windowTop: RGBA, windowBottom: RGBA

    // Glass: a fill plus a rim, one material.
    let glassSidebar: RGBA, glassInspector: RGBA, glassBar: RGBA
    let rimTop: RGBA, rimRing: RGBA
    let panelShadow: [ShadowSpec], barShadow: [ShadowSpec]

    // Regions.
    let panelContent: RGBA
    let panelRing: RGBA?               // dark: inset ring on the content panel
    let stage: RGBA
    let templateCard: RGBA
    let templateCardShadow: [ShadowSpec]

    // Rows and controls.
    let selectList: RGBA, selectSidebar: RGBA
    let controlGround: RGBA            // menu pills
    let chipGround: RGBA               // chips

    // Screens (recessed).
    let screenFill: RGBA
    let screenInsetShadow: RGBA, screenInsetLight: RGBA

    // Text.
    let textPrimary: RGBA, textSecondary: RGBA
    let onPrimaryButton: RGBA          // text on the primary button (whose fill is textPrimary)

    // Red has one job: a live value.
    let signal: RGBA
    let signalGlow: [(radius: CGFloat, opacity: Double)]
    /// While a hand is on the dial: brighter and wider. Light keeps one tight halo.
    let signalGlowTurning: [(radius: CGFloat, opacity: Double)]

    // The dial.
    let dialArc: RGBA, dialStop: RGBA

    // Slider.
    let sliderTrack: RGBA, sliderFill: RGBA, sliderThumb: RGBA
    let rulerTick: RGBA

    // Dark mode only.
    let grainOpacity: Double

    static let dark = Theme(
        isDark: true,
        windowTop: RGBA(0x141416), windowBottom: RGBA(0x0D0D0E),
        glassSidebar: RGBA(0x232321, 0.72), glassInspector: RGBA(0x161614, 0.84), glassBar: RGBA(0x2A2A28, 0.78),
        rimTop: RGBA(0xFFFFFF, 0.10), rimRing: RGBA(0xFFFFFF, 0.045),
        panelShadow: [], barShadow: [],
        panelContent: RGBA(0x1C1C1B), panelRing: RGBA(0xFFFFFF, 0.035),
        stage: RGBA(0x111110),
        templateCard: RGBA(0xFFFFFF), templateCardShadow: [],
        selectList: RGBA(0x2C2C2A), selectSidebar: RGBA(0xFFFFFF, 0.10),
        controlGround: RGBA(0xFFFFFF, 0.07), chipGround: RGBA(0xFFFFFF, 0.07),
        screenFill: RGBA(0x0D0D0C),
        screenInsetShadow: RGBA(0x000000, 0.55), screenInsetLight: RGBA(0xFFFFFF, 0.05),
        textPrimary: RGBA(0xEDEBE5), textSecondary: RGBA(0xA5A29A),
        onPrimaryButton: RGBA(0x161615),
        signal: RGBA(0xE5341D),
        signalGlow: [(2, 0.90), (7, 0.45)],
        signalGlowTurning: [(3, 0.95), (10, 0.55)],
        dialArc: RGBA(0x3A3A37), dialStop: RGBA(0x77756F),
        sliderTrack: RGBA(0x2B2B29), sliderFill: RGBA(0xEDEBE5), sliderThumb: RGBA(0xEDEBE5),
        rulerTick: RGBA(0x5E5C57),
        grainOpacity: 0.07)

    static let light = Theme(
        isDark: false,
        windowTop: RGBA(0xE3E5EE), windowBottom: RGBA(0xEFEDF2),
        glassSidebar: RGBA(0xFFFFFF, 0.58), glassInspector: RGBA(0xFFFFFF, 0.58), glassBar: RGBA(0xFFFFFF, 0.72),
        rimTop: RGBA(0xFFFFFF, 0.95), rimRing: RGBA(0xFFFFFF, 0.60),
        panelShadow: [ShadowSpec(color: RGBA(0x1E2846, 0.10), radius: 14, y: 8), ShadowSpec(color: RGBA(0x1E2846, 0.08), radius: 1, y: 1)],
        barShadow: [ShadowSpec(color: RGBA(0x000000, 0.08), radius: 5, y: 2)],
        panelContent: RGBA(0xFFFFFF), panelRing: nil,
        stage: RGBA(0xF2F2F0),
        templateCard: RGBA(0xFFFFFF), templateCardShadow: [ShadowSpec(color: RGBA(0x000000, 0.10), radius: 1.5, y: 1)],
        selectList: RGBA(0xEAEAE7), selectSidebar: RGBA(0x000000, 0.07),
        controlGround: RGBA(0xF2F2F4), chipGround: RGBA(0x000000, 0.05),
        screenFill: RGBA(0xEFEFEC),
        screenInsetShadow: RGBA(0x000000, 0.10), screenInsetLight: RGBA(0xFFFFFF, 0.90),
        textPrimary: RGBA(0x1D1D1F), textSecondary: RGBA(0x5F5F64),
        onPrimaryButton: RGBA(0xFFFFFF),
        signal: RGBA(0xE5341D),
        signalGlow: [(1.5, 0.60)],
        signalGlowTurning: [(2.5, 0.70)],
        dialArc: RGBA(0xC4C2BC), dialStop: RGBA(0x8F8D87),
        sliderTrack: RGBA(0xDEDEDB), sliderFill: RGBA(0x1D1D1F), sliderThumb: RGBA(0xFFFFFF),
        rulerTick: RGBA(0xB8B6B0),
        grainOpacity: 0)

    /// The one place the color scheme is read.
    static func resolve(_ scheme: ColorScheme) -> Theme { scheme == .dark ? .dark : .light }

    // MARK: Text and background pairs (the contrast test walks these)

    struct Pair {
        let name: String
        let text: RGBA          // already opaque
        let background: RGBA    // already composited, opaque
    }

    /// Every text token on every ground it can sit on, composited over the layer beneath it.
    var textPairs: [Pair] {
        let base = windowTop
        let sidebar = glassSidebar.over(base)
        let inspector = glassInspector.over(base)
        let bar = glassBar.over(stage)
        let grounds: [(String, RGBA)] = [
            ("panel.content", panelContent),
            ("stage", stage),
            ("glass.sidebar", sidebar),
            ("glass.inspector", inspector),
            ("glass.bar", bar),
            ("select.list", selectList.over(panelContent)),
            ("select.sidebar", selectSidebar.over(sidebar)),
            ("control.ground on panel", controlGround.over(panelContent)),
            ("control.ground on inspector", controlGround.over(inspector)),
            ("chip.ground on inspector", chipGround.over(inspector)),
            ("chip.ground on panel", chipGround.over(panelContent)),
            ("screen.fill", screenFill),
        ]
        var out: [Pair] = []
        for (name, bg) in grounds {
            out.append(Pair(name: "text.primary on \(name)", text: textPrimary.over(bg), background: bg))
            out.append(Pair(name: "text.secondary on \(name)", text: textSecondary.over(bg), background: bg))
        }
        out.append(Pair(name: "text.on-primary-button on primary button", text: onPrimaryButton, background: textPrimary))
        return out
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.dark }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Resolves the theme from the color scheme once, at the root, and hands it down.
struct ThemeRoot<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content

    var body: some View {
        let theme = Theme.resolve(scheme)
        content
            .environment(\.theme, theme)
            .tint(theme.textPrimary.color)           // toggles, sliders and progress follow text.primary, not system blue
    }
}

// MARK: - Fonts: Doto (numbers on screens) and Geist Mono (small caps labels)

enum InstrumentFonts {
    private static var registered = false

    /// Makes the bundled OFL fonts available to this process. Safe to call twice.
    static func registerFonts() {
        guard !registered else { return }
        registered = true
        for name in ["Doto", "GeistMono"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static let wght: Int = 0x77676874       // the 'wght' axis tag

    private static func variable(_ family: String, size: CGFloat, weight: Double, fallback: NSFont) -> Font {
        let desc = NSFontDescriptor(fontAttributes: [
            .family: family,
            .variation: [wght: weight],
        ])
        if let font = NSFont(descriptor: desc, size: size), font.familyName == family { return Font(font) }
        return Font(fallback)
    }

    /// Doto Black, for numbers on screens only.
    static func doto(_ size: CGFloat) -> Font {
        variable("Doto", size: size, weight: 900, fallback: .monospacedDigitSystemFont(ofSize: size, weight: .bold))
    }

    /// Geist Mono regular, for small caps labels only.
    static func label(_ size: CGFloat = 10) -> Font {
        variable("Geist Mono", size: size, weight: 400, fallback: .monospacedSystemFont(ofSize: size, weight: .regular))
    }
}

/// "01 · WHY IT PAIRS": Geist Mono 10, tracking 0.14 em, upper case.
struct LabelStyle10: ViewModifier {
    @Environment(\.theme) private var theme
    var color: KeyPath<Theme, RGBA> = \.textSecondary

    func body(content: Content) -> some View {
        content.font(InstrumentFonts.label(10)).tracking(1.4).textCase(.uppercase).foregroundStyle(theme[keyPath: color].color)
    }
}

extension View {
    func moduleLabel(color: KeyPath<Theme, RGBA> = \.textSecondary) -> some View { modifier(LabelStyle10(color: color)) }
}

// MARK: - Surfaces

/// Glass: a fill plus a rim, one material. Dark has no drop shadow. Light has one soft tinted shadow.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.theme) private var theme
    let fill: KeyPath<Theme, RGBA>
    let shape: S
    var bar = false

    func body(content: Content) -> some View {
        let shadows = bar ? theme.barShadow : theme.panelShadow
        content
            .background(shape.fill(theme[keyPath: fill].color))
            .background { SystemGlass(shape: shape) }
            .overlay(
                shape.strokeBorder(theme.rimRing.color, lineWidth: 1)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [theme.rimTop.color, theme.rimTop.color.opacity(0)],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: bar ? 0.6 : 0.04)),
                    lineWidth: 1)
            )
            .compositingGroup()
            .modifier(ShadowStack(shadows: shadows))
    }
}

/// The system's own glass under the token fill: Liquid Glass on macOS 26, the thin material before it.
/// The token rim and fill sit on top, so the look stays the spec's and the material only adds depth.
private struct SystemGlass<S: InsettableShape>: View {
    let shape: S
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

private struct ShadowStack: ViewModifier {
    let shadows: [ShadowSpec]
    func body(content: Content) -> some View {
        shadows.reduce(AnyView(content)) { view, s in
            AnyView(view.shadow(color: s.color.color, radius: s.radius, x: 0, y: s.y))
        }
    }
}

extension View {
    func glass<S: InsettableShape>(_ fill: KeyPath<Theme, RGBA>, in shape: S, bar: Bool = false) -> some View {
        modifier(GlassSurface(fill: fill, shape: shape, bar: bar))
    }
}

/// A recessed screen: dark well with an inner top shadow and a lit bottom edge. Both themes.
struct RecessedScreen: ViewModifier {
    @Environment(\.theme) private var theme
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(theme.screenFill.color))
            .overlay(
                shape.strokeBorder(theme.screenInsetShadow.color, lineWidth: 3)
                    .blur(radius: 1.5).offset(y: 1.5)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape.strokeBorder(theme.screenInsetLight.color, lineWidth: 1)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: UnitPoint(x: 0.5, y: 0.7), endPoint: .bottom))
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func recessed(radius: CGFloat = 12) -> some View { modifier(RecessedScreen(radius: radius)) }
}

/// The neutral selection pill used by the Text list and the sidebar.
struct SelectionPill: View {
    @Environment(\.theme) private var theme
    let on: Bool
    var sidebar = false
    var radius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(on ? (sidebar ? theme.selectSidebar : theme.selectList).color : .clear)
    }
}

/// Dark-mode noise on the sidebar, content panel and inspector. Never on the stage or a specimen.
struct Grain: View {
    @Environment(\.theme) private var theme
    private static let tile: NSImage? = Bundle.main.url(forResource: "grain", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        if theme.grainOpacity > 0, let tile = Self.tile {
            Image(nsImage: tile)
                .resizable(resizingMode: .tile)
                .opacity(theme.grainOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The lit dot for a live value: lock light, scanning light. Hollow when `lit` is false.
struct SignalLight: View {
    @Environment(\.theme) private var theme
    let lit: Bool
    var size: CGFloat = 7

    var body: some View {
        ZStack {
            if lit {
                Circle().fill(theme.signal.color)
                    .modifier(Glow(layers: theme.signalGlow, color: theme.signal.color))
            } else {
                Circle().strokeBorder(theme.textSecondary.color, lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Glow: ViewModifier {
    let layers: [(radius: CGFloat, opacity: Double)]
    let color: Color
    func body(content: Content) -> some View {
        layers.reduce(AnyView(content)) { view, l in
            AnyView(view.shadow(color: color.opacity(l.opacity), radius: l.radius))
        }
    }
}

// MARK: - Controls

/// A menu or button pill on the control ground.
struct PillBackground: ViewModifier {
    @Environment(\.theme) private var theme
    var chip = false
    func body(content: Content) -> some View {
        content.background(Capsule().fill((chip ? theme.chipGround : theme.controlGround).color))
    }
}

extension View {
    func pill(chip: Bool = false) -> some View { modifier(PillBackground(chip: chip)) }
}

/// Primary action: text.primary fill, on-primary text. The one prominent button on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: .medium))
            .foregroundStyle(theme.onPrimaryButton.color)
            .padding(.horizontal, large ? 22 : 16).padding(.vertical, large ? 11 : 8)
            .background(Capsule().fill(theme.textPrimary.color.opacity(configuration.isPressed ? 0.8 : 1)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

/// A quiet button inside glass: the control ground.
struct GlassButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: large ? .medium : .regular))
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, large ? 22 : 14).padding(.vertical, large ? 11 : 8)
            .background(Capsule().fill(theme.controlGround.color.opacity(configuration.isPressed ? 0.6 : 1)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

/// Links are text.primary with an underline. No blue.
struct LinkButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .underline()
            .foregroundStyle(theme.textPrimary.color.opacity(configuration.isPressed ? 0.7 : 1))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == LinkButtonStyle {
    static var themeLink: LinkButtonStyle { LinkButtonStyle() }
}

/// A switch drawn from tokens: track on slider.track, lit track text.primary.
struct ThemeToggleStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? theme.sliderFill.color : theme.sliderTrack.color)
                    Circle().fill(configuration.isOn ? theme.panelContent.color : theme.sliderThumb.color)
                        .padding(2)
                }
                .frame(width: 30, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityElement()
            .accessibilityValue(configuration.isOn ? "on" : "off")
            .accessibilityAddTraits(.isButton)
        }
    }
}

extension ToggleStyle where Self == ThemeToggleStyle {
    static var theme: ThemeToggleStyle { ThemeToggleStyle() }
}
