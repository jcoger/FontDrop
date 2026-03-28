import { converter as culoriConverter } from "culori";
import {
  maxChroma as getMaxChroma,
  relativeToAbsoluteChroma,
  peakChromaL,
  halton,
  hueDifference,
  safeColor,
  hkLightnessCorrection,
} from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type { RampColor, TempCorridorParams } from "../types";

// ── Axis mapping ──────────────────────────────────────────────────────
// X (0→1): cool 230 → neutral 130 → warm 30   ⟹  hue = 230 − x·200

export function xToHue(x: number): number {
  return ((230 - x * 200) % 360 + 360) % 360;
}

export function hueToX(h: number): number {
  let d = 230 - h;
  if (d < -80) d += 360;
  if (d > 280) d -= 360;
  return Math.max(0, Math.min(1, d / 200));
}

// Y (0→1): chroma ceiling as relative fraction of gamut.
// 0 = 0% of max chroma (achromatic), 1 = 100% of max chroma (full gamut)
export function yToChromaCeiling(y: number): number {
  return Math.max(0, Math.min(1, y));
}

export function chromaCeilingToY(ceiling: number): number {
  return Math.max(0, Math.min(1, ceiling));
}

// ── Human-readable labels ─────────────────────────────────────────────

export function readoutLabel(hCenter: number, chromaCeiling: number): string {
  const hx = hueToX(hCenter);
  const temp = hx > 0.7 ? "WARM" : hx < 0.3 ? "COOL" : "NEUTRAL";
  const sat = chromaCeiling > 0.67 ? "VIVID" : chromaCeiling < 0.33 ? "MUTED" : "MODERATE";
  return `${sat} ${temp}`;
}

export function badgeTemp(hCenter: number): string {
  const hx = hueToX(hCenter);
  return hx > 0.7 ? "WARM" : hx < 0.3 ? "COOL" : "NEUTRAL";
}

// ── XY Pad background painter ─────────────────────────────────────────

/** Paint pad background: X=hue, Y=relative chroma (gamut-aware).
 *  Each pixel shows the color at that hue with chroma as a fraction of the max
 *  chroma at L=0.55 for that hue. Cool blues get just as vivid as warm oranges. */
export function paintPadBg(canvas: HTMLCanvasElement): void {
  const SIZE = 64;
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext("2d")!;
  const img = ctx.createImageData(SIZE, SIZE);

  // Canvas ImageData is always sRGB — convert directly, don't parse CSS strings
  const toSrgb = culoriConverter("rgb");

  for (let py = 0; py < SIZE; py++) {
    for (let px = 0; px < SIZE; px++) {
      const x = px / (SIZE - 1);
      const y = 1 - py / (SIZE - 1); // y=0 bottom, y=1 top
      const h = xToHue(x);
      const l = 0.55;
      const mc = getMaxChroma(l, h);
      const c = y * mc; // relative chroma: y fraction of gamut
      const color: OklchColor = { mode: "oklch", l, c: Math.min(c, mc), h };
      const safe = safeColor(color);
      const rgb = toSrgb(safe);
      const off = (py * SIZE + px) * 4;
      if (rgb) {
        img.data[off] = Math.round(Math.min(1, Math.max(0, rgb.r)) * 255);
        img.data[off + 1] = Math.round(Math.min(1, Math.max(0, rgb.g)) * 255);
        img.data[off + 2] = Math.round(Math.min(1, Math.max(0, rgb.b)) * 255);
      }
      img.data[off + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
}

// ── Generation ────────────────────────────────────────────────────────

export interface DualCorridorParams {
  node1: TempCorridorParams;
  node2: TempCorridorParams;
  accentWeight: number; // 0.1–0.9, fraction for node2
}

/** Generate two corridors and interleave them (every 3rd card from node2). */
export function generateDualCorridor(params: DualCorridorParams): RampColor[] {
  const { node1, node2, accentWeight } = params;
  const total = node1.count; // total card count comes from node1.count
  const n2Count = Math.max(1, Math.round(total * accentWeight));
  const n1Count = Math.max(1, total - n2Count);

  const ramp1 = generateTemperatureCorridor({ ...node1, count: n1Count });
  const ramp2 = generateTemperatureCorridor({ ...node2, count: n2Count }).map((rc) => ({
    ...rc,
    badge: `ACCENT ${rc.badge}`,
  }));

  // Interleave: every 3rd card from corridor 2
  const merged: RampColor[] = [];
  let i1 = 0, i2 = 0;
  for (let i = 0; i < n1Count + n2Count; i++) {
    if ((i + 1) % 3 === 0 && i2 < ramp2.length) {
      merged.push(ramp2[i2++]);
    } else if (i1 < ramp1.length) {
      merged.push(ramp1[i1++]);
    } else if (i2 < ramp2.length) {
      merged.push(ramp2[i2++]);
    }
  }
  // Flush remaining
  while (i1 < ramp1.length) merged.push(ramp1[i1++]);
  while (i2 < ramp2.length) merged.push(ramp2[i2++]);

  return merged;
}

export function generateTemperatureCorridor(params: TempCorridorParams): RampColor[] {
  const { hCenter, tempWidth, chromaMin, chromaMax, lRange, count, useRelativeChroma, lMidBias } = params;
  const hMin = hCenter - tempWidth / 2;
  const tempLabel = badgeTemp(hCenter);
  const ramp: RampColor[] = [];
  const bias = lMidBias ?? 0.5;

  // Peak-L bias: when chroma ceiling is high and using relative chroma,
  // pull L toward the lightness where this hue's gamut is widest.
  const usePeakBias = useRelativeChroma && chromaMax >= 0.50;
  const peakBlendScale = usePeakBias
    ? Math.min(1, (chromaMax - 0.50) / 0.50) // 0 at 0.50, 1 at 1.0
    : 0;

  for (let i = 0; i < count; i++) {
    const h = ((hMin + halton(i, 2) * tempWidth) % 360 + 360) % 360;

    // Lightness with midpoint bias (quadratic bezier through bias point)
    const t = halton(i, 3);
    const uniformL = (1 - t) * (1 - t) * lRange[0] + 2 * (1 - t) * t * (lRange[0] + (lRange[1] - lRange[0]) * bias) + t * t * lRange[1];

    // When chroma ceiling is high, bias L toward peak-chroma lightness for this hue
    let l: number;
    if (peakBlendScale > 0) {
      const peak = peakChromaL(h);
      const clampedPeak = Math.max(lRange[0], Math.min(lRange[1], peak));
      l = uniformL + peakBlendScale * (clampedPeak - uniformL);
    } else {
      l = uniformL;
    }

    // Chroma: relative (gamut-aware) or absolute
    const rawRel = chromaMin + halton(i, 5) * (chromaMax - chromaMin);
    const mc = getMaxChroma(l, h);
    const c = useRelativeChroma ? relativeToAbsoluteChroma(rawRel, l, h) : Math.min(rawRel, mc);

    // HK perceptual brightness correction — only for vivid modes (chromaMax >= 0.50)
    const finalL = chromaMax >= 0.50 ? hkLightnessCorrection(l, c, h) : l;

    const hueDist = hueDifference(h, hCenter);
    const halfWidth = tempWidth / 2;
    const intensity = halfWidth > 0 ? Math.round((1 - hueDist / halfWidth) * 3) : 3;
    ramp.push({ color: { mode: "oklch", l: finalL, c, h }, badge: `${tempLabel} +${intensity}` });
  }

  ramp.sort((a, b) => hueDifference(a.color.h, hCenter) - hueDifference(b.color.h, hCenter));
  return ramp;
}
