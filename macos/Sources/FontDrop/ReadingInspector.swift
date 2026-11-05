import FontDropCore
import SwiftUI

/// The Text inspector, in the order the audit set: why it pairs, the Text playground (open),
/// the Display playground (collapsed). The shortlist and "Use for Text" live on the stage.
struct ReadingInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selected = model.candidate(model.selectedCandidate)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c = selected {
                    header(c)
                    ScaleSection(family: c.family, fallbackPath: c.filePath)
                    if model.displayFamily != nil { why(c) }
                    playgrounds(c)
                } else {
                    Text(Lexicon.Reading.pickOne).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func header(_ c: Candidate) -> some View {
        let isCurrent = model.chosen(.reading) == c.family
        return VStack(alignment: .leading, spacing: 2) {
            Text(c.family).font(.title3.weight(.semibold))
            Text(isCurrent ? Lexicon.Reading.currentTitle : Lexicon.Reading.candidateTitle)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func inspectorXHeightNote(_ c: Candidate) -> String? {
        guard let display = model.displayFamily else { return nil }
        let body = model.familyByName[c.family].map { model.face("reading", $0) }
            ?? FaceSpec(path: c.filePath, settings: .defaults(job: "reading"))
        return measuredXHeightNote(display: model.face("display", display).resolvedPath, candidate: body.resolvedPath)
    }

    /// Every piece of evidence with its sources: the technical detail the list rows leave out.
    private func why(_ c: Candidate) -> some View {
        InspectorSection(title: Lexicon.whyItPairs) {
            if c.evidence.isEmpty {
                Text("The engine measured nothing notable.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(c.evidence.enumerated()), id: \.offset) { i, e in
                if i > 0 { Divider().padding(.vertical, 6) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: symbol(e)).font(.caption).foregroundStyle(tint(e))
                        Text(Lexicon.whyTitle(e)).font(.caption).foregroundStyle(.secondary)
                        if let term = Lexicon.term(forLens: e.lens) { HelpButton(term: term) }
                        Spacer()
                    }
                    let detail = e.lens == "x-height" ? (inspectorXHeightNote(c) ?? Lexicon.whyDetail(e)) : Lexicon.whyDetail(e)
                    if !detail.isEmpty {
                        Text(detail).font(.callout)
                            .help(e.lens == "Recommended for text" ? Lexicon.recommendedBy(Lexicon.sources(e.source)) : "")
                    }
                    if e.effect == 0 {
                        Text(Lexicon.notScored).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        let word = Lexicon.strength(e.strength)
                        Text([word, Lexicon.strengthHelp[word]].compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    let sources = Lexicon.sources(e.source)
                    if !sources.isEmpty { Text(sources).font(.caption2).foregroundStyle(.tertiary) }
                }
            }
        }
    }

    private func symbol(_ e: Evidence) -> String {
        e.effect > 0 ? "plus.circle" : e.effect < 0 ? "minus.circle" : "circle.dashed"
    }

    private func tint(_ e: Evidence) -> Color {
        e.effect > 0 ? .accentColor : e.effect < 0 ? .orange : .secondary
    }

    /// The candidate's Text playground (open) first, then the Display playground (collapsed unless asked for).
    @ViewBuilder
    private func playgrounds(_ c: Candidate) -> some View {
        if let family = model.familyByName[c.family] {
            PlaygroundGroup(job: "reading", family: family, title: "Text \u{00B7} \(family.name)",
                            preview: SampleCopy.paragraphs[0], startOpen: true)
        }
        if let display = model.displayFamily {
            PlaygroundGroup(job: "display", family: display, title: "Display \u{00B7} \(display.name)",
                            preview: SampleCopy.displayHeadline, startOpen: model.options.openPlayground)
        }
    }
}
