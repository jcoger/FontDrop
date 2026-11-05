import AppKit
import SwiftUI

// Motion: one small token set, the way Theme.swift holds the colors. Nothing frequent bounces, nothing runs past 0.35 s.
// Every animation goes through `Motion.ok`, `Motion.run` or a modifier below, so Reduce Motion is honoured in one place:
// movement becomes a short fade or an instant change.
//
// React: a `motion.ts` of durations and easings, plus a `useReducedMotion()` guard around each transition.

enum Motion {
    /// The system setting. Read live, so a change takes effect without a relaunch.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Hovers, small state changes, the inspector fade. 0.15 s.
    static let quick = Animation.easeOut(duration: 0.15)
    /// Screen changes, zoom, panels. 0.25 s.
    static let standard = Animation.easeInOut(duration: 0.25)
    /// The selection pill and the dial. Critically damped: it glides and settles, it does not bounce. About 0.3 s.
    static let spring = Animation.spring(response: 0.28, dampingFraction: 1)
    /// How far a screen slides in, in points.
    static let travel: CGFloat = 7

    /// The animation, or none when Reduce Motion is on.
    static func ok(_ animation: Animation) -> Animation? { reduced ? nil : animation }

    /// `withAnimation`, skipped under Reduce Motion.
    @discardableResult
    static func run<R>(_ animation: Animation = standard, _ body: () throws -> R) rethrows -> R {
        reduced ? try body() : try withAnimation(animation, body)
    }
}

// MARK: - Screen changes

/// Display, Text and Set cross-fade with a small slide in the direction of travel (Set is to the right of Text).
/// Reduce Motion keeps the fade and drops the slide. The scan screen handing off to the grid is the same fade, no slide.
private struct ScreenTransition: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Key: Hashable { let screen: Screen; let scan: Bool; let empty: Bool }

    func body(content: Content) -> some View {
        let key = Key(screen: model.screen, scan: model.showsScanScreen, empty: model.libraryIsEmpty)
        let dx = reduceMotion || key.scan || key.empty ? 0 : model.screenTravel * Motion.travel
        ZStack {
            content
                .id(key)
                .transition(.asymmetric(insertion: .modifier(active: Slide(dx: dx, opacity: 0), identity: Slide(dx: 0, opacity: 1)),
                                        removal: .opacity))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Motion.standard, value: key)
    }

    private struct Slide: ViewModifier {
        let dx: CGFloat, opacity: Double
        func body(content: Content) -> some View { content.offset(x: dx).opacity(opacity) }
    }
}

// MARK: - Selection

/// When the key changes, the content dips and returns to full opacity over `quick`. The inspector reads as one
/// panel whose contents change, with no second copy of it on screen. Reduce Motion: no dip, the content swaps.
private struct SelectionFade<Key: Hashable>: ViewModifier {
    let key: Key
    @State private var opacity = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onChange(of: key) { _, _ in
                guard !Motion.reduced else { return }
                opacity = 0.35
                withAnimation(Motion.quick) { opacity = 1 }
            }
    }
}

extension View {
    /// Cross-fades what a screen shows when `model.screen` changes. One hook, at the content router.
    func screenTransition() -> some View { modifier(ScreenTransition()) }
    /// Fades the content in again whenever `key` changes.
    func selectionFade<Key: Hashable>(_ key: Key) -> some View { modifier(SelectionFade(key: key)) }
}

/// The namespace a list or grid shares, so its selection mark glides from one row or tile to the next.
private struct GlideKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues {
    var glide: Namespace.ID? {
        get { self[GlideKey.self] }
        set { self[GlideKey.self] = newValue }
    }
}

/// The selection mark: a filled pill (rows) or a ring (tiles). Where the list gave a namespace, one mark moves
/// between rows (matchedGeometryEffect). Without one it just appears. Reduce Motion: it jumps.
struct SelectionMark<S: InsettableShape, F: ShapeStyle>: View {
    @Environment(\.glide) private var glide
    let on: Bool
    let shape: S
    let fill: F
    var ring: CGFloat?

    var body: some View {
        ZStack {
            if on { mark }
        }
        .animation(Motion.ok(Motion.spring), value: on)
    }

    @ViewBuilder
    private var mark: some View {
        let base = Group {
            if let ring { shape.strokeBorder(fill, lineWidth: ring) } else { shape.fill(fill) }
        }
        if let glide {
            base.matchedGeometryEffect(id: "selection", in: glide).transition(.identity)
        } else {
            base
        }
    }
}
