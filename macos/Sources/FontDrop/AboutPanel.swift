import AppKit

/// The About window. macOS draws the icon (the AppIcon asset), the name, the version and build (CFBundleShortVersionString
/// and CFBundleVersion) and the copyright (NSHumanReadableCopyright) from the app bundle. This file adds the credits.
enum AboutPanel {
    /// Credits as links: the two bundled fonts' licence, and the two type guides behind Recommended for text.
    static func credits() -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let text = NSMutableAttributedString(string: Lexicon.About.credits, attributes: base)
        func link(_ word: String, _ url: String) {
            let range = (text.string as NSString).range(of: word)
            guard range.location != NSNotFound, let target = URL(string: url) else { return }
            text.addAttributes([.link: target, .foregroundColor: NSColor.linkColor], range: range)
        }
        link("SIL Open Font License 1.1", "https://openfontlicense.org")
        link("Typewolf", "https://www.typewolf.com")
        link("Butterick\u{2019}s Practical Typography", "https://practicaltypography.com")
        return text
    }

    @MainActor
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    /// The lines the About window shows from the bundle, for a test: "FontDrop", "0.2", "2".
    static func bundleFacts(_ bundle: Bundle = .main) -> (name: String, version: String, build: String) {
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? "FontDrop"
        return (name, info["CFBundleShortVersionString"] as? String ?? "", info["CFBundleVersion"] as? String ?? "")
    }
}
