import CoreText
import Foundation

/// Loads fonts straight from a file URL with Core Text. No global registration:
/// the descriptor is private to this process's use, nothing lands in the system font list.
final class FontLoader: @unchecked Sendable {
    static let shared = FontLoader()

    enum Failure: Error, Hashable, Sendable {
        case noDescriptors   // Core Text could not read the file at all
        case noGlyphs        // loaded, but cannot draw the name or the sample word
    }

    /// What a view needs: a descriptor to size later, and the text that font can actually draw.
    struct Loaded: @unchecked Sendable {
        let descriptor: CTFontDescriptor
        let sample: String
        let faceCount: Int
        func font(size: CGFloat) -> CTFont { CTFontCreateWithFontDescriptor(descriptor, size, nil) }
    }

    private let lock = NSLock()
    private var cache: [String: Result<Loaded, Failure>] = [:]

    static let fallbackSample = "Hamburgefonstiv"

    /// Safe to call from any thread. First call per path reads the file.
    func load(path: String, preferredText: String) -> Result<Loaded, Failure> {
        lock.lock()
        if let hit = cache[path] { lock.unlock(); return hit }
        lock.unlock()

        let result = Self.read(path: path, preferredText: preferredText)

        lock.lock()
        cache[path] = result
        lock.unlock()
        return result
    }

    /// Cache lookup only; never touches the disk. Cheap enough to call from a view body.
    func load(cached path: String) -> Result<Loaded, Failure>? {
        lock.lock(); defer { lock.unlock() }
        return cache[path]
    }

    var cachedCount: Int { lock.lock(); defer { lock.unlock() }; return cache.count }

    var failures: [String: Failure] {
        lock.lock(); defer { lock.unlock() }
        var out: [String: Failure] = [:]
        for (k, v) in cache { if case .failure(let f) = v { out[k] = f } }
        return out
    }

    func clear() { lock.lock(); cache.removeAll(); lock.unlock(); stepLock.lock(); stepLog.removeAll(); stepLock.unlock() }

    /// Per-step timings (ms) per path, filled only when `profile` is true. Bench use.
    struct Step: Sendable { var path: String; var descriptors: Double; var create: Double; var cover: Double }
    nonisolated(unsafe) static var profile = false
    private let stepLock = NSLock()
    private var stepLog: [Step] = []
    var steps: [Step] { stepLock.lock(); defer { stepLock.unlock() }; return stepLog }

    private static func read(path: String, preferredText: String) -> Result<Loaded, Failure> {
        let t0 = DispatchTime.now()
        let url = URL(fileURLWithPath: path) as CFURL
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
              let first = descriptors.first else {
            return .failure(.noDescriptors)   // first face only, also for .ttc
        }
        let t1 = DispatchTime.now()
        let probe = CTFontCreateWithFontDescriptor(first, 20, nil)
        let t2 = DispatchTime.now()
        var result: Result<Loaded, Failure> = .failure(.noGlyphs)
        for text in [preferredText, fallbackSample] where covers(text, probe) {
            result = .success(Loaded(descriptor: first, sample: text, faceCount: descriptors.count))
            break
        }
        if profile {
            let t3 = DispatchTime.now()
            let st = Step(path: path, descriptors: ms(t0, t1), create: ms(t1, t2), cover: ms(t2, t3))
            shared.stepLock.lock(); shared.stepLog.append(st); shared.stepLock.unlock()
        }
        return result
    }

    private static func covers(_ text: String, _ font: CTFont) -> Bool {
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        return CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
    }
}
