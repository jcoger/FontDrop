import AppKit
import Darwin
import QuartzCore

// Developer tools, off unless a flag is passed:
//   --screenshot <png> [--screen display|reading|set] [--appearance light|dark] [--brand <name>] [--select <family>]
//       Renders the window in-process (no screen-recording permission), writes a PNG, quits.
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

@MainActor
enum ScreenshotRunner {
    static func runIfRequested(model: AppModel) async {
        guard let path = model.options.screenshot else { return }
        while !(model.fontsReady) {
            if case .failed(let m) = model.phase { print("SCREENSHOT failed: \(m)"); NSApp.terminate(nil); return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        switch model.options.appearance {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: 1360, height: 860))
        }
        model.screen = model.options.screen
        if CommandLine.arguments.contains("--no-inspector") { model.showInspector = false }
        if model.screen == .reading {
            while model.candidates.isEmpty && model.candidatesError == nil && model.displayFamily != nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
        } else {
            model.selectedFamily = model.options.select ?? model.chosen(model.screen) ?? model.visibleFamilies.first?.name
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
            let rep = NSBitmapImageRep(cgImage: try capture(window: window))
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("SCREENSHOT written \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        } catch {
            print("SCREENSHOT failed: \(error)")
        }
        fflush(stdout)
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
        while !model.fontsReady {
            if case .failed(let m) = model.phase { log("failed: \(m)"); NSApp.terminate(nil); return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: 1360, height: 860))
        }
        try? await Task.sleep(for: .seconds(1))
        log("db=\(model.dbPath)")
        log("families=\(model.families.count) fonts=\(model.fontCount)")
        for t in model.timings { log(String(format: "load %@ = %.1f ms", t.label, t.ms)) }
        log(String(format: "memory after load: %.0f MB footprint, fonts cached %d", footprintMB(), FontLoader.shared.cachedCount))

        // Display grid: every family, fonts preloaded, 5 passes.
        model.screen = .display
        model.category = .all
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
