import SwiftUI

/// The rules behind a number field, apart from the view so a test can pin them.
enum NumberFieldMath {
    /// Reads what was typed. Accepts a comma as the decimal mark and ignores a trailing unit ("12 pt", "1.4x", "0.02 em").
    /// Returns nil when no number can be read. The result is clamped to `range`.
    static func parse(_ text: String, range: ClosedRange<Double>) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        // Keep the leading number (sign, digits, one point); drop a unit after it.
        var kept = ""
        var seenPoint = false
        for (i, ch) in cleaned.enumerated() {
            if ch.isNumber { kept.append(ch) }
            else if ch == "." && !seenPoint { seenPoint = true; kept.append(ch) }
            else if (ch == "-" || ch == "+") && i == 0 { kept.append(ch) }
            else if ch == " " && kept.isEmpty { continue }
            else { break }
        }
        cleaned = kept
        guard let v = Double(cleaned), v.isFinite else { return nil }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    /// One step up or down, clamped, with float noise removed (0.1 + 0.2 is 0.3).
    static func stepped(_ value: Double, by step: Double, direction: Int, range: ClosedRange<Double>) -> Double {
        let raw = value + step * Double(direction)
        let rounded = (raw / step).rounded() * step
        let clean = (rounded * 1_000_000).rounded() / 1_000_000
        return min(max(clean, range.lowerBound), range.upperBound)
    }

    static func text(_ value: Double, decimals: Int) -> String { String(format: "%.\(decimals)f", value) }
}

/// A number you can type, with a minus and a plus. It sits beside a slider wherever a precise value matters (Body,
/// Measure, Line height, Trim, Tracking, optical size). It reads from the same value as the slider and writes
/// through the same `onChange`, so the two never disagree. Return or leaving the field commits. Escape puts the old
/// value back. The up and down arrows step it while it has focus. It is drawn on the control ground.
///
/// React: a controlled input[type=number] with its own draft string, committed on blur or Enter.
struct NumberField: View {
    @Environment(\.theme) private var theme
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var decimals = 0
    var unit: String?
    var enabled = true
    /// Shown instead of the number while the value is following Auto and has not been edited (optical size).
    var autoText: String?
    /// Following Auto: drawn dim, and bright once someone has set it.
    var dim = false
    let onChange: (Double) -> Void

    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $draft)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle((dim && !focused ? theme.textSecondary : theme.textPrimary).color)
            .focused($focused)
            .disabled(!enabled)
            .onSubmit { commit() }
            .onExitCommand { draft = shown; focused = false }
            .onKeyPress(.upArrow) { nudge(1); return .handled }
            .onKeyPress(.downArrow) { nudge(-1); return .handled }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .accessibilityLabel(label)
            .accessibilityValue(shown)
            .frame(width: 76, height: Metrics.inline)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.controlGround.color.opacity(focused || hovering ? 1 : 0)))
            .overlay { if focused { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.textPrimary.color.opacity(0.45), lineWidth: 1) } }
            .padding(.trailing, -6)                    // the digits, not the hover plate, sit on the lane
            .onHover { hovering = $0 }
            .onAppear { draft = shown }
            .onChange(of: value) { _, _ in if !focused { draft = shown } }
            .onChange(of: autoText) { _, _ in if !focused { draft = shown } }
    }

    /// What the field shows at rest.
    private var shown: String {
        if let autoText { return autoText }
        let n = NumberFieldMath.text(value, decimals: decimals)
        return unit.map { "\(n) \($0)" } ?? n
    }

    private func nudge(_ direction: Int) {
        guard enabled else { return }
        let next = NumberFieldMath.stepped(value, by: step, direction: direction, range: range)
        if next != value { onChange(next) }
        draft = NumberFieldMath.text(next, decimals: decimals) + (unit.map { " \($0)" } ?? "")
    }

    private func commit() {
        guard enabled else { return }
        if let v = NumberFieldMath.parse(draft, range: range), abs(v - value) > step / 1000 || autoText != nil && draft != autoText {
            onChange(v)
            draft = NumberFieldMath.text(v, decimals: decimals) + (unit.map { " \($0)" } ?? "")
        } else {
            draft = shown
        }
    }
}
