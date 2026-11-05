import Foundation
import Observation

// The brand's type scale: one body size and one ratio, shared by the Display and Reading faces.
//
//   TypeScale   the numbers (a plain Codable struct) and the rule: size = body x ratio^step
//   ScaleStore  one TypeScale per brand, saved to a small JSON file next to the library DB
//
// Unlocked (the default), templates fit their type to the font (TypeFit.swift) and these numbers are unused.
// Locked, every role in a template takes its size from the scale, whatever the font.

struct TypeScale: Codable, Hashable, Sendable {
    /// The Reading size every other size steps from, in points.
    var body: Double = 15
    /// How much each step up multiplies the size.
    var ratio: Double = 1.333
    /// Off: Fit decides every size. On: `body x ratio^step`.
    var locked = false

    static let ratios: [Double] = [1.2, 1.25, 1.333, 1.5, 1.618]
    static let bodyRange: ClosedRange<Double> = 9...24
    /// The body size the Paper boards were drawn at.
    static let boardBody: Double = 15

    /// The size of a role `step` steps from body (label -1, body 0, deck +1, headline about +5).
    func size(step: Int) -> Double { body * pow(ratio, Double(step)) }

    /// The standard ratio closest to `value`.
    static func nearestRatio(_ value: Double) -> Double {
        ratios.min { abs($0 - value) < abs($1 - value) } ?? 1.333
    }

    /// The step a board size sits at on the standard scale (body 15, ratio 1.333). 88 is +6, 44 is +4, 20 is +1,
    /// 12 is -1. The nudge keeps the in-between 13 on the label side, with the 12s.
    static func defaultStep(px: CGFloat) -> Int {
        guard px > 0 else { return 0 }
        return Int((log(Double(px) / boardBody) / log(1.333) - 0.05).rounded())
    }
}

/// One scale per brand. Saved as JSON next to the library DB (`<db>.scale.json`), so a test DB copy gets
/// its own file and never touches the live one. Same shape as `TypeSettingsStore`.
@MainActor @Observable
final class ScaleStore {
    private(set) var map: [String: TypeScale] = [:]
    private let url: URL
    private let persist: Bool
    private var saveTask: Task<Void, Never>?

    init(dbPath: String, persist: Bool = true) {
        url = URL(fileURLWithPath: dbPath + ".scale.json")
        self.persist = persist
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: TypeScale].self, from: data) {
            map = decoded
        }
    }

    private static func key(_ brand: Int64?) -> String { "\(brand ?? 0)" }

    func scale(brand: Int64?) -> TypeScale { map[Self.key(brand)] ?? TypeScale() }

    func update(brand: Int64?, _ change: (inout TypeScale) -> Void) {
        var s = scale(brand: brand)
        change(&s)
        s.body = min(max(s.body, TypeScale.bodyRange.lowerBound), TypeScale.bodyRange.upperBound)
        map[Self.key(brand)] = s
        scheduleSave()
    }

    private func scheduleSave() {
        guard persist else { return }       // screenshot, bench and test runs read the scale but never write it
        let url = self.url
        saveTask?.cancel()
        let snapshot = map
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))      // a slider drag is many updates; write once
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
