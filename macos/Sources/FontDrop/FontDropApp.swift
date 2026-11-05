import AppKit
import SwiftUI

/// Usage: FontDrop [--db <path>] [--bench]
/// DB path order: --db, $FONTDROP_DB, the real app's DB (opened read-only by the core).
@main
struct FontDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    private let dbPath: String
    private let bench: Bool

    init() {
        let args = CommandLine.arguments
        bench = args.contains("--bench")
        if let i = args.firstIndex(of: "--db"), i + 1 < args.count {
            dbPath = args[i + 1]
        } else if let env = ProcessInfo.processInfo.environment["FONTDROP_DB"] {
            dbPath = env
        } else {
            dbPath = NSHomeDirectory() + "/Library/Application Support/co.dynolabs.fontdrop/fontdrop.db"
        }
    }

    var body: some Scene {
        WindowGroup("FontDrop") {
            RootView(store: Store(dbPath: dbPath), bench: bench)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 800)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
