import SwiftUI

/// The Set screen: today a plain specimen of the pair. Scale, measure and optical-size work is round R5.
struct SetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        let tick = model.fontTick
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 24) {
                    pairing("Display", model.displayFamily?.name)
                    pairing("Text", model.readingFamily?.name)
                }

                if let display = model.displayFamily {
                    FaceText(face: model.face("display", display), text: SampleCopy.displayHeadline, ratio: 1.3, tick: tick)
                        .lineLimit(3)
                } else {
                    Text("Choose a Display face to see it here.").foregroundStyle(.secondary)
                }
                if let reading = model.readingFamily {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(SampleCopy.paragraphs, id: \.self) { p in
                            FaceText(face: model.face("reading", reading), text: p, ratio: 1.1, tick: tick)
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                } else {
                    Text("Choose a Text face to see it here.").foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.stage.color)
        // The saved style (a heavy cut, say) may not be loaded yet. Without its file the text draws invisibly.
        .task(id: "\(model.displayFamily?.name ?? "")/\(model.readingFamily?.name ?? "")") {
            await model.preloadStyles(of: [model.displayFamily?.name, model.readingFamily?.name].compactMap { $0 })
        }
    }

    private func pairing(_ job: String, _ family: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(job).font(.caption).foregroundStyle(.secondary)
            Text(family ?? "None yet").font(.title3.weight(.semibold))
        }
    }
}
