import CoreText
import SwiftUI

/// A face plus the designer's playground settings: everything a template needs to draw text in it.
struct FaceSpec: Hashable {
    let path: String            // the family's regular file; the fallback when no style is picked
    var settings: TypeSettings
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

    var body: some View {
        if let font = FontLoader.shared.styledFont(face, ratio: ratio) {
            let size = CTFontGetSize(font)
            let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            Text(text)
                .font(Font(font))
                .tracking(CGFloat(face.settings.tracking) * size)
                .lineSpacing(useLineHeight ? max(0, CGFloat(face.settings.lineHeight) * size - natural) : 0)
        } else {
            Text(text).font(.system(size: CGFloat(face.settings.size) * ratio)).opacity(0)   // reserve the space
        }
    }
}
