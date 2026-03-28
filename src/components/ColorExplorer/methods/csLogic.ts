import {
  maxChroma as getMaxChroma,
  contrastRatio,
  contrastLevel,
  oklchToCss,
  oklchToHex,
} from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type { ContrastSafeParams, ContrastRampColor, Threshold } from "../types";

export type { ContrastRampColor };

// ── Generation ────────────────────────────────────────────────────────

export function generateContrastSafe(params: ContrastSafeParams): ContrastRampColor[] {
  const { primary, lRange, cRange, hueMode, threshold, density } = params;
  const thresholdRatio = threshold === "AAA" ? 7 : 4.5;

  let hueSlices: number[];
  if (hueMode === "full") {
    hueSlices = Array.from({ length: 12 }, (_, i) => (i * 30) % 360);
  } else {
    const center = primary.h;
    hueSlices = Array.from({ length: 6 }, (_, i) => ((center - 60 + i * 20) % 360 + 360) % 360);
  }

  const lSteps = Math.max(2, Math.round(Math.sqrt(density)));
  const cSteps = Math.max(2, Math.round(density / lSteps));
  const results: ContrastRampColor[] = [];

  for (const h of hueSlices) {
    for (let li = 0; li < lSteps; li++) {
      const l = lSteps === 1 ? (lRange[0] + lRange[1]) / 2 : lRange[0] + (lRange[1] - lRange[0]) * (li / (lSteps - 1));
      for (let ci = 0; ci < cSteps; ci++) {
        const rawC = cSteps === 1 ? (cRange[0] + cRange[1]) / 2 : cRange[0] + (cRange[1] - cRange[0]) * (ci / (cSteps - 1));
        const mc = getMaxChroma(l, h);
        const c = Math.min(rawC, mc);
        const testColor: OklchColor = { mode: "oklch", l, c, h };
        const ratio = contrastRatio(testColor, primary);
        const level = contrastLevel(ratio);
        const passes = ratio >= thresholdRatio;
        const levelColors: Record<string, string> = { AAA: "var(--c-success)", AA: "var(--c-warning)", "AA-large": "var(--c-caution)", FAIL: "var(--c-error)" };
        results.push({ color: testColor, badge: `${level} ${ratio.toFixed(1)}:1`, passes, ratio, badgeColor: levelColors[level] } as ContrastRampColor & { badgeColor: string });
      }
    }
  }

  results.sort((a, b) => { if (a.passes !== b.passes) return a.passes ? -1 : 1; return b.ratio - a.ratio; });
  return results.slice(0, 24);
}

// ── Scatter plot data ←────────────────────────────────────────────────

export interface ScatterDot {
  h: number;
  l: number;
  css: string;
  hex: string;
  passes: boolean;
  ratio: number;
  badge: string;
}

export function buildDots(results: ContrastRampColor[]): ScatterDot[] {
  return results.map((r) => ({
    h: r.color.h,
    l: r.color.l,
    css: oklchToCss(r.color),
    hex: oklchToHex(r.color),
    passes: r.passes,
    ratio: r.ratio,
    badge: r.badge,
  }));
}

// ── Canvas painters ───────────────────────────────────────────────────

export const PLOT_W = 190;
export const PLOT_H = 140;

export function paintForbiddenZone(
  ctx: CanvasRenderingContext2D,
  primary: OklchColor,
  threshold: Threshold,
  hMin: number,
  hMax: number,
  w: number,
  h: number,
): void {
  const ratio = threshold === "AAA" ? 7 : 4.5;
  const step = 4;
  ctx.fillStyle = "rgba(239,68,68,0.08)";
  for (let px = 0; px < w; px += step) {
    for (let py = 0; py < h; py += step) {
      const hue = hMin + (px / w) * (hMax - hMin);
      const l = 1 - py / h;
      const test: OklchColor = { mode: "oklch", l, c: 0.15, h: ((hue % 360) + 360) % 360 };
      if (contrastRatio(test, primary) < ratio) {
        ctx.fillRect(px, py, step, step);
      }
    }
  }
}

export function paintScatter(
  canvas: HTMLCanvasElement,
  dots: ScatterDot[],
  primary: OklchColor,
  threshold: Threshold,
  hMin: number,
  hMax: number,
  selRect: { x0: number; y0: number; x1: number; y1: number } | null,
): void {
  const dpr = 2;
  canvas.width = PLOT_W * dpr;
  canvas.height = PLOT_H * dpr;
  const ctx = canvas.getContext("2d")!;
  ctx.scale(dpr, dpr);

  ctx.fillStyle = "#1a1a1a";
  ctx.fillRect(0, 0, PLOT_W, PLOT_H);

  ctx.strokeStyle = "rgba(255,255,255,0.06)";
  ctx.lineWidth = 1;
  for (const gl of [0.25, 0.5, 0.75]) {
    const y = (1 - gl) * PLOT_H;
    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(PLOT_W, y); ctx.stroke();
  }

  paintForbiddenZone(ctx, primary, threshold, hMin, hMax, PLOT_W, PLOT_H);

  if (selRect) {
    ctx.fillStyle = "rgba(217,119,54,0.08)";
    ctx.strokeStyle = "rgba(217,119,54,0.4)";
    ctx.lineWidth = 1;
    const rx = Math.min(selRect.x0, selRect.x1) * PLOT_W;
    const ry = (1 - Math.max(selRect.y0, selRect.y1)) * PLOT_H;
    const rw = Math.abs(selRect.x1 - selRect.x0) * PLOT_W;
    const rh = Math.abs(selRect.y1 - selRect.y0) * PLOT_H;
    ctx.fillRect(rx, ry, rw, rh);
    ctx.strokeRect(rx, ry, rw, rh);
  }

  const hRange = hMax - hMin;
  for (const dot of dots) {
    let normH = ((dot.h - hMin) % 360 + 360) % 360;
    if (normH > hRange) continue;
    const x = (normH / hRange) * PLOT_W;
    const y = (1 - dot.l) * PLOT_H;
    ctx.globalAlpha = dot.passes ? 1 : 0.25;
    ctx.fillStyle = dot.css;
    ctx.beginPath(); ctx.arc(x, y, 3, 0, Math.PI * 2); ctx.fill();
  }

  ctx.globalAlpha = 1;
  const normPH = ((primary.h - hMin) % 360 + 360) % 360;
  if (normPH <= hRange) {
    const px = (normPH / hRange) * PLOT_W;
    const py = (1 - primary.l) * PLOT_H;
    ctx.strokeStyle = "#ffffff";
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(px, py, 6, 0, Math.PI * 2); ctx.stroke();
    ctx.fillStyle = oklchToCss(primary);
    ctx.beginPath(); ctx.arc(px, py, 5, 0, Math.PI * 2); ctx.fill();
  }
}
