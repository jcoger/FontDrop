import {
  maxChroma as getMaxChroma,
  halton,
  hueDifference,
  oklchToCss,
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

// Y (0→1): muted → vivid. Interpolate chroma range boundaries.
const CMIN_LO = 0.02, CMIN_HI = 0.18;
const CMAX_LO = 0.08, CMAX_HI = 0.37;

export function yToChroma(y: number): [number, number] {
  return [
    CMIN_LO + y * (CMIN_HI - CMIN_LO),
    CMAX_LO + y * (CMAX_HI - CMAX_LO),
  ];
}

export function chromaToY(cMin: number): number {
  return Math.max(0, Math.min(1, (cMin - CMIN_LO) / (CMIN_HI - CMIN_LO)));
}

// ── Human-readable labels ─────────────────────────────────────────────

export function readoutLabel(hCenter: number, cMin: number): string {
  const hx = hueToX(hCenter);
  const temp = hx > 0.7 ? "WARM" : hx < 0.3 ? "COOL" : "NEUTRAL";
  const y = (cMin - CMIN_LO) / (CMIN_HI - CMIN_LO);
  const sat = y > 0.67 ? "VIVID" : y < 0.33 ? "MUTED" : "MODERATE";
  return `${sat} ${temp}`;
}

export function badgeTemp(hCenter: number): string {
  const hx = hueToX(hCenter);
  return hx > 0.7 ? "WARM" : hx < 0.3 ? "COOL" : "NEUTRAL";
}

// ── XY Pad background painter ─────────────────────────────────────────

export function paintPadBg(canvas: HTMLCanvasElement): void {
  const SIZE = 64;
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext("2d")!;
  const img = ctx.createImageData(SIZE, SIZE);

  for (let py = 0; py < SIZE; py++) {
    for (let px = 0; px < SIZE; px++) {
      const x = px / (SIZE - 1);
      const y = 1 - py / (SIZE - 1);
      const h = xToHue(x);
      const cBand = y * 0.35 + 0.02;
      const l = 0.55;
      const color: OklchColor = { mode: "oklch", l, c: Math.min(cBand, getMaxChroma(l, h)), h };
      const css = oklchToCss(color);
      const m = css.match(/(\d+)/g);
      const off = (py * SIZE + px) * 4;
      if (m) { img.data[off] = +m[0]; img.data[off + 1] = +m[1]; img.data[off + 2] = +m[2]; }
      img.data[off + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
}

// ── Generation ────────────────────────────────────────────────────────

export function generateTemperatureCorridor(params: TempCorridorParams): RampColor[] {
  const { hCenter, tempWidth, chromaMin, chromaMax, lRange, count } = params;
  const hMin = hCenter - tempWidth / 2;
  const tempLabel = badgeTemp(hCenter);
  const ramp: RampColor[] = [];

  for (let i = 0; i < count; i++) {
    const h = ((hMin + halton(i, 2) * tempWidth) % 360 + 360) % 360;
    const l = lRange[0] + halton(i, 3) * (lRange[1] - lRange[0]);
    const rawC = chromaMin + halton(i, 5) * (chromaMax - chromaMin);
    const mc = getMaxChroma(l, h);
    const c = Math.min(rawC, mc);
    const hueDist = hueDifference(h, hCenter);
    const halfWidth = tempWidth / 2;
    const intensity = halfWidth > 0 ? Math.round((1 - hueDist / halfWidth) * 3) : 3;
    ramp.push({ color: { mode: "oklch", l, c, h }, badge: `${tempLabel} +${intensity}` });
  }

  ramp.sort((a, b) => hueDifference(a.color.h, hCenter) - hueDifference(b.color.h, hCenter));
  return ramp;
}
