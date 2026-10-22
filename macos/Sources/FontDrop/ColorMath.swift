import Foundation

// Pure color math for the Colors control and the templates. No SwiftUI here, so it is easy to test.
// Everything is sRGB, 0...1 per channel.

/// An sRGB color. Codable as a "#RRGGBB" string so the saved JSON stays readable.
struct HexColor: Equatable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1); self.g = min(max(g, 0), 1); self.b = min(max(b, 0), 1)
    }

    /// Accepts 3 or 6 hex digits, with or without "#". Anything else is nil.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 3 || s.count == 6, s.allSatisfy(\.isHexDigit) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((value >> 16) & 0xff) / 255, g: Double((value >> 8) & 0xff) / 255, b: Double(value & 0xff) / 255)
    }

    /// "#RRGGBB", uppercase.
    var hex: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    // MARK: HSB (all three 0...1; hue 0 = red, wraps at 1)

    var hsb: (h: Double, s: Double, b: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    init(h: Double, s: Double, b: Double) {
        let hue = (h - h.rounded(.down)) * 6, sat = min(max(s, 0), 1), val = min(max(b, 0), 1)
        let c = val * sat, x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1)), m = val - c
        let (r, g, bl): (Double, Double, Double)
        switch Int(hue) {
        case 0: (r, g, bl) = (c, x, 0)
        case 1: (r, g, bl) = (x, c, 0)
        case 2: (r, g, bl) = (0, c, x)
        case 3: (r, g, bl) = (0, x, c)
        case 4: (r, g, bl) = (x, 0, c)
        default: (r, g, bl) = (c, 0, x)
        }
        self.init(r: r + m, g: g + m, b: bl + m)
    }

    // MARK: WCAG 2

    /// Relative luminance, WCAG 2.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Contrast ratio from 1 to 21. Order does not matter.
    func contrast(with other: HexColor) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    // MARK: Mixing

    /// This color with `amount` (0...1) of `other` mixed in. Straight sRGB blend, like opacity over a solid.
    func mixed(with other: HexColor, amount: Double) -> HexColor {
        let t = min(max(amount, 0), 1)
        return HexColor(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// Whichever of `options` has the most contrast with this color.
    func mostReadable(of options: [HexColor]) -> HexColor {
        options.max { contrast(with: $0) < contrast(with: $1) } ?? self
    }
}

extension HexColor: Codable {
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let c = HexColor(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad hex \(s)"))
        }
        self = c
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

/// The three WCAG bands the Colors popover reports.
enum ContrastBand: Equatable {
    case fine, largeOnly, tooLow

    init(ratio: Double) { self = ratio >= 4.5 ? .fine : ratio >= 3 ? .largeOnly : .tooLow }

    /// "19.8" for display. Never rounds up across a band edge, so 4.49 reads 4.4 and never "4.5 Large text only".
    static func display(_ ratio: Double) -> String {
        var r = (ratio * 10).rounded() / 10
        if ratio < 4.5, r >= 4.5 { r = 4.4 }
        if ratio < 3, r >= 3 { r = 2.9 }
        return String(format: "%.1f", r)
    }
}
