import SwiftUI

// Small pieces the templates share. Colors always come from the palette.

/// A one-point line across, in a palette color.
struct Hairline: View {
    let color: HexColor
    var weight: CGFloat = 1
    var body: some View { Rectangle().fill(color.color).frame(height: weight) }
}

/// A vertical line.
struct VLine: View {
    let color: HexColor
    var body: some View { Rectangle().fill(color.color).frame(width: 1) }
}

extension PairContext {
    /// "ESSAY · CRAFT": a small label in capitals, tracked open. Reading face, semibold.
    func label(_ text: String, _ px: CGFloat = 12, color: HexColor? = nil, weight: Double = 600,
               align: TextAlignment = .leading) -> some View {
        reading(text.uppercased(), px, track: 0.08, weight: weight, color: color ?? palette.text)
            .multilineTextAlignment(align)
    }

    /// A button: filled (text color field, background color label) or outlined / soft.
    func button(_ title: String, px: CGFloat = 14, filled: Bool, soft: Bool = false, radius: CGFloat? = nil,
                horizontal: CGFloat = 20, vertical: CGFloat = 12) -> some View {
        let shape = radius.map { AnyShape(RoundedRectangle(cornerRadius: $0)) } ?? AnyShape(Capsule())
        return reading(title, px, weight: 500, color: filled ? palette.background : palette.text)
            .padding(.horizontal, horizontal).padding(.vertical, vertical)
            .background(shape.fill(filled ? palette.text.color : soft ? palette.background.color : .clear))
            .overlay(shape.stroke(palette.rule.color, lineWidth: filled || soft ? 0 : 1))
    }
}
