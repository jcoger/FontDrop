import CoreText
import Foundation

/// Loads fonts straight from a file URL with Core Text. No global registration:
/// nothing lands in the system font list.
///
/// The cache is a lock-guarded dictionary, so views can read it from `body`
/// without touching the disk or writing any state. Fonts are loaded ahead of
/// time by `preload` (see AppModel). The spike showed that loading from each
/// row caused multi-second stalls.
final class FontLoader: @unchecked Sendable {
    static let shared = FontLoader()

    enum Failure: Error, Hashable, Sendable {
        case noDescriptors   // Core Text could not read the file at all
    }

    /// A loaded face. `probe` is a size-20 instance used to ask "can this font draw that text?".
    struct Loaded: @unchecked Sendable {
        let descriptor: CTFontDescriptor
        let faceCount: Int
        let probe: CTFont

        func font(size: CGFloat) -> CTFont { CTFontCreateWithFontDescriptor(descriptor, size, nil) }

        func canDraw(_ text: String) -> Bool {
            let chars = Array(text.utf16)
            guard !chars.isEmpty else { return false }
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            return CTFontGetGlyphsForCharacters(probe, chars, &glyphs, chars.count)
        }

        /// x-height as a fraction of the em (0.518 = 51.8%).
        var xHeightRatio: Double { Double(CTFontGetXHeight(probe)) / 20 }

        /// Variable-font axes, if any (wght, opsz, STYL ...).
        var axes: [Axis] {
            guard let raw = CTFontCopyVariationAxes(probe) as? [[String: Any]] else { return [] }
            return raw.compactMap { d in
                guard let min = (d[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue,
                      let max = (d[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue,
                      let def = (d[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)?.doubleValue
                else { return nil }
                let name = d[kCTFontVariationAxisNameKey as String] as? String ?? "Axis"
                let id = (d[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value ?? 0
                let hidden = (d[kCTFontVariationAxisHiddenKey as String] as? NSNumber)?.boolValue ?? false
                return Axis(tag: Self.tag(id), identifier: id, name: name, min: min, max: max,
                            defaultValue: def, hidden: hidden)
            }
        }

        private static func tag(_ id: UInt32) -> String {
            let bytes = [UInt8((id >> 24) & 0xff), UInt8((id >> 16) & 0xff), UInt8((id >> 8) & 0xff), UInt8(id & 0xff)]
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    struct Axis: Sendable, Identifiable {
        let tag: String
        let identifier: UInt32     // the number Core Text wants when you set a value
        let name: String
        let min: Double
        let max: Double
        let defaultValue: Double
        var hidden = false         // the font asks apps not to show it (e.g. GRAD in SF)
        var id: String { tag }
    }

    private let lock = NSLock()
    private var cache: [String: Result<Loaded, Failure>] = [:]

    static let fallbackSample = "Hamburgefonstiv"

    /// Safe to call from any thread. First call per path reads the file.
    @discardableResult
    func load(path: String) -> Result<Loaded, Failure> {
        lock.lock()
        if let hit = cache[path] { lock.unlock(); return hit }
        lock.unlock()

        let result = Self.read(path: path)

        lock.lock()
        cache[path] = result
        lock.unlock()
        return result
    }

    /// Cache lookup only; never touches the disk. Cheap enough to call from a view body.
    func cached(_ path: String) -> Result<Loaded, Failure>? {
        lock.lock(); defer { lock.unlock() }
        return cache[path]
    }

    var cachedCount: Int { lock.lock(); defer { lock.unlock() }; return cache.count }

    func clear() { lock.lock(); cache.removeAll(); lock.unlock() }

    /// Loads every path with `workers` parallel tasks. Returns when all are cached.
    /// `progress` is called (from a worker) after each batch with the running total.
    func preload(paths: [String], workers: Int = 8, batch: Int = 256,
                 progress: (@Sendable (Int) -> Void)? = nil) async {
        let todo = paths.filter { cached($0) == nil }
        guard !todo.isEmpty else { return }
        var done = 0
        for start in stride(from: 0, to: todo.count, by: batch) {
            let slice = Array(todo[start..<min(start + batch, todo.count)])
            await withTaskGroup(of: Void.self) { group in
                for w in 0..<workers {
                    group.addTask {
                        var i = w
                        while i < slice.count { FontLoader.shared.load(path: slice[i]); i += workers }
                    }
                }
            }
            done += slice.count
            progress?(done)
        }
    }

    private static func read(path: String) -> Result<Loaded, Failure> {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
              let first = descriptors.first else {
            return .failure(.noDescriptors)   // first face only, also for .ttc
        }
        let probe = CTFontCreateWithFontDescriptor(first, 20, nil)
        return .success(Loaded(descriptor: first, faceCount: descriptors.count, probe: probe))
    }
}
