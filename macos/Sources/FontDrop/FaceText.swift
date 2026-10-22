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

    /// Space added between lines. A template's own line height may tighten below the font's natural spacing;
    /// the playground's may not (as before).
    private func extraLeading(size: CGFloat, natural: CGFloat) -> CGFloat {
        let wanted = CGFloat(leading ?? face.settings.lineHeight) * size - natural
        return leading == nil ? max(0, wanted) : wanted
    }

    var body: some View {
        if let font = FontLoader.shared.styledFont(face, ratio: ratio) {
            let size = CTFontGetSize(font)
            let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            Text(text)
                .font(Font(font))
                .tracking(CGFloat(face.settings.tracking + trackBias) * size)
                .exactLineHeight(leading.map { CGFloat($0) * size }, natural: natural, fallbackSpacing: useLineHeight ? extraLeading(size: size, natural: natural) : 0)
        } else {
            Text(text).font(.system(size: CGFloat(face.settings.size) * ratio)).opacity(0)   // reserve the space
        }
    }
}

extension View {
    /// A template's own line height. macOS 26 can set an exact one, which also tightens below the font's
    /// natural spacing (poster type). Earlier systems get extra line spacing, which can only loosen.
    ///
    /// SwiftUI keeps the first baseline where the font's natural ascent puts it and only changes the pitch
    /// between lines, so tight type drifts down and its last line falls outside the view. CSS splits the
    /// difference between the first and last line (half-leading). The offset does the same.
    @ViewBuilder
    func exactLineHeight(_ points: CGFloat?, natural: CGFloat, fallbackSpacing: CGFloat) -> some View {
        if let points, #available(macOS 26.0, *) {
            self.lineHeight(.exact(points: points))
                .fixedSize(horizontal: false, vertical: true)
                .offset(y: -max(0, natural - points) / 2)
        } else {
            self.lineSpacing(fallbackSpacing)
        }
    }
}
