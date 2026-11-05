import AppKit
import SwiftUI

/// The one-page pair spec: the faces with their foundry and license, the scale at its real sizes, the tuning, the brand
/// colors if set, a sample block and the license list. Light, solid, no glass: it prints.
/// React: a fixed-width article rendered to PDF with the print stylesheet.
struct SpecPageView: View {
    let spec: ExportSpec
    let displayFace: FaceSpec
    let textFace: FaceSpec

    static let width: CGFloat = 720
    private let pad: CGFloat = 40
    private let labelWidth: CGFloat = 128
    private let theme = Theme.light

    private var sizes: SetSizes {
        SetSizes(body: spec.bodySize, ratio: spec.ratio, measure: spec.measure, lineHeight: spec.bodyLineHeight)
    }
    private var specimenWidth: CGFloat { Self.width - 2 * pad - labelWidth - 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 22)
            HStack(alignment: .top, spacing: 16) {
                faceCard(spec.display, face: displayFace)
                faceCard(spec.text, face: textFace)
            }
            .padding(.bottom, 26)
            section(Lexicon.Export.scaleTitle)
            ForEach(ScaleStep.stageOrder) { row($0) }
            Text(Lexicon.Export.scaleNote).moduleLabel().padding(.top, 8).padding(.bottom, 26)
            section(Lexicon.Export.tuningTitle)
            tuning.padding(.bottom, 26)
            if let colors = spec.colors {
                section(Lexicon.Export.colorsTitle)
                colorRow(colors).padding(.bottom, 26)
            }
            section(Lexicon.Export.sampleTitle)
            sample.padding(.bottom, 26)
            section(Lexicon.Export.licenseTitle)
            ForEach([spec.display, spec.text], id: \.role) { licenseRow($0) }
        }
        .padding(pad)
        .frame(width: Self.width, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(theme.textPrimary.color)
        .environment(\.theme, theme)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Lexicon.Export.specKicker).moduleLabel()
            Text(spec.brandName).font(.system(size: 28, weight: .semibold))
            Text(Lexicon.Export.specSubtitle(display: spec.display.family, text: spec.text.family))
                .font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
        }
    }

    private func section(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(theme.sliderTrack.color).frame(height: 1)
            Text(title).moduleLabel()
        }
        .padding(.bottom, 10)
    }

    private func faceCard(_ f: ExportFace, face: FaceSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(f.role).moduleLabel()
            FaceText(face: face, text: f.family, ratio: 26 / max(face.settings.size, 1), useLineHeight: false)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(f.style).font(.system(size: 12, weight: .semibold))
            Text(f.foundry ?? Lexicon.Export.noFoundry).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            Text(Exporters.licenseFlag(f)).font(.system(size: 11, weight: f.isTrial ? .semibold : .regular))
                .foregroundStyle(f.isTrial ? Color(red: 0.70, green: 0.17, blue: 0.08) : theme.textSecondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.sliderTrack.color, lineWidth: 1))
    }

    private func row(_ step: ScaleStep) -> some View {
        let pt = spec.size(step)
        let f = step.isDisplayFace ? displayFace : textFace
        let who = step.isDisplayFace ? spec.display : spec.text
        let plan = SetRowPlan.make(step: step, pt: pt, face: f, text: step.sampleLine, specWidth: Double(specimenWidth), sizes: sizes)
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.sliderTrack.color).frame(height: 1)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(step.label) \u{00B7} \(Lexicon.SetScreen.points(pt))").moduleLabel()
                    if step == .body {
                        Text("\(spec.measure) \(Lexicon.SetScreen.measureUnit) \u{00B7} " + String(format: "%.2f", spec.bodyLineHeight)).moduleLabel()
                    } else {
                        Text(String(format: "%.2f", spec.lineHeight(step))).moduleLabel()
                    }
                    Text(who.family).font(.system(size: 10)).foregroundStyle(theme.textSecondary.color)
                }
                .frame(width: labelWidth, alignment: .leading).padding(.top, 4)
                FaceText(face: f, text: step.sampleLine, ratio: CGFloat(plan.drawnPt / max(f.settings.size, 1)), trackBias: 0, leading: plan.leading)
                    .lineLimit(step == .body ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: CGFloat(plan.drawnWidth ?? Double(specimenWidth)), alignment: .leading)
            }
            .padding(.vertical, 12)
        }
    }

    private var tuning: some View {
        VStack(alignment: .leading, spacing: 10) {
            tuningLine(Lexicon.Export.scaleLine(body: spec.bodySize, ratio: spec.ratio))
            tuningLine(Lexicon.Export.textLine(measure: spec.measure, lineHeight: spec.bodyLineHeight))
            ForEach([spec.display, spec.text], id: \.role) { f in
                tuningLine(Lexicon.Export.faceTuning(role: f.role, trim: f.trim, tracking: f.tracking, opticalSize: f.opticalSize))
            }
        }
    }

    private func tuningLine(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
    }

    private func colorRow(_ c: ExportSpec.Colors) -> some View {
        HStack(spacing: 18) {
            ForEach([(Lexicon.Export.colorBackground, c.background), (Lexicon.Export.colorText, c.text), (Lexicon.Export.colorAccent, c.accent)], id: \.0) { item in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: item.1))
                        .frame(width: 28, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.sliderTrack.color, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.0).moduleLabel()
                        Text(item.1).font(.system(size: 12, design: .monospaced))
                    }
                }
            }
        }
    }

    /// A headline and a paragraph in the pair, on the brand's colors when it has them.
    private var sample: some View {
        let bg = spec.colors.map { Color(hex: $0.background) } ?? Color.white
        let ink = spec.colors.map { Color(hex: $0.text) } ?? theme.textPrimary.color
        let accent = spec.colors.map { Color(hex: $0.accent) } ?? theme.textSecondary.color
        let head = SetRowPlan.make(step: .h1, pt: spec.size(.h1), face: displayFace, text: spec.brandName, specWidth: Double(Self.width - 2 * pad - 48), sizes: sizes)
        let bodyPlan = SetRowPlan.make(step: .body, pt: spec.size(.body), face: textFace, text: ScaleStep.body.sampleLine,
                                       specWidth: Double(Self.width - 2 * pad - 48), sizes: sizes)
        return VStack(alignment: .leading, spacing: 14) {
            Text(spec.display.role.uppercased() + " + " + spec.text.role.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(accent)
            FaceText(face: displayFace, text: Lexicon.SetScreen.h1Line, ratio: CGFloat(head.drawnPt / max(displayFace.settings.size, 1)), leading: head.leading)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            FaceText(face: textFace, text: ScaleStep.body.sampleLine, ratio: CGFloat(bodyPlan.drawnPt / max(textFace.settings.size, 1)), leading: bodyPlan.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: CGFloat(bodyPlan.drawnWidth ?? Double(Self.width - 2 * pad - 48)), alignment: .leading)
        }
        .foregroundStyle(ink)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.sliderTrack.color, lineWidth: 1))
    }

    private func licenseRow(_ f: ExportFace) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(f.role) \u{00B7} \(f.family), \(f.style)").font(.system(size: 12, weight: .semibold))
            Text(f.foundry ?? Lexicon.Export.noFoundry).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            Text(f.foundryURL ?? Lexicon.Export.noLink).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
            Text(Exporters.licenseFlag(f)).font(.system(size: 12, weight: f.isTrial ? .semibold : .regular))
        }
        .padding(.bottom, 12)
    }
}

private extension Color {
    init(hex: String) {
        let h = HexColor(hex: hex) ?? HexColor(r: 0, g: 0, b: 0)
        self.init(red: h.r, green: h.g, blue: h.b)
    }
}

@MainActor
enum SpecPage {
    /// Writes `<base>.pdf` and `<base>.png`. The PDF is vector, one page as tall as the content. The PNG is 2x.
    @discardableResult
    static func write(spec: ExportSpec, displayFace: FaceSpec, textFace: FaceSpec, base: URL) throws -> (pdf: URL, png: URL) {
        let renderer = ImageRenderer(content: SpecPageView(spec: spec, displayFace: displayFace, textFace: textFace))
        renderer.proposedSize = ProposedViewSize(width: SpecPageView.width, height: nil)
        let pdf = base.deletingPathExtension().appendingPathExtension("pdf")
        let png = base.deletingPathExtension().appendingPathExtension("png")
        var wrote = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(pdf as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            wrote = true
        }
        renderer.scale = 2
        guard wrote, let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "FontDrop", code: 10, userInfo: [NSLocalizedDescriptionKey: "Could not draw the spec page."])
        }
        try data.write(to: png)
        return (pdf, png)
    }
}
