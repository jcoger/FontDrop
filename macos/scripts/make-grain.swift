#!/usr/bin/env swift
// Writes Sources/FontDrop/Resources/grain.png: a 160 px tile of fractal noise, white with a noise alpha.
// Three octaves, base frequency about 0.9 per pixel (the Paper board's feTurbulence setting). The tile
// wraps on all edges. The view draws it at the token's opacity (7%), so the PNG itself is full strength.
// Run once: swift scripts/make-grain.swift
import AppKit

let n = 160
var state: UInt64 = 0x9E3779B97F4A7C15
func rnd() -> Double {
    state ^= state << 13; state ^= state >> 7; state ^= state << 17
    return Double(state % 100_000) / 100_000
}
// One octave: a wrapped lattice of random values, smoothly interpolated. cell = pixels per lattice step.
func octave(cell: Int) -> [Double] {
    let g = max(n / cell, 1)
    let lattice = (0..<(g * g)).map { _ in rnd() }
    var out = [Double](repeating: 0, count: n * n)
    for y in 0..<n { for x in 0..<n {
        let fx = Double(x) / Double(cell), fy = Double(y) / Double(cell)
        let x0 = Int(fx) % g, y0 = Int(fy) % g, x1 = (x0 + 1) % g, y1 = (y0 + 1) % g
        let tx = fx - floor(fx), ty = fy - floor(fy)
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let a = lattice[y0 * g + x0], b = lattice[y0 * g + x1], c = lattice[y1 * g + x0], d = lattice[y1 * g + x1]
        out[y * n + x] = (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
    } }
    return out
}
let o1 = (0..<(n * n)).map { _ in rnd() }     // 0.9 cycles per pixel is pixel-scale: white noise
let o2 = octave(cell: 2), o3 = octave(cell: 4)
var rgba = [UInt8](repeating: 255, count: n * n * 4)
for i in 0..<(n * n) {
    let v = (o1[i] + 0.5 * o2[i] + 0.25 * o3[i]) / 1.75
    rgba[i * 4 + 3] = UInt8(max(0, min(255, v * 255)))   // white, alpha = noise
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: n * 4, bitsPerPixel: 32)!
rgba.withUnsafeBufferPointer { rep.bitmapData!.update(from: $0.baseAddress!, count: n * n * 4) }
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sources/FontDrop/Resources/grain.png")
try! rep.representation(using: .png, properties: [:])!.write(to: url)
print("wrote \(url.path)")
