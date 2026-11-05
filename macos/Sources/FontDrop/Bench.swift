import AppKit
import Darwin
import QuartzCore

// Developer tools, off unless a flag is passed:
//   --screenshot <png> [--screen display|reading|set] [--appearance light|dark] [--brand <name>] [--select <family>]
//       [--template article|hero|appui|poster] [--open-playground]
//       [--difference close|distinct|strong|any] [--page <n>  (Reading candidates asked of the core, default 40)] [--sources yours,google,system] [--show-hidden] [--saved] [--search <text>] [--sort less-common|character-first] [--demo-save <family,family>  (stars them in the DB copy)] [--demo-choose <family>  (no brand: shows the Name this brand sheet)]
//       Renders the window in-process (no screen-recording permission), writes a PNG, quits.
//       FD_NO_SIDEBAR=1 hides the sidebar. FD_NEW_BRAND=<name> makes a brand after setting a Saved scope. FD_WINDOW=WxH sets the capture window size (default 1360x860). --inspector / --no-inspector force the inspector.
//       Reading flags: --demo-shortlist, --compare, --zoom, --trim-display, --trim-reading, --body-size, --ratio, FD_LOCK=1, --pick-reading (see applyReadingFlags).
//   --bench
//       Measures load time and scroll frame times on the Display grid and Reading, prints "BENCH ..." lines, quits.

// MARK: - Screenshot

/// Captures this app's own window, with the toolbar and glass materials (cacheDisplay cannot draw those).
@MainActor
func capture(window: NSWindow) throws -> CGImage {
    // CGWindowListCreateImage is marked unavailable in the macOS 15+ SDK but still exists at runtime.
    typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
        throw NSError(domain: "FontDrop", code: 1, userInfo: [NSLocalizedDescriptionKey: "CGWindowListCreateImage unavailable"])
    }
    let fn = unsafeBitCast(sym, to: Fn.self)
    // 8 = kCGWindowListOptionIncludingWindow, 1 = kCGWindowImageBoundsIgnoreFraming
    guard let img = fn(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue() else {
        throw NSError(domain: "FontDrop", code: 3, userInfo: [NSLocalizedDescriptionKey: "capture returned nil"])
    }
    return img
}

/// A sheet or a popover is its own window, so the window capture misses it. Capture each one and draw it
/// onto the main image. A sheet also dims the window behind it, as macOS does.
@MainActor
func compositeWithSheets(window: NSWindow) throws -> CGImage {
    let base = try capture(window: window)
    let popovers = NSApp.windows.filter {
        $0 !== window && $0.isVisible && !window.sheets.contains($0) && $0.frame.intersects(window.frame)
            && $0.frame.width > 40 && String(describing: type(of: $0)).contains("Popover")
    }
    guard !window.sheets.isEmpty || !popovers.isEmpty else { return base }
    let scale = CGFloat(base.width) / window.frame.width
    // A popover can hang past the window's edge, so the canvas is the window plus every popover.
    let canvas = popovers.reduce(window.frame) { $0.union($1.frame) }
    let w = Int((canvas.width * scale).rounded()), h = Int((canvas.height * scale).rounded())
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
    let ox = (window.frame.minX - canvas.minX) * scale, oy = (window.frame.minY - canvas.minY) * scale
    ctx.draw(base, in: CGRect(x: ox, y: oy, width: CGFloat(base.width), height: CGFloat(base.height)))
    if !window.sheets.isEmpty {
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.25))
        ctx.fill(CGRect(x: ox, y: oy, width: CGFloat(base.width), height: CGFloat(base.height)))
    }
    for extra in window.sheets + popovers {
        guard let img = try? capture(window: extra) else { continue }
        let x = (extra.frame.minX - canvas.minX) * scale
        let y = (extra.frame.minY - canvas.minY) * scale      // CGContext origin is bottom-left, like AppKit
        ctx.draw(img, in: CGRect(x: x, y: y, width: CGFloat(img.width), height: CGFloat(img.height)))
    }
    return ctx.makeImage() ?? base
}

/// Screenshot flags for the Reading templates and the Colors popover:
///   --variant <id>             the layout (essay, feature, statement, product, detail, dashboard, event, specimen, readout, blocks, layered)
///   --colors <preset>          paper | night | bone | signal, or three hex values: --colors FFFFFF,0A0A0A,E5341D
///   --open-colors <role>       open the Colors popover, with this role's color field open (background | text | accent | none)
///   --tabular-display-figures  draw the big numbers in tabular figures, to show what the default avoids
@MainActor
func applyStyleFlags(_ model: AppModel) {
    let args = CommandLine.arguments
    // Each flag can also come from an environment variable (--open-colors -> FD_OPEN_COLORS). Long argument
    // lists sometimes stop macOS from opening the window when the app is launched from a script.
    func value(_ flag: String) -> String? {
        if let i = args.firstIndex(of: flag), i + 1 < args.count { return args[i + 1] }
        let name = "FD_" + flag.dropFirst(2).uppercased().replacingOccurrences(of: "-", with: "_")
        return ProcessInfo.processInfo.environment[name]
    }
    if let t = value("--template"), Templates.all.contains(where: { $0.id == t }) {
        let saved = model.defaults.string(forKey: "readingTemplate")
        model.templateID = t
        model.defaults.set(saved, forKey: "readingTemplate")     // a screenshot run never changes the remembered template
    }
    let template = Templates.descriptor(model.templateID)
    if let v = value("--variant") { model.brandStyle.setVariant(v, template: template) }
    if let c = value("--colors") {
        if let preset = TemplatePalette.presets.first(where: { $0.id == c.lowercased() }) {
            model.brandStyle.setPalette(preset.palette, brand: model.brandID)
        } else {
            let parts = c.split(separator: ",").compactMap { HexColor(hex: String($0)) }
            if parts.count == 3 {
                model.brandStyle.setPalette(TemplatePalette(background: parts[0], text: parts[1], accent: parts[2]), brand: model.brandID)
            }
        }
    }
    TemplateDebug.tabularDisplayFigures = args.contains("--tabular-display-figures") || value("--tabular-display-figures") != nil
    if let role = value("--open-colors") {
        model.brandStyle.editingRole = ColorRole(rawValue: role)
        model.brandStyle.showColors = true
    }
}

/// The window size for captures and the bench: 1360x860 unless `FD_WINDOW=WxH` says otherwise.
@MainActor
func captureSize() -> NSSize {
    if let raw = ProcessInfo.processInfo.environment["FD_WINDOW"] {
        let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
        if parts.count == 2, parts[0] >= 300, parts[1] >= 300 { return NSSize(width: parts[0], height: parts[1]) }
    }
    return NSSize(width: 1360, height: 860)
}

/// Reading flags for screenshots (each also reads FD_<NAME>):
///   --demo-shortlist <a,b,c>   shortlist these families (in the DB copy)
///   --compare                  turn Compare on
///   --zoom <factor>            stage zoom, 0.5 to 4
///   --trim-display <x>         the Display face's Trim as a multiplier, 0.75 to 1.35, in memory only
///   --trim-reading <x>         the same for the selected Reading candidate
///   --body-size <pt>           the brand scale's body size, 9 to 24, in memory only
///   --ratio <r>                the brand scale's ratio (1.2, 1.25, 1.333, 1.5, 1.618)
///   --lock or FD_LOCK=1        lock the scale: every size is body x ratio^step instead of fitted to the font
///   --pick-reading <family>    choose this family for Reading (in the DB copy)
///   --clear <job>              clear the Display or Reading face (in the DB copy)
/// --body-size, --ratio and FD_LOCK for the brand's scale. `family` is the Text face the lock starts from
/// (the selected candidate on Text, the chosen face on Set).
@MainActor
func applyScaleFlags(_ model: AppModel, family: (name: String, path: String)?) {
    let args = CommandLine.arguments
    func value(_ flag: String) -> String? {
        if let i = args.firstIndex(of: flag), i + 1 < args.count { return args[i + 1] }
        return ProcessInfo.processInfo.environment["FD_" + flag.dropFirst(2).uppercased().replacingOccurrences(of: "-", with: "_")]
    }
    let body = value("--body-size").flatMap(Double.init)
    let ratio = value("--ratio").flatMap(Double.init)
    // --lock works as an argument now (ArgvFix.swift fixed the launch hang); FD_LOCK=1 still works too.
    let lock = ProcessInfo.processInfo.environment["FD_LOCK"] != nil || args.contains("--lock")
    guard body != nil || ratio != nil || lock else { return }
    if lock, body == nil, ratio == nil, let family {
        model.lockScale(reading: family.name, fallbackPath: family.path)      // starts from what Fit gives, as the switch does
    }
    model.updateScale {
        if let body { $0.body = body }
        if let ratio { $0.ratio = TypeScale.nearestRatio(ratio) }
        if lock { $0.locked = true }
    }
}

@MainActor
func applyReadingFlags(_ model: AppModel) async {
    let args = CommandLine.arguments
    func value(_ flag: String) -> String? {
        if let i = args.firstIndex(of: flag), i + 1 < args.count { return args[i + 1] }
        return ProcessInfo.processInfo.environment["FD_" + flag.dropFirst(2).uppercased().replacingOccurrences(of: "-", with: "_")]
    }
    if let n = model.options.page { while model.candidateLimit < n && model.candidatesHasMore { await model.showMoreCandidates() } }
    if let list = value("--demo-shortlist") {
        for name in list.split(separator: ",") { await model.setShortlist("reading", family: String(name), on: true) }
    }
    if let f = value("--pick-reading") { await model.choose("reading", family: f) }
    if let job = value("--clear") { await model.clear(job) }          // "Clear Display face", for the screenshot of the result
    if let trim = value("--trim-display").flatMap(Double.init), let d = model.displayFamily {
        model.typeSettings.update(model.settingsKey("display", d.name), job: "display") {
            $0.trim = min(max(trim, TypeSettings.trimRange.lowerBound), TypeSettings.trimRange.upperBound)
        }
    }
    if let trim = value("--trim-reading").flatMap(Double.init), let c = model.candidate(model.selectedCandidate) {
        model.typeSettings.update(model.settingsKey("reading", c.family), job: "reading") {
            $0.trim = min(max(trim, TypeSettings.trimRange.lowerBound), TypeSettings.trimRange.upperBound)
        }
    }
    applyScaleFlags(model, family: model.candidate(model.selectedCandidate).map { ($0.family, $0.filePath) })
    if let z = value("--zoom").flatMap(Double.init) { while model.stageZoom.factor < z - 0.01 && model.stageZoom.canZoomIn { model.stageZoom.zoomIn() } }
    if args.contains("--compare") || value("--compare") != nil { model.compareMode = true }
}

/// Display-screen flags, applied before the capture:
///   --pick-reading <family>      choose this Text face (in the DB copy)
///   --clear <job>                clear the Display or Text face (in the DB copy)
///   --display-sort pairs|library the Display grid's sort (default: automatic, Pairs with once a Text face is chosen and no Display face is)
/// Then waits for the Pairs with ranks, so the capture never shows the grid half-sorted.
@MainActor
func applyDisplayFlags(_ model: AppModel) async {
    let args = CommandLine.arguments
    func value(_ flag: String) -> String? {
        if let i = args.firstIndex(of: flag), i + 1 < args.count { return args[i + 1] }
        return ProcessInfo.processInfo.environment["FD_" + flag.dropFirst(2).uppercased().replacingOccurrences(of: "-", with: "_")]
    }
    if let f = value("--pick-reading") { await model.choose("reading", family: f) }
    if let job = value("--clear") { await model.clear(job) }
    switch value("--display-sort") {
    case "pairs": model.displaySortChoice = .pairsWith
    case "library": model.displaySortChoice = .library
    default: break
    }
    var waited = 0
    while model.displayPairsLoading && waited < 300 { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
}

@MainActor
enum ScreenshotRunner {
    static func runIfRequested(model: AppModel) async {
        guard let path = model.options.screenshot else { return }
        while !(model.fontsReady) {
            if case .failed(let m) = model.phase { print("SCREENSHOT failed: \(m)"); NSApp.terminate(nil); return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        switch model.options.appearance ?? ProcessInfo.processInfo.environment["FD_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(captureSize())
        }
        model.screen = model.options.screen
        applyStyleFlags(model)
        try? await Task.sleep(for: .milliseconds(800))      // let the window settle at its new size before the inspector is forced
        let args = CommandLine.arguments
        let env = ProcessInfo.processInfo.environment
        if args.contains("--no-inspector") || env["FD_NO_INSPECTOR"] != nil { model.inspectorTouched = true; model.showInspector = false }
        if args.contains("--inspector") || env["FD_INSPECTOR"] != nil { model.inspectorTouched = true; model.showInspector = true }
        if env["FD_NO_SIDEBAR"] != nil { model.showSidebar = false }
        // FD_NEW_BRAND=<name>: make a brand after a dirty scope (Saved, system fonts) to show it starts on the full grid.
        if let name = env["FD_NEW_BRAND"] {
            model.filter.sources = [.system]; model.filter.savedOnly = true
            await model.createBrand(name)
            await model.finderSettled()
        }
        if model.screen == .reading {
            var waited = 0
            while model.candidates.isEmpty && model.candidatesError == nil && waited < 300 {
                try? await Task.sleep(for: .milliseconds(100)); waited += 1
            }
            await applyReadingFlags(model)
        } else {
            await applyDisplayFlags(model)
            model.selectedFamily = model.options.select ?? model.chosen(model.screen)
                ?? (model.screen == .display ? model.displayGridFamilies : model.visibleFamilies).first?.name
            if model.screen == .set, let r = model.readingFamily {
                applyScaleFlags(model, family: (r.name, r.filePath))
            }
        }
        if model.options.bgRefresh {
            // FD_BG_REFRESH=1 runs the real background rescan. FD_BG_REFRESH_AT=<s> captures that many seconds
            // after the window is ready (mid-rescan); otherwise the capture waits for the rescan to finish.
            if let at = env["FD_BG_REFRESH_AT"].flatMap(Double.init) {
                try? await Task.sleep(for: .seconds(max(0, at - 5)))
            } else {
                var waited = 0
                while !model.rescanDone && waited < 6000 { try? await Task.sleep(for: .milliseconds(100)); waited += 1 }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        if let family = model.options.demoChoose {
            // The "Name this brand" sheet: with --no-brand, pressing "Use for Display" opens it.
            model.selectedFamily = family
            await model.choose("display", family: family)
        }
        if let note = args.firstIndex(of: "--demo-notice").flatMap({ $0 + 1 < args.count ? args[$0 + 1] : nil }) ?? env["FD_DEMO_NOTICE"] {
            model.exportNotice = note        // set directly, so it stays up for the capture
        }
        try? await Task.sleep(for: .seconds(3))
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        try? await Task.sleep(for: .seconds(1))
        NSApp.windows.first(where: { $0.isVisible })?.displayIfNeeded()
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else {
            print("SCREENSHOT failed: no window"); NSApp.terminate(nil); return
        }
        print("SCREENSHOT diag visible=\(window.isVisible) occ=\(window.occlusionState.rawValue) key=\(window.isKeyWindow) frame=\(window.frame) screen=\(String(describing: window.screen?.frame)) layer=\(String(describing: window.contentView?.layer))")
        if CommandLine.arguments.contains("--dump-views") {
            func walk(_ v: NSView, _ d: Int) {
                print(String(repeating: " ", count: d) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden) layer=\(v.layer.map { "\(type(of: $0)) sub=\($0.sublayers?.count ?? 0)" } ?? "nil")")
                if d < 9 { v.subviews.forEach { walk($0, d + 1) } }
            }
            walk(window.contentView!, 0)
        }
        do {
            let rep = NSBitmapImageRep(cgImage: try compositeWithSheets(window: window))
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("SCREENSHOT written \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        } catch {
            print("SCREENSHOT failed: \(error)")
        }
        fflush(stdout)
        model.pending = nil                       // an open sheet would hold up quitting
        try? await Task.sleep(for: .milliseconds(400))
        NSApp.terminate(nil)
    }
}

// MARK: - Bench

@MainActor
enum Bench {
    static let speed: Double = 6000      // pt/s, a fast trackpad flick
    static let maxSeconds: Double = 40

    static func log(_ s: String) {
        print("BENCH " + s)
        fflush(stdout)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func runIfRequested(model: AppModel) async {
        guard model.options.bench else { return }
        // A test host counts as a bench for isolation, but it must not run the measurement: the bench quits the app
        // when it ends, and that would pull the host out from under the tests that are still running.
        guard !LaunchOptions.isTestHost(ProcessInfo.processInfo.environment) else { return }
        while !model.fontsReady {
            if case .failed(let m) = model.phase { log("failed: \(m)"); NSApp.terminate(nil); return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(captureSize())
        }
        try? await Task.sleep(for: .seconds(1))
        log("db=\(model.dbPath)")
        log("families=\(model.families.count) fonts=\(model.fontCount)")
        for t in model.timings { log(String(format: "load %@ = %.1f ms", t.label, t.ms)) }
        log(String(format: "memory after load: %.0f MB footprint, fonts cached %d", footprintMB(), FontLoader.shared.cachedCount))

        // Display grid: every family, fonts preloaded, 5 passes.
        model.screen = .display
        model.filter = .standard
        try? await Task.sleep(for: .seconds(1.5))
        for pass in 1...5 {
            let m0 = footprintMB()
            let stats = await scrollPass()
            log("scroll display grid pass \(pass): \(stats) | mem \(String(format: "%.0f", m0)) -> \(String(format: "%.0f", footprintMB())) MB")
        }
        // Jumps: what a scrollbar drag costs.
        if let sv = biggestScrollView(), let doc = sv.documentView {
            let maxY = max(0, doc.frame.height - sv.contentView.bounds.height)
            var out: [String] = []
            for frac in [0.5, 0.9, 0.2] {
                let t0 = DispatchTime.now()
                sv.contentView.scroll(to: NSPoint(x: 0, y: maxY * frac))
                sv.reflectScrolledClipView(sv.contentView)
                try? await Task.sleep(for: .milliseconds(100))
                out.append(String(format: "%.0f%%: %.0f ms", frac * 100, ms(t0, DispatchTime.now()) - 100))
            }
            log("jump display grid \(out.joined(separator: ", "))")
        }

        // Reading, if a Display face is chosen.
        if model.displayFamily != nil {
            let t0 = DispatchTime.now()
            model.screen = .reading
            while model.candidates.isEmpty && model.candidatesError == nil { try? await Task.sleep(for: .milliseconds(50)) }
            log(String(format: "reading: %d candidates ready in %.0f ms after switching screens", model.candidates.count, ms(t0, DispatchTime.now())))
            try? await Task.sleep(for: .seconds(1.5))
            for pass in 1...3 {
                log("scroll reading pass \(pass): \(await scrollPass())")
            }
        }
        log(String(format: "memory end: %.0f MB", footprintMB()))
        log("DONE")
        NSApp.terminate(nil)
    }

    // MARK: scroll

    static func biggestScrollView() -> NSScrollView? {
        guard let root = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return nil }
        var best: NSScrollView?
        func walk(_ v: NSView) {
            if let sv = v as? NSScrollView, let doc = sv.documentView,
               doc.frame.height > (best?.documentView?.frame.height ?? 0) { best = sv }
            v.subviews.forEach(walk)
        }
        walk(root)
        return best
    }

    static func scrollPass() async -> String {
        guard let sv = biggestScrollView(), let doc = sv.documentView, let win = sv.window else {
            return "ERROR no scroll view"
        }
        let clip = sv.contentView
        let maxY = max(0, doc.frame.height - clip.bounds.height)
        guard maxY > 0 else { return "ERROR nothing to scroll (content fits)" }
        let driver = Driver(scrollView: sv, maxY: maxY, speed: speed, deadline: maxSeconds)
        let link = win.contentView!.displayLink(target: driver, selector: #selector(Driver.tick(_:)))
        link.add(to: .main, forMode: .common)
        await withCheckedContinuation { c in driver.done = { c.resume() } }
        link.invalidate()
        return driver.summary(distance: maxY)
    }

    /// Scrolls the real NSScrollView behind the SwiftUI view at a fixed speed on a display link,
    /// and records the time between frames.
    @MainActor
    final class Driver: NSObject {
        let sv: NSScrollView
        let maxY: Double, speed: Double, deadline: Double
        var y = 0.0
        var last: CFTimeInterval = 0
        var start: CFTimeInterval = 0
        var interval: Double = 1.0 / 60
        var dts: [Double] = []
        var done: (() -> Void)?
        var finished = false

        init(scrollView: NSScrollView, maxY: Double, speed: Double, deadline: Double) {
            sv = scrollView; self.maxY = maxY; self.speed = speed; self.deadline = deadline
            sv.contentView.scroll(to: .zero)
            sv.reflectScrolledClipView(sv.contentView)
        }

        @objc func tick(_ link: CADisplayLink) {
            guard !finished else { return }
            let now = link.timestamp
            interval = link.targetTimestamp - link.timestamp
            if last == 0 { last = now; start = now; return }
            let dt = now - last
            dts.append(dt)
            last = now
            y += speed * min(dt, 0.05)   // a stalled frame must not teleport the scroll position
            if y >= maxY || now - start > deadline {
                finished = true
                done?()
                return
            }
            sv.contentView.scroll(to: NSPoint(x: 0, y: y))
            sv.reflectScrolledClipView(sv.contentView)
        }

        func summary(distance: Double) -> String {
            guard !dts.isEmpty else { return "no frames" }
            let s = dts.sorted()
            func p(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count) * q))] * 1000 }
            let nominal = interval * 1000
            let late = dts.filter { $0 * 1000 > nominal * 1.5 }.count
            let severe = dts.filter { $0 * 1000 > nominal * 3 }.count
            return String(format: "frames=%d refresh=%.1fms p50=%.1f p95=%.1f p99=%.1f max=%.1fms late(>1.5x)=%d (%.1f%%) severe(>3x)=%d scrolled=%.0f/%.0fpt",
                          dts.count, nominal, p(0.5), p(0.95), p(0.99), s.last! * 1000,
                          late, Double(late) / Double(dts.count) * 100, severe, min(y, distance), distance)
        }
    }
}


/// `--export-dir <dir>` writes every export for the brand's pair into the folder and quits: pair.css, pair.tailwind.css,
/// pair.paper.css, licenses.txt, spec.pdf and spec.png. No panel, no pasteboard. The render check and the spec page
/// samples come from here. (Also FD_EXPORT_DIR.)
@MainActor
enum ExportRunner {
    static func runIfRequested(model: AppModel) async {
        let args = CommandLine.arguments
        let dir = args.firstIndex(of: "--export-dir").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            ?? ProcessInfo.processInfo.environment["FD_EXPORT_DIR"]
        guard let dir else { return }
        while !model.fontsReady {
            if case .failed(let m) = model.phase { print("EXPORT failed: \(m)"); NSApp.terminate(nil); return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        guard let spec = await ExportSpec.make(model: model), let d = model.displayFamily, let r = model.readingFamily else {
            print("EXPORT failed: \(Lexicon.Export.needsFaces)"); NSApp.terminate(nil); return
        }
        do {
            try Exporters.css(spec).write(to: base.appendingPathComponent("pair.css"), atomically: true, encoding: .utf8)
            try Exporters.theme(spec).write(to: base.appendingPathComponent("pair.tailwind.css"), atomically: true, encoding: .utf8)
            try Exporters.theme(spec, paper: true).write(to: base.appendingPathComponent("pair.paper.css"), atomically: true, encoding: .utf8)
            try Exporters.licenses(spec).write(to: base.appendingPathComponent("licenses.txt"), atomically: true, encoding: .utf8)
            let out = try SpecPage.write(spec: spec, displayFace: model.face("display", d), textFace: model.face("reading", r),
                                         base: base.appendingPathComponent("spec"))
            print("EXPORT wrote \(out.pdf.path) \(out.png.path)")
        } catch {
            print("EXPORT failed: \(error)")
        }
        NSApp.terminate(nil)
    }
}
