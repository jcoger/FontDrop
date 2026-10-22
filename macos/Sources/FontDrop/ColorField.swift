import AppKit
import SwiftUI

/// A color picker that lives inside a popover, modeled on react-colorful: a saturation and brightness
/// square, a hue strip, a hex field, an eyedropper, and rows of recent and preset colors.
/// SwiftUI's `ColorPicker` opens the floating system color panel. This one does not.
///
/// The color is kept as hue, saturation and brightness while you edit, so dragging the square down to
/// black does not lose the hue (a gray has no hue of its own). `onCommit` fires when an edit ends
/// (drag released, hex entered, swatch clicked), which is when the color joins the recent list.
///
/// Keyboard: the square and the strip take focus. Arrow keys move by 1 percent, with Shift by 10.
/// VoiceOver: each control has a label and a value, and the square and strip are adjustable.
struct ColorField: View {
    @Binding var color: HexColor
    var recents: [HexColor]
    var presets: [HexColor] = ColorField.presetColors
    var onCommit: (HexColor) -> Void = { _ in }

    @State private var hue = 0.0
    @State private var sat = 0.0
    @State private var val = 0.0
    @State private var hexText = ""
    @State private var hexInvalid = false
    @FocusState private var hexFocused: Bool
    @State private var sampler: NSColorSampler?

    /// The colors the four presets use, each once.
    static let presetColors: [HexColor] = {
        var seen = Set<HexColor>()
        return TemplatePalette.presets.flatMap { [$0.palette.background, $0.palette.text, $0.palette.accent] }
            .filter { seen.insert($0).inserted }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ColorArea(hue: hue, sat: $sat, val: $val, onChange: pushHSB, onEnd: commit)
                .frame(height: 140)
            HueStrip(hue: $hue, onChange: pushHSB, onEnd: commit)
                .frame(height: 14)
            hexRow
            if !recents.isEmpty { swatchRow(title: Lexicon.Colors.recent, colors: recents, label: Lexicon.Colors.recentLabel) }
            swatchRow(title: Lexicon.Colors.fromPresets, colors: presets, label: Lexicon.Colors.presetColorLabel)
        }
        .onAppear(perform: syncFromColor)
        .onChange(of: color) { _, new in
            // An outside change (a preset, an eyedropper pick): follow it. Our own edits already match.
            if HexColor(h: hue, s: sat, b: val).hex != new.hex { syncFromColor() }
        }
    }

    // MARK: Hex and eyedropper

    private var hexRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5).fill(color.color).frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
                    .accessibilityHidden(true)
                HStack(spacing: 2) {
                    Text("#").foregroundStyle(.secondary)
                    TextField(Lexicon.Colors.hexPlaceholder, text: $hexText)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .monospaced))
                        .focused($hexFocused)
                        .onChange(of: hexText) { _, new in applyHex(new) }
                        .onSubmit { commitHex() }
                        .onChange(of: hexFocused) { _, focused in if !focused { commitHex() } }
                        .accessibilityLabel(Lexicon.Colors.hexLabel)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.background.secondary))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(hexInvalid ? Color.orange : Color.secondary.opacity(0.25)))
                Button(action: pickFromScreen) { Image(systemName: "eyedropper") }
                    .buttonStyle(.bordered).controlSize(.regular)
                    .help(Lexicon.Colors.eyedropper)
                    .accessibilityLabel(Lexicon.Colors.eyedropper)
            }
            if hexInvalid {
                Label(Lexicon.Colors.hexInvalid, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func swatchRow(title: String, colors: [HexColor], label: @escaping (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                    Button { choose(c) } label: {
                        RoundedRectangle(cornerRadius: 5).fill(c.color)
                            .frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
                            .overlay { if c == color { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2) } }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label(c.hex))
                    .help(c.hex)
                }
            }
        }
    }

    // MARK: Changes

    private func syncFromColor() {
        let h = color.hsb
        hue = h.h; sat = h.s; val = h.b
        hexText = String(color.hex.dropFirst())
        hexInvalid = false
    }

    /// The square or the strip moved: rebuild the color from the three numbers.
    private func pushHSB() {
        let c = HexColor(h: hue, s: sat, b: val)
        color = c
        if !hexFocused { hexText = String(c.hex.dropFirst()) }
        hexInvalid = false
    }

    private func commit() { onCommit(color) }

    private func choose(_ c: HexColor) {
        color = c
        syncFromColor()
        onCommit(c)
    }

    /// Typing: a valid 3 or 6 digit value updates the color live. An invalid one waits and shows a hint.
    private func applyHex(_ text: String) {
        guard hexFocused else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { hexInvalid = false; return }
        if let c = HexColor(hex: trimmed) {
            hexInvalid = false
            color = c
            let h = c.hsb
            hue = h.h; sat = h.s; val = h.b
        } else {
            hexInvalid = trimmed.count >= 6 || trimmed.contains { !$0.isHexDigit && $0 != "#" }
        }
    }

    /// Enter or leaving the field: keep a valid color and show it in full, or go back to the current one.
    private func commitHex() {
        if let c = HexColor(hex: hexText) { color = c; onCommit(c) }
        hexText = String(color.hex.dropFirst())
        hexInvalid = false
    }

    private func pickFromScreen() {
        let s = NSColorSampler()
        sampler = s
        s.show { picked in
            Task { @MainActor in
                sampler = nil
                // The sampler returns the display's color space. Convert, or the hex would be off.
                guard let rgb = picked?.usingColorSpace(.sRGB) else { return }
                choose(HexColor(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent))
            }
        }
    }
}

// MARK: - Saturation and brightness square

private struct ColorArea: View {
    let hue: Double
    @Binding var sat: Double
    @Binding var val: Double
    let onChange: () -> Void
    let onEnd: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(HexColor(h: hue, s: 1, b: 1).color)
                Rectangle().fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                Rectangle().fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom))
                Thumb(color: HexColor(h: hue, s: sat, b: val).color)
                    .position(x: sat * w, y: (1 - val) * h)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    focused = true
                    sat = min(max(g.location.x / w, 0), 1)
                    val = 1 - min(max(g.location.y / h, 0), 1)
                    onChange()
                }
                .onEnded { _ in onEnd() })
        }
        .focusable()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { press in
            let step = press.modifiers.contains(.shift) ? 0.1 : 0.01
            switch press.key {
            case .leftArrow: sat = max(0, sat - step)
            case .rightArrow: sat = min(1, sat + step)
            case .upArrow: val = min(1, val + step)
            case .downArrow: val = max(0, val - step)
            default: return .ignored
            }
            onChange(); onEnd()
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(Lexicon.Colors.areaLabel)
        .accessibilityValue(Lexicon.Colors.areaValue(Int((sat * 100).rounded()), Int((val * 100).rounded())))
        .accessibilityAdjustableAction { direction in
            // Up and down change brightness. Saturation has its own custom actions below.
            val = min(max(val + (direction == .increment ? 0.05 : -0.05), 0), 1)
            onChange(); onEnd()
        }
        .accessibilityAction(named: "More saturated") { sat = min(sat + 0.05, 1); onChange(); onEnd() }
        .accessibilityAction(named: "Less saturated") { sat = max(sat - 0.05, 0); onChange(); onEnd() }
    }
}

// MARK: - Hue strip

private struct HueStrip: View {
    @Binding var hue: Double
    let onChange: () -> Void
    let onEnd: () -> Void
    @FocusState private var focused: Bool

    private static let stops = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { HexColor(h: $0, s: 1, b: 1).color }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: Self.stops, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.quaternary))
                Thumb(color: HexColor(h: hue, s: 1, b: 1).color).position(x: hue * w, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    focused = true
                    hue = min(max(g.location.x / w, 0), 1)
                    onChange()
                }
                .onEnded { _ in onEnd() })
        }
        .focusable()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { press in
            let step = press.modifiers.contains(.shift) ? 0.1 : 0.01
            switch press.key {
            case .leftArrow, .downArrow: hue = max(0, hue - step)
            case .rightArrow, .upArrow: hue = min(1, hue + step)
            default: return .ignored
            }
            onChange(); onEnd()
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(Lexicon.Colors.hueLabel)
        .accessibilityValue(Lexicon.Colors.hueValue(Int((hue * 360).rounded())))
        .accessibilityAdjustableAction { direction in
            hue = min(max(hue + (direction == .increment ? 0.02 : -0.02), 0), 1)
            onChange(); onEnd()
        }
    }
}

/// The round handle: a white ring around the color it sits on, with a hairline shadow so it reads on white.
private struct Thumb: View {
    let color: Color
    var body: some View {
        Circle().fill(color)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.35), radius: 1.5)
    }
}
