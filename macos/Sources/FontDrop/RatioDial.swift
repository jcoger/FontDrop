import AppKit
import SwiftUI

// The ratio dial: five stops on an arc, 1.333 straight up. Turning snaps to a stop and locks the scale.
// Pressing the pivot (or Space) hands the sizes back to Auto. Design: docs/design/2026-11-05-instrument-look.md,
// "Dial" and Paper board 13.
//
//   DialMath    the pure part: stops, angles, snapping, the interval names, the Auto ratio
//   RatioDial   the view: shapes from Theme tokens, drag, scroll wheel, arrow keys, VoiceOver, haptic click
//
// React: DialMath is a utils module; RatioDial is a controlled component (value in, onTurn/onAuto out) that
// keeps only the transient "hand is on it" state to itself.

enum DialMath {
    /// The five stops, left to right.
    static let stops: [Double] = TypeScale.ratios
    /// Degrees between neighbouring stops. 1.333 (index 2) sits at 0, straight up.
    static let spread: Double = 27
    /// The needle can lean a little past the end stops while a hand drags it.
    static let reach: Double = spread * 2 + 8

    static func angle(ofStop index: Int) -> Double { Double(index - 2) * spread }

    /// The needle angle for any ratio: stop angles, joined by straight lines in between. Auto sits between stops.
    static func angle(ofRatio ratio: Double) -> Double {
        if ratio <= stops[0] { return max(-reach, angle(ofStop: 0) - (stops[0] - ratio) / (stops[1] - stops[0]) * spread) }
        if ratio >= stops[4] { return min(reach, angle(ofStop: 4) + (ratio - stops[4]) / (stops[4] - stops[3]) * spread) }
        for i in 0..<4 where ratio <= stops[i + 1] {
            let t = (ratio - stops[i]) / (stops[i + 1] - stops[i])
            return angle(ofStop: i) + t * spread
        }
        return 0
    }

    /// The stop nearest to a needle angle (degrees from straight up, clockwise positive).
    static func stopIndex(nearestToAngle angle: Double) -> Int {
        min(max(Int((angle / spread).rounded()) + 2, 0), stops.count - 1)
    }

    static func stopIndex(nearestToRatio ratio: Double) -> Int {
        stops.indices.min { abs(stops[$0] - ratio) < abs(stops[$1] - ratio) } ?? 2
    }

    /// The stop `delta` places from `index`, held inside the arc.
    static func step(from index: Int, by delta: Int) -> Int { min(max(index + delta, 0), stops.count - 1) }

    /// Needle angle for a point relative to the pivot (y grows downward), clamped to the reach.
    static func angle(dx: Double, dy: Double) -> Double {
        let degrees = atan2(dx, -dy) * 180 / .pi
        return min(max(degrees, -reach), reach)
    }

    static func intervalName(_ ratio: Double) -> String {
        switch stopIndex(nearestToRatio: ratio) {
        case 0: Lexicon.Dial.minorThird
        case 1: Lexicon.Dial.majorThird
        case 2: Lexicon.Dial.fourth
        case 3: Lexicon.Dial.fifth
        default: Lexicon.Dial.golden
        }
    }

    /// The ratio Auto's sizes add up to: the headline's multiple of body, taken over its steps up the scale.
    /// Nil when the sizes are not known yet.
    static func autoRatio(headline: Double, body: Double, steps: Int) -> Double? {
        guard headline > 0, body > 0, steps > 0 else { return nil }
        return pow(headline / body, 1 / Double(steps))
    }

    /// Whether a ratio sits on a stop closely enough to be named by it.
    static func isOnStop(_ ratio: Double) -> Bool { stops.contains { abs($0 - ratio) < 0.004 } }

    /// The value the readout prints: a stop as itself ("1.333"), Auto's own number to two places ("1.32").
    static func valueLabel(_ ratio: Double) -> String {
        isOnStop(ratio) ? TypeScale.ratioLabel(stops[stopIndex(nearestToRatio: ratio)]) : String(format: "%.2f", ratio)
    }
}

/// The scroll wheel's arithmetic: one stop for every 14 points of travel, the remainder kept between events.
struct DialScroll: Equatable {
    static let pointsPerStop: CGFloat = 14
    var remainder: CGFloat = 0

    /// Adds one event's travel. Returns the stops to move: +1 turns up, -1 down. A line-based wheel
    /// (no precise deltas) counts six points a line.
    mutating func add(deltaY: CGFloat, precise: Bool) -> [Int] {
        remainder += precise ? deltaY : deltaY * 6
        var out: [Int] = []
        while abs(remainder) >= Self.pointsPerStop {
            let direction = remainder > 0 ? 1 : -1
            remainder -= CGFloat(direction) * Self.pointsPerStop
            out.append(direction)
        }
        return out
    }

    mutating func reset() { remainder = 0 }
}

/// The dial's live state for the scroll monitor, held in a reference so the one installed monitor always sees the
/// current view. `step` is replaced on every body pass with a closure over that pass's scale, Auto ratio and turn handler.
@MainActor
final class DialLive {
    var hovering = false
    var step: (Int) -> Void = { _ in }
    private var scroll = DialScroll()
    private var monitor: Any?

    /// The wheel (or two-finger scroll) steps the dial while the pointer is over it. Returns true when it took the event.
    func scrolled(deltaY: CGFloat, precise: Bool, ended: Bool) -> Bool {
        guard hovering else { return false }
        for direction in scroll.add(deltaY: deltaY, precise: precise) { step(direction) }
        if ended { scroll.reset() }
        return true
    }

    func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let delta = event.scrollingDeltaY, precise = event.hasPreciseScrollingDeltas
            let ended = event.phase == .ended || event.momentumPhase == .ended
            let took = MainActor.assumeIsolated { self?.scrolled(deltaY: delta, precise: precise, ended: ended) ?? false }
            return took ? nil : event
        }
    }

    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        scroll.reset()
    }
}

// MARK: - The dial

struct RatioDial: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    let scale: TypeScale
    /// Where the grey needle rests in Auto.
    let autoRatio: Double?
    /// A hand turned the dial to this stop. The scale locks.
    let onTurn: (Double) -> Void
    /// The pivot was pressed (or Space): Auto again.
    let onAuto: () -> Void

    @State private var dragAngle: Double?
    @State private var turning = false
    @State private var settle: Task<Void, Never>?
    /// What the scroll-wheel monitor reads. The monitor is installed once, so it must not capture this view's values:
    /// it reads them from here, and every body pass refreshes the box.
    @State private var live = DialLive()

    // The drawing is laid out on a 160 x 100 board and scaled to the frame.
    private static let board = CGSize(width: 160, height: 100)
    private static let pivot = CGPoint(x: 80, y: 86)
    private static let radius: CGFloat = 62

    private var currentStop: Int { DialMath.stopIndex(nearestToRatio: scale.locked ? scale.ratio : (autoRatio ?? 1.333)) }
    private var restingAngle: Double { scale.locked ? DialMath.angle(ofRatio: scale.ratio) : DialMath.angle(ofRatio: autoRatio ?? 1.333) }
    private var shownAngle: Double { dragAngle ?? restingAngle }
    private var glow: [(radius: CGFloat, opacity: Double)] {
        guard scale.locked, contrast != .increased else { return [] }
        return turning ? theme.signalGlowTurning : theme.signalGlow
    }

    var body: some View {
        let _ = live.step = { direction in
            turn(toStop: DialMath.step(from: currentStop, by: direction), onlyIfChanged: false)
        }
        GeometryReader { geo in
            let k = min(geo.size.width / Self.board.width, geo.size.height / Self.board.height)
            ZStack(alignment: .topLeading) {
                arc
                ForEach(0..<DialMath.stops.count, id: \.self) { i in stopTick(i) }
                needle
                pivot
            }
            .frame(width: Self.board.width, height: Self.board.height, alignment: .topLeading)
            .scaleEffect(k, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { drag in
                    let pivotPoint = CGPoint(x: Self.pivot.x * k, y: Self.pivot.y * k)
                    let angle = DialMath.angle(dx: drag.location.x - pivotPoint.x, dy: drag.location.y - pivotPoint.y)
                    dragAngle = angle
                    handTouched()
                    turn(toStop: DialMath.stopIndex(nearestToAngle: angle), onlyIfChanged: true)
                }
                .onEnded { _ in
                    withMotion(.spring(response: 0.28, dampingFraction: 0.7)) { dragAngle = nil }
                    settleSoon()
                })
            .onTapGesture(count: 1) { location in
                // A press on the pivot hands the sizes back to Auto.
                let p = CGPoint(x: Self.pivot.x * k, y: Self.pivot.y * k)
                let dist: CGFloat = hypot(location.x - p.x, location.y - p.y)
                let hit: CGFloat = 16
                if dist <= hit { returnToAuto() }
            }
            .onHover { live.hovering = $0 }
        }
        .frame(height: 88)
        .focusable()
        .onKeyPress(keys: [.leftArrow, .downArrow, .rightArrow, .upArrow, .space, .return]) { press in
            switch press.key {
            case .leftArrow, .downArrow: turn(toStop: DialMath.step(from: currentStop, by: -1), onlyIfChanged: false)
            case .rightArrow, .upArrow: turn(toStop: DialMath.step(from: currentStop, by: 1), onlyIfChanged: false)
            default: returnToAuto()
            }
            return .handled
        }
        .onAppear { live.installMonitor() }
        .onDisappear { live.removeMonitor() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Lexicon.Dial.label)
        .accessibilityValue(Lexicon.Dial.accessibilityValue(scale, autoRatio: autoRatio))
        .accessibilityHint(Lexicon.Dial.hint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: turn(toStop: DialMath.step(from: currentStop, by: 1), onlyIfChanged: false)
            case .decrement: turn(toStop: DialMath.step(from: currentStop, by: -1), onlyIfChanged: false)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Lexicon.Dial.returnToAuto) { returnToAuto() }
    }

    // MARK: Parts

    private func point(angle degrees: Double, radius r: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: Self.pivot.x + CGFloat(sin(a)) * r, y: Self.pivot.y - CGFloat(cos(a)) * r)
    }

    private var arc: some View {
        Path { p in
            p.addArc(center: Self.pivot, radius: Self.radius,
                     startAngle: .degrees(-90 - DialMath.reach + 0), endAngle: .degrees(-90 + DialMath.reach), clockwise: false)
        }
        .stroke(theme.dialArc.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 5]))
    }

    private func stopTick(_ i: Int) -> some View {
        let angle = DialMath.angle(ofStop: i)
        let lit = scale.locked && i == currentStop
        return Path { p in
            p.move(to: point(angle: angle, radius: Self.radius + 5))
            p.addLine(to: point(angle: angle, radius: Self.radius + (lit ? 16 : 12)))
        }
        .stroke(lit ? theme.signal.color : theme.dialStop.color, style: StrokeStyle(lineWidth: lit ? 2.5 : 1.5, lineCap: .round))
        .modifier(Glow(layers: lit ? glow : [], color: theme.signal.color))
        .animation(nil, value: scale.ratio)
    }

    private var needle: some View {
        let length = Self.radius - 8
        let width: CGFloat = (scale.locked ? 3 : 1.5) + (contrast == .increased ? 1 : 0)
        return Capsule()
            .fill(scale.locked ? theme.signal.color : theme.textSecondary.color)
            .frame(width: width, height: length)
            .modifier(Glow(layers: glow, color: theme.signal.color))
            .position(x: Self.pivot.x, y: Self.pivot.y - length / 2)
            .rotationEffect(.degrees(shownAngle), anchor: UnitPoint(x: Self.pivot.x / Self.board.width, y: Self.pivot.y / Self.board.height))
            .animation(Motion.ok(Motion.spring), value: restingAngle)
    }

    private var pivot: some View {
        ZStack {
            Circle().fill(theme.textPrimary.color)
            Circle().fill(theme.screenFill.color).frame(width: 5, height: 5)
        }
        .frame(width: 12, height: 12)
        .position(Self.pivot)
    }

    // MARK: Behaviour

    private func handTouched() {
        turning = true
        settle?.cancel()
    }

    /// The glow settles back 300 ms after the last touch.
    private func settleSoon() {
        settle?.cancel()
        settle = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withMotion(.easeOut(duration: 0.3)) { turning = false }
        }
    }

    private func turn(toStop index: Int, onlyIfChanged: Bool) {
        let ratio = DialMath.stops[index]
        let changed = !(scale.locked && abs(scale.ratio - ratio) < 0.0005)
        if onlyIfChanged && !changed { return }
        if changed { haptic() }
        handTouched()
        onTurn(ratio)
        if dragAngle == nil { settleSoon() }
    }

    private func returnToAuto() {
        guard scale.locked else { return }
        haptic()
        withMotion(.easeOut(duration: 0.2)) { turning = false }
        settle?.cancel()
        onAuto()
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

/// `withAnimation` that does nothing under Reduce Motion.
@MainActor
func withMotion<R>(_ animation: Animation? = .default, _ body: () throws -> R) rethrows -> R {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? try body() : try withAnimation(animation, body)
}
