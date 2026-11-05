import Foundation

/// Why `--lock`, `--inspector`, `--compare` (and any developer flag with no value) hung the app at launch.
///
/// AppKit reads the command line as `-name value` pairs. A `--flag` with no value takes the NEXT argument as its
/// value, which leaves the argument after it over, and by default AppKit treats a leftover argument as a file to
/// open. Launch then waits for that open: no window, no `applicationDidFinishLaunching`, none of our code runs.
/// `--lock --appearance dark` hung. `--lock` as the very last argument did not, and `--lock 1` did not.
///
/// The fix is AppKit's own switch, `NSTreatUnknownArgumentsAsOpen`. With it off, a leftover argument is just ignored
/// (our flags are read by `LaunchOptions` and `Bench.swift`, not by AppKit). It must be set before AppKit starts, so
/// main.swift calls this first. The app never opens files from the command line, so nothing is lost.
enum LaunchArguments {
    static let defaultsKey = "NSTreatUnknownArgumentsAsOpen"

    static func stopTreatingStrayArgumentsAsFiles(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [defaultsKey: false])
    }
}
