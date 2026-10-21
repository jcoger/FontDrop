import AppKit
import QuartzCore
import Darwin
import FontDropCore

/// `--bench`: measures load, font prefetch, and scroll frame times, prints "BENCH ..." lines, quits.
/// Scrolling drives the real NSScrollView behind the SwiftUI list/grid at a fixed speed (pt/s),
/// so the frame times include layout, lazy row creation and font loading.
@MainActor
enum Bench {
    static let speed: Double = 6000      // pt/s, a fast trackpad flick
    static let maxSeconds: Double = 30

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

    /// Main-thread watchdog: when the main thread has not ticked for 3 s, run /usr/bin/sample on ourselves.
    nonisolated(unsafe) static var heartbeat = CACurrentMediaTime()
    static func startWatchdog() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let dir = ProcessInfo.processInfo.environment["BENCH_OUT"] ?? NSTemporaryDirectory()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in Bench.heartbeat = CACurrentMediaTime() }
        let t = Thread {
            var n = 0
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                if CACurrentMediaTime() - heartbeat > 3, n < 3 {
                    n += 1
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                    p.arguments = ["\(pid)", "2", "-file", "\(dir)/stall-\(n).txt"]
                    try? p.run(); p.waitUntilExit()
                    print("BENCH main thread stalled >3s, sample written to \(dir)/stall-\(n).txt"); fflush(stdout)
                    Thread.sleep(forTimeInterval: 5)
                }
            }
        }
        t.start()
    }

    /// `--screenshot <png>`: waits for data and pairs, renders the window in-process (no screen-recording
    /// permission needed), writes a PNG, quits. Optional `--select <family name>`.
    static func screenshot(store: Store, path: String) async {
        while store.families.isEmpty && store.loadError == nil { try? await Task.sleep(for: .milliseconds(100)) }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--select"), i + 1 < args.count,
           let f = store.families.first(where: { $0.name == args[i + 1] }) { store.selection = f.id }
        if let i = args.firstIndex(of: "--mode"), i + 1 < args.count,
           let m = BrowseMode.allCases.first(where: { $0.rawValue == args[i + 1] }) { store.mode = m }
        try? await Task.sleep(for: .seconds(4))
        guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { log("screenshot failed"); NSApp.terminate(nil); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        log("screenshot written \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        NSApp.terminate(nil)
    }

    static func run(store: Store) async {
        if CommandLine.arguments.contains("--watch") { startWatchdog() }   // sampling itself perturbs timings
        // wait for data
        while store.families.isEmpty && store.loadError == nil { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .seconds(1))
        log("db=\(store.dbPath)")
        for t in store.timings { log(String(format: "load %@ = %.1f ms", t.label, t.ms)) }
        log(String(format: "memory after data load: %.0f MB footprint", footprintMB()))

        // pair query latency, 5 families
        var pairMs: [Double] = []
        guard let lib = store.core else { return }
        for f in store.families.prefix(60).filter({ $0.styleCount > 2 }).prefix(5) {
            let id = f.fontId
            let m: Double = await Task.detached {
                let t0 = DispatchTime.now()
                _ = try? lib.fontPairs(fontId: id, excludedIds: [], job: nil)
                return ms(t0, DispatchTime.now())
            }.value
            pairMs.append(m)
        }
        log("font_pairs ms (5 families): " + pairMs.map { String(format: "%.0f", $0) }.joined(separator: ", "))
        log(String(format: "memory idle: %.0f MB", footprintMB()))

        // scroll passes
        if CommandLine.arguments.contains("--hot") {
            // Experiment: every font already cached, so rows never write @State from a task.
            for f in store.fonts { _ = FontLoader.shared.load(path: f.filePath, preferredText: f.family) }
            log("hot: \(FontLoader.shared.cachedCount) fonts preloaded")
            for mode in [BrowseMode.sidebar, .grid, .flat, .flat, .grid, .sidebar] {
                store.mode = mode
                try? await Task.sleep(for: .seconds(1.5))
                log("hot scroll mode=\(mode.rawValue) \(await scrollPass())")
            }
            log("DONE")
            NSApp.terminate(nil)
            return
        }
        let only = CommandLine.arguments.contains("--prefetch-only")
        for mode in BrowseMode.allCases where !only {
            for pass in ["cold", "warm"] {
                if pass == "cold" { FontLoader.shared.clear() }
                store.mode = mode
                try? await Task.sleep(for: .seconds(1.5))
                let m0 = footprintMB()
                let stats = await scrollPass()
                log("scroll mode=\(mode.rawValue) cache=\(pass) \(stats) | mem \(String(format: "%.0f", m0)) -> \(String(format: "%.0f", footprintMB())) MB | fonts cached \(FontLoader.shared.cachedCount)")
            }
        }

        // jump test: what a scrollbar drag or "scroll to letter" costs
        for mode in BrowseMode.allCases {
            store.mode = mode
            try? await Task.sleep(for: .seconds(1.5))
            guard let sv = biggestScrollView(), let doc = sv.documentView else { continue }
            let maxY = max(0, doc.frame.height - sv.contentView.bounds.height)
            var out: [String] = []
            for frac in [0.5, 0.9, 0.2] {
                let t0 = DispatchTime.now()
                sv.contentView.scroll(to: NSPoint(x: 0, y: maxY * frac))
                sv.reflectScrolledClipView(sv.contentView)
                try? await Task.sleep(for: .milliseconds(100))
                out.append(String(format: "%.0f%%: %.0f ms", frac * 100, ms(t0, DispatchTime.now()) - 100))
            }
            log("jump mode=\(mode.rawValue) \(out.joined(separator: ", ")) (cold-ish cache)")
        }

        await prefetchAll(store: store)
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
        let driver = Driver(scrollView: sv, maxY: maxY, speed: speed, deadline: maxSeconds)
        let link = win.contentView!.displayLink(target: driver, selector: #selector(Driver.tick(_:)))
        link.add(to: .main, forMode: .common)
        await withCheckedContinuation { c in driver.done = { c.resume() } }
        link.invalidate()
        return driver.summary(distance: maxY)
    }

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
            Bench.heartbeat = CACurrentMediaTime()
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

    // MARK: prefetch

    static func prefetchAll(store: Store) async {
        FontLoader.shared.clear()
        FontLoader.profile = true
        let paths: [String] = store.fonts.map(\.filePath)
        let fams: [String] = store.fonts.map(\.family)
        let before = footprintMB()
        let t0 = DispatchTime.now()
        let times: [Double] = await Task.detached { () -> [Double] in
            // 8 workers over the list
            let n = paths.count, workers = 8
            return await withTaskGroup(of: [Double].self) { g in
                for w in 0..<workers {
                    g.addTask {
                        var out: [Double] = []
                        var i = w
                        while i < n {
                            let a = DispatchTime.now()
                            _ = FontLoader.shared.load(path: paths[i], preferredText: fams[i])
                            out.append(ms(a, DispatchTime.now()))
                            i += workers
                        }
                        return out
                    }
                }
                var all: [Double] = []
                for await part in g { all += part }
                return all
            }
        }.value
        let total = ms(t0, DispatchTime.now())
        let s = times.sorted()
        func p(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count) * q))] }
        let fails = FontLoader.shared.failures
        let noDesc = fails.filter { $0.value == .noDescriptors }
        let noGlyph = fails.filter { $0.value == .noGlyphs }
        log(String(format: "prefetch %d font files, 8 workers: total %.0f ms, per-file p50=%.2f p95=%.2f max=%.1f ms | mem %.0f -> %.0f MB",
                   paths.count, total, p(0.5), p(0.95), s.last ?? 0, before, footprintMB()))
        log("fail: Core Text could not read \(noDesc.count); loaded but no glyphs for name or sample \(noGlyph.count)")
        let names = Dictionary(store.fonts.map { ($0.filePath, $0.name) }, uniquingKeysWith: { a, _ in a })
        let slow = FontLoader.shared.steps.sorted { ($0.descriptors + $0.create + $0.cover) > ($1.descriptors + $1.create + $1.cover) }.prefix(15)
        log("slowest 15 files (ms: descriptors / CTFontCreate / glyph probe, file size):")
        for st in slow {
            let size = ((try? FileManager.default.attributesOfItem(atPath: st.path)[.size] as? Int) ?? 0) ?? 0
            log(String(format: "  %7.0f / %7.0f / %7.0f  %6.1f MB  %@", st.descriptors, st.create, st.cover, Double(size) / 1_048_576, st.path))
        }
        let sum = FontLoader.shared.steps.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.descriptors, $0.1 + $1.create, $0.2 + $1.cover) }
        log(String(format: "summed worker time ms: descriptors %.0f, CTFontCreate %.0f, glyph probe %.0f", sum.0, sum.1, sum.2))
        for (path, f) in fails.sorted(by: { $0.key < $1.key }).prefix(40) {
            log("  \(f == .noDescriptors ? "unreadable" : "noglyphs") \(names[path] ?? "?") :: \(path)")
        }
    }
}
