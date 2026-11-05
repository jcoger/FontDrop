import FontDropCore
import Foundation
import Observation

// The brand's type scale: one body size and one ratio, shared by the Display and Reading faces.
//
//   TypeScale   the numbers (a plain Codable struct) and the rule: size = body x ratio^step
//   ScaleStore  one TypeScale per brand, saved in the library database (the core's `brand_scale` table)
//
// Unlocked (the default), templates fit their type to the font (TypeFit.swift) and these numbers are unused.
// Locked, every role in a template takes its size from the scale, whatever the font.

struct TypeScale: Codable, Hashable, Sendable {
    /// The Reading size every other size steps from, in points.
    var body: Double = 15
    /// How much each step up multiplies the size.
    var ratio: Double = 1.333
    /// Off: Auto decides every size. On: `body x ratio^step`.
    var locked = false
    /// Characters per line for body text. Nil: the type rules' default (`TextRules`).
    var measure: Int?
    /// Body line height as a multiple of the size. Nil: it follows the measure.
    var lineHeight: Double?

    static let ratios: [Double] = [1.2, 1.25, 1.333, 1.5, 1.618]
    static let bodyRange: ClosedRange<Double> = 9...24
    /// The body size the Paper boards were drawn at.
    static let boardBody: Double = 15

    /// The size of a role `step` steps from body (label -1, body 0, deck +1, headline about +5).
    func size(step: Int) -> Double { body * pow(ratio, Double(step)) }

    /// 1.2, 1.25, 1.333, 1.5, 1.618: as many digits as the number has.
    static func ratioLabel(_ ratio: Double) -> String {
        let s = String(format: "%.3f", ratio)
        return s.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

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

/// One scale per brand, kept in memory and saved to the library database (`brand_scale`, owned by the core).
/// Screenshot, bench and test runs read it but never write it. A brand with no id yet (`nil`) lives in memory only.
@MainActor @Observable
final class ScaleStore {
    private(set) var map: [Int64: TypeScale] = [:]
    private var memoryOnly = TypeScale()
    private let writer: WriteBehind<Int64>

    init(persist: Bool = true) {
        var read: (@MainActor (Int64) -> TypeScale?)?
        writer = WriteBehind(persist: persist) { id in
            guard let s = read?(id) else { return nil }
            let row = BrandScale(brandId: id, body: s.body, ratio: s.ratio, locked: s.locked,
                                 measure: s.measure.map(UInt32.init), lineHeight: s.lineHeight)
            return { try $0.scaleSet(scale: row) }
        }
        read = { [weak self] id in self?.map[id] }
    }

    /// The library is open: read every brand's scale from it, and write changes to it from now on.
    func attach(_ library: Library) {
        writer.library = library
        let rows = (try? library.scalesList()) ?? []
        map = Dictionary(rows.map { row in
            (row.brandId, TypeScale(body: row.body, ratio: row.ratio, locked: row.locked,
                                    measure: row.measure.map(Int.init), lineHeight: row.lineHeight))
        }, uniquingKeysWith: { _, b in b })
    }

    func scale(brand: Int64?) -> TypeScale {
        guard let brand else { return memoryOnly }
        return map[brand] ?? TypeScale()
    }

    func update(brand: Int64?, _ change: (inout TypeScale) -> Void) {
        var s = scale(brand: brand)
        change(&s)
        s.body = min(max(s.body, TypeScale.bodyRange.lowerBound), TypeScale.bodyRange.upperBound)
        if let measure = s.measure { s.measure = min(max(measure, TextRules.measureRange.lowerBound), TextRules.measureRange.upperBound) }
        if let lh = s.lineHeight { s.lineHeight = min(max(lh, TextRules.lineHeightRange.lowerBound), TextRules.lineHeightRange.upperBound) }
        guard let brand else { memoryOnly = s; return }
        map[brand] = s
        writer.mark(brand)
    }

    /// The brand is gone (the database already dropped its row).
    func forget(brand: Int64) { map[brand] = nil }

    func flush() { writer.flush() }
}
