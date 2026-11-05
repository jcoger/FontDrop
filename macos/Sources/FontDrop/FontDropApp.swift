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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
