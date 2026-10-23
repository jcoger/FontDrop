import SwiftUI

/// Poster D, Blocks. Tests: the Display face at poster size over blocks of flat color, and small labels in
/// the Reading face on each of them. The blocks come from the accent plus four fixed hues pulled toward it.
/// On the Bone preset this is the Paper board.
struct PosterBlocks: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    /// The fit rule (PosterFit.swift): the big word shrinks so the blocks keep room, and the text in the
    /// Spring and sign blocks shrinks until it fits its block.
    init(ctx base: PairContext) {
        let r = base.readingScale
        let word = FitItem(text: TemplateCopy.blocksWord, px: 158, lh: 0.99, tracking: -0.055)
        let spring = TemplateCopy.blocksSpring.map { FitItem(text: $0, px: 34, lh: 1.06, width: 218) }
        let sign = TemplateCopy.blocksSign.map { FitItem(text: $0, px: 28, lh: 1.0, width: 262) }
        // Padding 56, the label row, two gaps, and the least the right column needs (open block, sign, bar).
        let above = 56 + 16 * r + 24
        let first = base.fitted(height: 750, fixed: above + 300, items: [word],
                                boxes: [FitBox(items: sign, height: 120 - 32)])
        // The Spring block is whatever height is left under the word. Its text must fit that, with its padding.
        let region = 750 - above - 158 * 0.99 * first.displayScale * first.fit
        ctx = base.fitted(height: 750, fixed: above + 300, items: [word],
                          boxes: [FitBox(items: sign, height: 120 - 32), FitBox(items: spring, height: max(region - 32, 40))])
    }

    var body: some View {
        let blocks = p.blocks
        Board(background: p.background.color, height: 750) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ctx.reading(TemplateCopy.blocksTop, 12, lh: 1.33)
                        Spacer()
                        ctx.reading("\(ctx.display.familyName) with \(ctx.body.familyName)", 12, lh: 1.33).lineLimit(1)
                    }
                    ctx.posterLine(TemplateCopy.blocksWord, 158, track: -0.055, lh: 0.99)
                }
                HStack(spacing: 0) {
                    spring(blocks[0])
                    VStack(spacing: 0) {
                        open(blocks[1], circle: blocks[2])
                        sign(blocks[3])
                        Rectangle().fill(blocks[4].color).frame(height: 28)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(28)
        }
    }

    private func spring(_ color: HexColor) -> some View {
        let ink = p.onColor(color)
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TemplateCopy.blocksSpring, id: \.self) { ctx.display($0, 34, lh: 1.06, italic: true, color: ink, width: 218) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(color.color)
        .frame(width: (Board<EmptyView>.designWidth - 56) * 0.46)
    }

    private func open(_ color: HexColor, circle: HexColor) -> some View {
        HStack(alignment: .top) {
            Circle().fill(circle.color).frame(width: 120, height: 120)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(TemplateCopy.blocksOpen, id: \.self) { ctx.reading($0, 12, lh: 1.33, color: p.onColor(color)) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.color)
    }

    private func sign(_ color: HexColor) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(TemplateCopy.blocksSign, id: \.self) { ctx.display($0, 28, lh: 1.0, color: p.onColor(color), width: 262) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 120, alignment: .bottomTrailing)
        .background(color.color)
    }
}
