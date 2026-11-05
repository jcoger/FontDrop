import CoreText
import SwiftUI

/// The fit rule for fixed-size boards (posters). The playground's Size slider scales every display size on the
/// board (Size 14 to 120). A poster is a fixed sheet, so past some size the type would run off the bottom.
/// The rule: shrink the display type, as one factor for the whole board, until the board's content fits its height.
/// Never clip, and never split a word (the width rule in `FitWords` still runs inside each line).
///
/// React: a `scale` custom property on the board, computed from the content's heights and the board height, that
/// every display size is multiplied by.
struct FitItem {
    let text: String
    /// Size on the 600-wide board at playground Size 40.
    let px: CGFloat
    /// Line height as a multiple of the size.
    let lh: Double
    /// The width the text wraps in. Nil means one line.
    var width: CGFloat?
    /// The most lines the template allows (a `lineLimit`). Nil means as many as it wraps to.
    var maxLines: Int?
    var tracking: Double = 0
    /// For a single line that is never wrapped: the width it must stay within, so the word is never cut off.
    var fitWidth: CGFloat?
}

/// A limit that is not about the whole board: "this text must fit in a box of this height".
struct FitBox {
    let items: [FitItem]
    /// Height available to those items, in board px.
    let height: CGFloat
}

enum PosterFit {
    static let floor: CGFloat = 0.1
    /// Leave a little air so a rounding error never touches the edge.
    static let margin: CGFloat = 0.97

    /// The factor that makes `display` (height at factor 1) fit in `height` next to `fixed` (height that does not
    /// scale). Never above 1 and never below the floor.
    static func scale(height: CGFloat, fixed: CGFloat, display: CGFloat) -> CGFloat {
        guard display > 0 else { return 1 }
        let s = (height - fixed) / display * margin
        return min(1, max(floor, s))
    }
}

extension PairContext {
    /// Playground Display size as a multiple of the size the boards were drawn at (40).
    var displayScale: CGFloat { CGFloat(display.settings.size) / Self.displayBaseSize }
    /// Playground Reading size as a multiple of the size the boards were drawn at (15).
    var readingScale: CGFloat { CGFloat(body.settings.size) / Self.readingBaseSize }

    /// Height of `item` on the board at the current playground size, shrunk by `s`, with its wrapped line count.
    private func height(of item: FitItem, at s: CGFloat) -> CGFloat {
        var lines = 1
        if let width = item.width, let font = FontLoader.shared.styledFont(display, ratio: item.px * s / Self.displayBaseSize) {
            lines = TightLines.lines(item.text, font: font,
                                     tracking: CGFloat(display.settings.tracking + item.tracking) * CTFontGetSize(font),
                                     width: width).count
        }
        if let cap = item.maxLines { lines = min(lines, cap) }
        return item.px * CGFloat(item.lh) * CGFloat(lines) * displayScale * s
    }

    /// This context with `fit` set so a fixed-height board holds its content.
    /// `items` is the display text in the flow, `fixed` the height of everything that does not scale (padding,
    /// gaps, Reading text), `boxes` any text that must fit its own box (a sign, a block).
    func fitted(height boardHeight: CGFloat, fixed: CGFloat, items: [FitItem], boxes: [FitBox] = []) -> PairContext {
        var c = self
        c.fit = 1
        // Line counts change as the type shrinks, so settle on the factor over a few passes.
        var s: CGFloat = 1
        for _ in 0..<4 {
            let flow = items.reduce(0) { $0 + height(of: $1, at: s) } / max(s, 0.0001)
            var next = PosterFit.scale(height: boardHeight, fixed: fixed, display: flow)
            for item in items {
                // The width rule: a line that cannot wrap shrinks until its widest word fits.
                guard let limit = item.fitWidth,
                      let font = FontLoader.shared.styledFont(display, ratio: item.px / Self.displayBaseSize) else { continue }
                let w = FitWords.widestWord(item.text, font: font, trackingEm: display.settings.tracking + item.tracking)
                if w > 0 { next = min(next, max(PosterFit.floor, limit / w * PosterFit.margin)) }
            }
            for box in boxes {
                let h = box.items.reduce(0) { $0 + height(of: $1, at: s) } / max(s, 0.0001)
                next = min(next, PosterFit.scale(height: box.height, fixed: 0, display: h))
            }
            if abs(next - s) < 0.005 { s = next; break }
            s = next
        }
        c.fit = s
        return c
    }
}
