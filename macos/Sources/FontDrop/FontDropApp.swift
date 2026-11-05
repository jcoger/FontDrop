import AppKit
import SwiftUI

@main
struct FontDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(options: LaunchOptions())

    var body: some Scene {
        WindowGroup("FontDrop") {
            RootView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            // One window: a second one would share this model and run the open and rescan again.
            CommandGroup(replacing: .newItem) {}
            // Command-1 Display, command-2 Text, command-3 Set. The menu lists them.
            CommandMenu(Lexicon.goMenu) {
                ForEach(Screen.sidebar) { screen in
                    if let key = screen.shortcutKey {
                        Button(screen.title) { model.screen = screen }
                            .keyboardShortcut(key, modifiers: .command)
                    }
                }
            }
            CommandMenu(Lexicon.typeMenu) {
                ForEach(["display", "reading"], id: \.self) { job in
                    Button(Lexicon.clearFace(job)) { Task { await model.clear(job) } }
                        .disabled(!model.canClear(job))
                }
                Divider()
                Button(Lexicon.undo) {
                    Task { for job in ["display", "reading"] where model.canUndo(job) { await model.undo(job); break } }
                }
                .disabled(!(model.canUndo("display") || model.canUndo("reading")))
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
