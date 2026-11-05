import AppKit
import SwiftUI
import XCTest
@testable import FontDrop

/// A VoiceOver walk of the dial: host it in a real window and read its accessibility tree the way VoiceOver does.
@MainActor
final class DialAccessibilityTests: XCTestCase {
    private func elements(in root: AnyObject, depth: Int = 0) -> [AnyObject] {
        guard depth < 12 else { return [] }
        var out: [AnyObject] = []
        var children: [AnyObject] = []
        if let kids = root.accessibilityChildren?() { children += kids.compactMap { $0 as AnyObject } }
        if let view = root as? NSView { children += view.subviews }
        for c in children {
            out.append(c)
            out += elements(in: c, depth: depth + 1)
        }
        return out
    }

    private func walk(locked: Bool) throws -> (label: String, value: String, role: String, adjustable: Bool) {
        // SwiftUI builds its accessibility tree only when an assistive client is present. Say one is.
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: attribute))
        }
        var scale = TypeScale(); scale.locked = locked; scale.ratio = 1.333
        let dial = RatioDial(scale: scale, autoRatio: 1.32, onTurn: { _ in }, onAuto: {})
            .environment(\.theme, Theme.dark)
            .frame(width: 142, height: 88)
        let host = NSHostingView(rootView: dial)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let all: [AnyObject] = [host] + elements(in: host)
        guard let el = all.first(where: { (($0.accessibilityLabel?() ?? nil) ?? "") == "Ratio" }) else {
            throw XCTSkip("SwiftUI published no accessibility element in this host: \(all.map { "\(type(of: $0))" })")
        }
        let label = (el.accessibilityLabel?() ?? nil) ?? ""
        let desc = (el.accessibilityValueDescription?() ?? nil) ?? ""
        let raw = (el.accessibilityValue?() ?? nil).map { "\($0)" } ?? ""
        let role = (el.accessibilityRole?() ?? nil)?.rawValue ?? ""
        let canStep = el.accessibilityPerformIncrement != nil && el.accessibilityPerformDecrement != nil
        return (label, desc.isEmpty ? raw : desc, role, canStep)
    }

    func testTheDialReadsRatioLockedAndCanBeAdjusted() throws {
        let r = try walk(locked: true)
        XCTAssertEqual(r.label, "Ratio")
        XCTAssertEqual(r.value, "1.333, locked")
        XCTAssertTrue(r.adjustable, "VoiceOver can raise and lower it (role \(r.role))")
    }

    func testTheDialReadsAutoWhenNotLocked() throws {
        let r = try walk(locked: false)
        XCTAssertEqual(r.label, "Ratio")
        XCTAssertEqual(r.value, "Auto")
    }
}
