import SwiftUI

/// Poster B, Specimen. Tests: one glyph pair at poster size, the weight ramp the family really has,
/// and the full character set.
struct PosterSpecimen: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    /// Light to heavy, one row per distinct weight the family offers. A family with two weights shows two rows.
    private var ramp: [(label: String, face: FaceSpec)] {
        var seen = Set<Int>()
        var out: [(String, FaceSpec)] = []
        for (_, w) in TemplateCopy.specimenRamp {
            let face = ctx.display.weighted(w)
            let actual = Int(face.weightValue.rounded())
            guard seen.insert(actual).inserted else { continue }
            out.append(("\(Self.weightName(Double(actual))) \(actual)", face))
        }
        return out
    }

    private static func weightName(_ w: Double) -> String {
        switch w {
        case ..<150: "Thin"
        case ..<250: "Extralight"
        case ..<350: "Light"
        case ..<450: "Regular"
        case ..<550: "Medium"
        case ..<650: "Semibold"
        case ..<750: "Bold"
        case ..<850: "Extrabold"
        default: "Black"
        }
    }

    var body: some View {
        Board(background: p.background.color, height: 800) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 0)
                glyphs
                Spacer(minLength: 0)
                weights
                Spacer(minLength: 0)
                footer
            }
            .padding(32)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ctx.reading(ctx.display.familyName, 13, lh: 1.23, weight: 600)
            Spacer()
            ctx.reading("with \(ctx.body.familyName)", 13, lh: 1.23)
            Spacer()
            ctx.reading(TemplateCopy.specimenSub, 13, lh: 1.23, color: p.accent)
        }
        .lineLimit(1)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Hairline(color: p.text) }
    }

    private var glyphs: some View {
        HStack(alignment: .bottom) {
            ctx.display(TemplateCopy.specimenGlyphs, 320, track: -0.04, lh: 0.78)
                .lineLimit(1).minimumScaleFactor(0.25)
            Spacer(minLength: 0)
            ctx.display(TemplateCopy.specimenAmp, 120, lh: 0.92, italic: true)
                .lineLimit(1).minimumScaleFactor(0.25)
                .padding(.bottom, 20)
        }
    }

    private var weights: some View {
        VStack(spacing: 4) {
            ForEach(Array(ramp.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ctx.reading(row.label, 12, lh: 1.33, color: p.secondary)
                        .frame(width: 104, alignment: .leading)
                    ctx.display(TemplateCopy.specimenLine, 30, lh: 1.2, face: row.face)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 24) {
            ctx.reading(TemplateCopy.specimenSet, 13, lh: 1.46)
                .frame(maxWidth: .infinity, alignment: .leading)
            ctx.reading(TemplateCopy.specimenNote, 13, lh: 1.46, color: p.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Hairline(color: p.rule) }
    }
}
