import CoreText
import SwiftUI

/// A face plus the designer's playground settings: everything a template needs to draw text in it.
struct FaceSpec: Hashable {
    let path: String            // the family's regular file; the fallback when no style is picked
    var settings: TypeSettings
    /// Every file in the family, so a template can find a real italic or bold. Empty when unknown.
    var siblings: [String] = []
    /// Weight of each file (CSS scale) as the library recorded it. Core Text's own trait is a fallback.
    var weights: [String: Int] = [:]
    var resolvedPath: String { settings.stylePath ?? path }
}

extension FontLoader {
    private static let memoLock = NSLock()
    nonisolated(unsafe) private static var infoMemo: [String: FaceInfo] = [:]
    nonisolated(unsafe) private static var fontMemo: [String: CTFont] = [:]

    /// Axes and features for a loaded file. Memoised: reading features is not free.
    func info(_ path: String) -> FaceInfo? {
        Self.memoLock.lock()
        if let hit = Self.infoMemo[path] { Self.memoLock.unlock(); return hit }
        Self.memoLock.unlock()
        guard case .success(let loaded)? = cached(path) else { return nil }
        let info = FaceInspector.read(loaded)
        Self.memoLock.lock(); Self.infoMemo[path] = info; Self.memoLock.unlock()
        return info
    }

    /// The font for a face and settings at a role size. Memoised, so a slider drag
    /// builds one font per value and a lazy grid re-reads it for free.
    func styledFont(_ face: FaceSpec, ratio: CGFloat) -> CTFont? {
        let path = face.resolvedPath
        guard case .success(let loaded)? = cached(path), let info = info(path) else { return nil }
        let key = "\(path)|\(face.settings.hashValue)|\(ratio)"
        Self.memoLock.lock()
        if let hit = Self.fontMemo[key] { Self.memoLock.unlock(); return hit }
        Self.memoLock.unlock()
        let font = face.settings.font(from: loaded, axisInfo: info.axes, ratio: ratio)
        Self.memoLock.lock()
        if Self.fontMemo.count > 4000 { Self.fontMemo.removeAll() }
        Self.fontMemo[key] = font
        Self.memoLock.unlock()
        return font
    }
}

/// Text in a face with its playground settings. Like `FontText`, it only reads caches:
/// no state, no disk, safe inside a lazy grid. `ratio` is the template's role size
/// relative to the face's base size (headline 1.0, caption 0.7 ...).
struct FaceText: View {
    let face: FaceSpec
    let text: String
    var ratio: CGFloat = 1
    var tick = 0
    var useLineHeight = true
    /// Templates adjust tracking per role: added to the playground's tracking (em).
    var trackBias: Double = 0
    /// A role's own line height as a multiple of the size. Nil uses the playground's.
    var leading: Double?
    /// The width the text will be laid out in, in points. Lets tight display type break its own lines (see `TightLines`).
    var wrapWidth: CGFloat?
    var lineAlignment: HorizontalAlignment = .leading

    /// Space added between lines. A template's own line height may tighten below the font's natural spacing;
    /// the playground's may not (as before).
    private func extraLeading(size: CGFloat, natural: CGFloat) -> CGFloat {
        let wanted = CGFloat(leading ?? face.settings.lineHeight) * size - natural
        return max(0, wanted)
    }

    var body: some View {
        if let font = FontLoader.shared.styledFont(face, ratio: ratio) {
            let size = CTFontGetSize(font)
            let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            let tracking = CGFloat(face.settings.tracking + trackBias) * size
            if let leading, let wrapWidth, CGFloat(leading) * size < natural {
                // Tighter than the font's own spacing: lay the lines out one by one.
                TightLines(text: text, font: font, tracking: tracking, width: wrapWidth,
                           pitch: CGFloat(leading) * size, natural: natural, alignment: lineAlignment)
            } else {
                Text(text)
                    .font(Font(font))
                    .tracking(tracking)
                    .exactLineHeight(leading.map { CGFloat($0) * size }, natural: natural,
                                     fallbackSpacing: useLineHeight ? extraLeading(size: size, natural: natural) : 0)
            }
        } else {
            Text(text).font(.system(size: CGFloat(face.settings.size) * ratio)).opacity(0)   // reserve the space
        }
    }
}

/// Display type set tighter than the font's natural line spacing (a poster headline at 0.9).
///
/// SwiftUI's own line height cannot do this safely. It keeps ink that falls outside the text's frame,
/// and the window then cuts that ink off. So the lines are broken here with Core Text, each one is its
/// own `Text` at its natural height, and the stack pulls them together by a negative gap.
/// React: splitting the string into lines yourself and stacking spans with `margin-top: -0.1em`.
struct TightLines: View {
    let text: String
    let font: CTFont
    let tracking: CGFloat
    let width: CGFloat
    let pitch: CGFloat
    let natural: CGFloat
    let alignment: HorizontalAlignment

    /// Where a typesetter would break `text` at `width`. Trailing spaces are dropped.
    static func lines(_ text: String, font: CTFont, tracking: CGFloat, width: CGFloat) -> [String] {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let setter = CTTypesetterCreateWithAttributedString(attributed)
        let ns = text as NSString
        var out: [String] = []
        var start = 0
        while start < ns.length {
            let count = max(1, CTTypesetterSuggestLineBreak(setter, start, Double(width)))
            out.append(ns.substring(with: NSRange(location: start, length: count)).trimmingCharacters(in: .whitespaces))
            start += count
        }
        return out
    }

    var body: some View {
        let list = Self.lines(text, font: font, tracking: tracking, width: width)
        VStack(alignment: alignment, spacing: pitch - natural) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, line in
                Text(line).font(Font(font)).tracking(tracking).lineLimit(1).fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .frame(width: width, alignment: Alignment(horizontal: alignment, vertical: .top))
    }
}

extension View {
    /// A template's own line height when it is at least the font's natural spacing. macOS 26 can set an
    /// exact one. Earlier systems get extra line spacing.
    @ViewBuilder
    func exactLineHeight(_ points: CGFloat?, natural: CGFloat, fallbackSpacing: CGFloat) -> some View {
        if let points, points >= natural, #available(macOS 26.0, *) {
            self.lineHeight(.exact(points: points)).fixedSize(horizontal: false, vertical: true)
        } else {
            self.lineSpacing(fallbackSpacing)
        }
    }
}
