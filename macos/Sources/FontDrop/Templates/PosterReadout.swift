import SwiftUI

/// Poster C, Readout. Tests: the playground itself. Each band prints the real values for the face it
/// shows (weight, italic, size, and tracking for the Reading band) as a small bar on that value's range.
struct PosterReadout: View {
    let ctx: PairContext
    private var p: TemplatePalette { ctx.palette }

    // The ranges the playground's sliders use (Playground.swift). Bars map a value onto its range.
    static let displaySize: ClosedRange<Double> = 14...120
    static let readingSize: ClosedRange<Double> = 9...40
    static let tracking: ClosedRange<Double> = -0.08...0.3

    /// Where `value` sits in `range`, 0...1.
    static func position(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        let displayItalic = ctx.display.italic() ?? ctx.display
        Board(background: p.field.color, height: 750) {
            VStack(alignment: .leading, spacing: 0) {
                band(face: ctx.display, size: ctx.display.settings.size, sizeRange: Self.displaySize, tracking: nil,
                     name: Lexicon.Readout.display) {
                    ctx.posterLine(TemplateCopy.readoutWord, 320, track: -0.05, lh: 0.82)
                }
                Spacer(minLength: 0)
                band(face: displayItalic, size: displayItalic.settings.size, sizeRange: Self.displaySize, tracking: nil,
                     name: Lexicon.Readout.displayItalic) {
                    ctx.display(TemplateCopy.readoutLine, 72, track: -0.02, lh: 1.0, italic: true, width: 552)
                        .lineLimit(2).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                band(face: ctx.body, size: ctx.body.settings.size, sizeRange: Self.readingSize,
                     tracking: ctx.body.settings.tracking, name: Lexicon.Readout.reading) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(TemplateCopy.readoutBody, id: \.self) {
                            ctx.reading($0, 15, lh: 1.4).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    /// One band: a row of bars on top, the sample under it.
    private func band<Sample: View>(face: FaceSpec, size: Double, sizeRange: ClosedRange<Double>, tracking: Double?,
                                    name: String, @ViewBuilder sample: () -> Sample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                bar(name == Lexicon.Readout.reading ? Lexicon.Readout.readingWeight(Int(face.weightValue.rounded())) : Lexicon.Readout.weight(Int(face.weightValue.rounded())), fill: face.weightPosition, color: p.accent)
                bar(Lexicon.Readout.italic(face.isItalic), fill: face.isItalic ? 1 : 0, color: p.text)
                if let tracking {
                    bar(Lexicon.Readout.tracking(tracking), fill: Self.position(tracking, in: Self.tracking), color: p.text)
                }
                bar(Lexicon.Readout.size(Int(size.rounded())), fill: Self.position(size, in: sizeRange), color: p.text,
                    trailing: true)
            }
            sample()
        }
    }

    private func bar(_ label: String, fill: Double, color: HexColor, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            ctx.reading(label.uppercased(), 10, track: 0.08, lh: 1.2, weight: 600)
                .lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(p.background.color)
                    Rectangle().fill(color.color).frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((fill * 100).rounded())) percent of the range")
    }
}
