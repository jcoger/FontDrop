import AppKit
import SwiftUI

/// Export actions: each reads the brand's pair from the model, then copies or saves it and says so in the Set bar.
extension AppModel {
    /// Export needs both faces. The reason is shown in the Set inspector and on the disabled items.
    var canExport: Bool { displayFamily != nil && readingFamily != nil }
    var exportReason: String? { canExport ? nil : Lexicon.Export.needsFaces }

    enum ExportKind { case css, tailwind, paper, licenses }

    /// The text for one kind, or nil while a face is missing.
    func exportText(_ kind: ExportKind) async -> String? {
        guard let spec = await ExportSpec.make(model: self) else { return nil }
        switch kind {
        case .css: return Exporters.css(spec)
        case .tailwind: return Exporters.theme(spec)
        case .paper: return Exporters.theme(spec, paper: true)
        case .licenses: return Exporters.licenses(spec)
        }
    }

    func copyExport(_ kind: ExportKind) {
        Task { @MainActor in
            guard let text = await exportText(kind) else { return }
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(text, forType: .string)
            switch kind {
            case .css: announce(Lexicon.Export.cssCopied)
            case .tailwind: announce(Lexicon.Export.tailwindCopied)
            case .paper: announce(Lexicon.Export.paperCopied)
            case .licenses: announce(Lexicon.Export.licensesCopied)
            }
        }
    }

    /// Asks where to save, then writes the PDF and the PNG side by side.
    func saveSpecPage() {
        Task { @MainActor in
            guard let spec = await ExportSpec.make(model: self), let d = displayFamily, let r = readingFamily else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = Lexicon.Export.defaultFileName(spec.brandName) + ".pdf"
            panel.message = Lexicon.Export.savePanelMessage
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try SpecPage.write(spec: spec, displayFace: face("display", d), textFace: face("reading", r), base: url)
                announce(Lexicon.Export.specSaved)
            } catch {
                announce(Lexicon.Export.specFailed)
            }
        }
    }

    /// Shows a line in the Set bar for a couple of seconds.
    func announce(_ text: String) {
        exportNotice = text
        exportNoticeTask?.cancel()
        exportNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.exportNotice = nil
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

/// The five Export items. The File menu carries the shortcuts; the Set bar and the inspector foot do not repeat them.
struct ExportMenuItems: View {
    @Environment(AppModel.self) private var model
    var shortcuts = false

    var body: some View {
        item(Lexicon.Export.copyCSS, "c") { model.copyExport(.css) }
        item(Lexicon.Export.copyTailwind, "t") { model.copyExport(.tailwind) }
        item(Lexicon.Export.copyPaper, "p") { model.copyExport(.paper) }
        Divider()
        item(Lexicon.Export.specPage, "s") { model.saveSpecPage() }
        item(Lexicon.Export.copyLicenses, "l") { model.copyExport(.licenses) }
    }

    @ViewBuilder
    private func item(_ title: String, _ key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        if shortcuts {
            Button(title, action: action).keyboardShortcut(key, modifiers: [.command, .shift]).disabled(!model.canExport)
        } else {
            Button(title, action: action).disabled(!model.canExport)
        }
    }
}
