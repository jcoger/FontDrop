import AppKit
import SwiftUI

/// Started from main.swift, after ArgvFix.
struct FontDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(options: LaunchOptions())

    init() { InstrumentFonts.registerFonts() }

    var body: some Scene {
        WindowGroup("FontDrop") {
            ThemeRoot {
                RootView()
                    .environment(model)
                    .frame(minWidth: 1000, minHeight: 640)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            // One window: a second one would share this model and run the open and rescan again.
            CommandGroup(replacing: .newItem) {}
            // File > Export: the same five items as the Set bar. Disabled until both faces are picked.
            CommandGroup(replacing: .importExport) {
                Menu(Lexicon.Export.menu) { ExportMenuItems(shortcuts: true).environment(model) }
                    .disabled(!model.canExport)
            }
            // Command-1 Display, command-2 Text, command-3 Set. The menu lists them.
            CommandMenu(Lexicon.goMenu) {
                ForEach(Screen.sidebar) { screen in
                    if let key = screen.shortcutKey {
                        Button(screen.title) { model.screen = screen }
                            .keyboardShortcut(key, modifiers: .command)
                    }
                }
            }
            CommandGroup(replacing: .appInfo) {
                Button("About FontDrop") { AboutPanel.show() }
            }
            // Edit > Undo and Redo take back and redo a face choice or clear. In a text box they undo the typing.
            CommandGroup(replacing: .undoRedo) {
                Button(model.undoLastLabel ?? Lexicon.undo) { Self.undo(model) }
                    .keyboardShortcut("z", modifiers: .command)
                Button(model.redoLastLabel ?? Lexicon.Keyboard.redo) { Self.redo(model) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button(Lexicon.Keyboard.find) { model.requestSearchFocus() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(!model.canFind)
            }
            CommandGroup(after: .sidebar) {
                Button(model.showSidebar ? Lexicon.hideSidebar : Lexicon.showSidebar) { model.showSidebar.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Button(model.showInspector ? Lexicon.hideInspector : Lexicon.showInspector) {
                    model.inspectorTouched = true; model.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
                Button(model.preview == nil ? Lexicon.Keyboard.previewFace : Lexicon.Keyboard.closePreview) { model.togglePreview() }
                    .keyboardShortcut("y", modifiers: .command)
                    .disabled(model.preview == nil && model.selectedFaceName == nil)
                // Command-= is the menu's key (no Shift on a US keyboard). Command-+ also works: see RootView.
                Button(Lexicon.Reading.zoomIn) { model.stageZoom.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(!model.canZoomStage || !model.stageZoom.canZoomIn)
                Button(Lexicon.Reading.zoomOut) { model.stageZoom.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!model.canZoomStage || !model.stageZoom.canZoomOut)
                Button(Lexicon.Reading.zoomFit) { model.stageZoom.fit() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(!model.canZoomStage)
            }
            CommandMenu(Lexicon.typeMenu) {
                // Return does the same in the Display grid and the Text list. The menu carries a modified shortcut so
                // that typing in a text box is never taken.
                Button(Lexicon.useFor(model.keyJob ?? "display")) { Task { await model.useSelected() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canUseSelected)
                Divider()
                ForEach(["display", "reading"], id: \.self) { job in
                    Button(Lexicon.clearFace(job)) { Task { await model.clear(job) } }
                        .disabled(!model.canClear(job))
                }
            }
        }
    }

    /// Command-Z. A text box that is being edited gets it first, so typing can be undone as usual. Otherwise it takes
    /// back a face choice, but only from the main window with nothing sitting on it: not behind a sheet or an alert,
    /// and not from the About panel.
    @MainActor
    static func undo(_ model: AppModel) {
        let text = NSApp.keyWindow?.firstResponder as? NSTextView
        switch UndoRoute.route(textCan: text?.undoManager?.canUndo == true, window: NSApp.keyWindow) {
        case .text: text?.undoManager?.undo()
        case .model: Task { await model.undoLast() }
        case .ignore: break
        }
    }

    @MainActor
    static func redo(_ model: AppModel) {
        let text = NSApp.keyWindow?.firstResponder as? NSTextView
        switch UndoRoute.route(textCan: text?.undoManager?.canRedo == true, window: NSApp.keyWindow) {
        case .text: text?.undoManager?.redo()
        case .model: Task { await model.redoLast() }
        case .ignore: break
        }
    }
}

/// Where Command-Z goes.
enum UndoRoute: Equatable {
    case text, model, ignore

    static func route(textCan: Bool, window: NSWindow?) -> UndoRoute {
        route(textCan: textCan, isMainWindow: window.map { $0.canBecomeMain && $0.sheetParent == nil } ?? false,
              hasSheet: window?.attachedSheet != nil)
    }

    static func route(textCan: Bool, isMainWindow: Bool, hasSheet: Bool) -> UndoRoute {
        if textCan { return .text }
        return isMainWindow && !hasSheet ? .model : .ignore
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
