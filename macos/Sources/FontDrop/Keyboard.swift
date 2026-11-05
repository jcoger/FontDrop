import AppKit
import FontDropCore
import SwiftUI

// Keyboard for every core task (R7). The menus (FontDropApp.swift) hold each command and show its shortcut. The lists
// take the bare keys: arrows move, Return uses, Space previews. Escape closes a preview.

/// Arrow-key movement in a grid of equal cells.
enum GridNav {
    enum Direction { case left, right, up, down }

    /// How many columns an adaptive grid fits: as many minimum-width cells as the width allows.
    static func columns(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
    }

    /// The index after one arrow press. Nothing selected: the first cell. Up and down move by a row and stop at the
    /// ends (they never jump to the other end). Left and right move by one and stop at the ends.
    static func move(count: Int, from index: Int?, _ direction: Direction, columns: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index, (0..<count).contains(index) else { return 0 }
        let cols = max(columns, 1)
        switch direction {
        case .left: return max(index - 1, 0)
        case .right: return min(index + 1, count - 1)
        case .up: return index - cols >= 0 ? index - cols : index
        case .down: return index + cols <= count - 1 ? index + cols : index
        }
    }
}

/// A face on show in the large preview.
struct FacePreviewState: Equatable {
    let job: String          // "display" or "reading"
    let family: String
}

extension AppModel {
    /// The family the arrow keys have selected on the current screen: the Display grid's card, or the Text list's row.
    /// Nil when that face is not on screen (a filter or the search box hides it): Return and Space then do nothing,
    /// and the first arrow press starts from the first face you can see.
    var selectedFaceName: String? {
        switch screen {
        case .display, .ui, .mono:
            guard let name = selectedFamily, visibleFamilies.contains(where: { $0.name == name }) else { return nil }
            return name
        case .reading:
            let rows = ReadingRows.rows(current: currentReadingCandidate, shown: readingResult.shown, search: search)
            guard let id = selectedCandidate, rows.contains(where: { $0.id == id }) else { return nil }
            return candidate(id)?.family
        case .set, .colors: return nil
        }
    }

    /// Return and the Type menu's Use for ... apply to this job. Set has no list, so it has no job.
    var keyJob: String? {
        switch screen {
        case .display: "display"
        case .reading: "reading"
        case .ui, .mono, .set, .colors: nil
        }
    }

    var canUseSelected: Bool { keyJob != nil && selectedFaceName != nil && phase == .ready }

    /// Return, or Type > Use for Display / Text.
    func useSelected() async {
        guard let job = keyJob, let name = selectedFaceName else { return }
        await choose(job, family: name)
    }

    /// Space, or View > Preview Face. Space again closes it.
    func togglePreview() {
        if preview != nil { preview = nil; return }
        guard let job = keyJob, let name = selectedFaceName, familyByName[name] != nil else { return }
        preview = FacePreviewState(job: job, family: name)
    }

    func closePreview() { preview = nil }

    /// Command-F: puts the keyboard in the search box of the screen you are on.
    func requestSearchFocus() { focusSearchTick += 1 }
    /// Escape in the search box: gives the keyboard back to the list.
    func requestListFocus() { focusListTick += 1 }

    var canFind: Bool { screen != .set && screen != .colors && phase == .ready && !showsScanScreen && !libraryIsEmpty }

    var canZoomStage: Bool { screen == .reading && comparedFamilies.isEmpty }
}

// MARK: - The large preview

/// A Quick Look style preview of the selected face: its name, a headline in it, the alphabet and a paragraph, over a
/// dimmed window. Space or Escape closes it. Return uses the face. It draws the face with the designer's settings.
///
/// React: a modal portal with a focus trap and an Escape handler.
struct FacePreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    let state: FacePreviewState

    var body: some View {
        let family = model.familyByName[state.family]
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { model.closePreview() }
            if let family {
                let face = model.face(state.job, family)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(family.name).font(.system(size: 15, weight: .semibold))
                        Text(Lexicon.jobName(state.job)).font(.system(size: 13)).foregroundStyle(theme.textSecondary.color)
                        Spacer()
                        Text(Lexicon.Keyboard.previewHint).font(.system(size: 12)).foregroundStyle(theme.textSecondary.color)
                    }
                    FaceText(face: face, text: state.job == "display" ? model.sampleText : Lexicon.Keyboard.previewHeadline,
                             ratio: 88 / max(CGFloat(face.settings.size), 1), tick: model.fontTick)
                        .lineLimit(2).minimumScaleFactor(0.4)
                    FaceText(face: face, text: Lexicon.Keyboard.previewLetters, ratio: 28 / max(CGFloat(face.settings.size), 1), tick: model.fontTick)
                    if state.job == "reading" {
                        FaceText(face: face, text: Lexicon.Keyboard.previewParagraph, ratio: 17 / max(CGFloat(face.settings.size), 1), tick: model.fontTick)
                            .frame(maxWidth: 560, alignment: .leading)
                    }
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.panelContent.color))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(theme.textPrimary.color.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .padding(40)
                .onTapGesture {}                                 // a click on the card does not close it
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(keys: [.escape, .space]) { _ in model.closePreview(); return .handled }
        // Tab leaves the preview: it closes and the keys go back to the list, so the controls under it can be reached.
        .onKeyPress(keys: [.tab]) { _ in model.closePreview(); model.requestListFocus(); return .handled }
        .onExitCommand { model.closePreview() }
        .onKeyPress(keys: [.return]) { _ in
            let job = state.job, name = state.family
            model.closePreview()
            Task { await model.choose(job, family: name) }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Lexicon.Keyboard.previewAccessibility(state.family))
        .accessibilityAction(.escape) { model.closePreview() }
        .transition(.opacity)
    }
}
