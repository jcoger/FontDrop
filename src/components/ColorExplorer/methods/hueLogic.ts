import type { RampColor, ContrastLevel } from "../types";
import type { OklchColor } from "../../../utils/oklch";
import {
  maxChroma as getMaxChroma,
  relativeToAbsoluteChroma,
  contrastRatio,
  oklchToCss,
  hexToOklch,
  hkLightnessCorrection,
} from "../../../utils/oklch";

// Re-export tone curve utilities (unchanged)
export { sampleToneCurve, L_MIN, L_MAX } from "./hueLock";

// ── FG presets ───────────────────────────────────────────────────────

export type HLFgPreset = "neutral" | "mono" | "complement" | "analog" | "split" | "warm+cool";

export interface HLFgPresetDef {
  id: HLFgPreset;
  label: string;
}

export const HL_FG_PRESETS: HLFgPresetDef[] = [
  { id: "neutral",    label: "NEUTRAL" },
  { id: "mono",       label: "MONO" },
  { id: "complement", label: "COMPLEMENT" },
  { id: "analog",     label: "ANALOG" },
  { id: "split",      label: "SPLIT" },
  { id: "warm+cool",  label: "WARM+COOL" },
];

function fgHueForPreset(preset: HLFgPreset, bgHue: number, cardIndex: number): number {
  switch (preset) {
    case "neutral": return bgHue;
    case "mono": return bgHue;
    case "complement": return (bgHue + 180) % 360;
    case "analog": {
      // Pick +30 or -30, whichever is further from achromatic
      return (bgHue + 30) % 360;
    }
    case "split": return cardIndex % 2 === 0 ? (bgHue + 150) % 360 : (bgHue + 210) % 360;
    case "warm+cool": {
      const isWarm = (bgHue >= 300 || bgHue <= 60);
      const base = isWarm ? 200 : 30;
      const variance = (cardIndex % 5 - 2) * 6; // ±12° spread
      return ((base + variance) % 360 + 360) % 360;
    }
  }
}

function fgRelChromaForPreset(preset: HLFgPreset): number {
  switch (preset) {
    case "neutral": return 0;
    case "mono": return 0.50;
    case "complement": return 0.70;
    case "analog": return 0.65;
    case "split": return 0.65;
    case "warm+cool": return 0.60;
  }
}

/** Compute a preview fg color for a preset chip (at mid bg). */
export function previewFgForPreset(preset: HLFgPreset, bgHue: number): OklchColor {
  const fgH = fgHueForPreset(preset, bgHue, 0);
  const relC = fgRelChromaForPreset(preset);
  const fgL = 0.45;
  const fgC = relativeToAbsoluteChroma(relC, fgL, fgH);
  return { mode: "oklch", l: fgL, c: fgC, h: fgH };
}

// ── Contrast helpers ─────────────────────────────────────────────────

function contrastThreshold(level: ContrastLevel): number {
  switch (level) { case "accessible": return 4.5; case "display": return 3.0; case "clash": return 1.5; }
}

function minLGap(level: ContrastLevel): number {
  switch (level) { case "accessible": return 0.40; case "display": return 0.22; case "clash": return 0.15; }
}

function findPassingFgWithHue(bg: OklchColor, fgH: number, fgC: number, intendedL: number, level: ContrastLevel): OklchColor | null {
  const threshold = contrastThreshold(level);
  const direction = bg.l > 0.55 ? -1 : 1;
  let testL = intendedL;
  for (let step = 0; step < 25; step++) {
    const clamped = Math.max(0, Math.min(1, testL));
    const fg: OklchColor = { mode: "oklch", l: clamped, c: fgC, h: fgH };
    if (contrastRatio(bg, fg) >= threshold) return fg;
    testL += direction * 0.025;
  }
  // Fallback achromatic
  const extremeL = direction > 0 ? 0 : 1;
  return { mode: "oklch", l: extremeL, c: 0, h: 0 };
}

// ── Neutral meta ─────────────────────────────────────────────────────

export function hlGetNeutralMeta(bgColor: OklchColor): string {
  return bgColor.l > 0.55
    ? oklchToCss({ mode: "oklch", l: 0.15, c: 0.02, h: bgColor.h })
    : oklchToCss({ mode: "oklch", l: 0.92, c: 0.02, h: bgColor.h });
}

// ── Hue family ───────────────────────────────────────────────────────

export function hlHueFamily(h: number): string {
  const n = ((h % 360) + 360) % 360;
  if (n < 20 || n >= 345) return "Reds";
  if (n < 50) return "Oranges";
  if (n < 80) return "Yellows";
  if (n < 155) return "Greens";
  if (n < 200) return "Teals";
  if (n < 260) return "Blues";
  if (n < 320) return "Purples";
  return "Pinks";
}

// ── Parse color input ────────────────────────────────────────────────

export function parseColorInput(input: string): OklchColor | null {
  const s = input.trim();
  // Hex
  if (s.startsWith("#")) {
    try { return hexToOklch(s); } catch { return null; }
  }
  // rgb(r, g, b)
  const rgbMatch = s.match(/^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/i);
  if (rgbMatch) {
    const hex = "#" + [rgbMatch[1], rgbMatch[2], rgbMatch[3]]
      .map(v => Math.min(255, +v).toString(16).padStart(2, "0")).join("");
    try { return hexToOklch(hex); } catch { return null; }
  }
  // oklch(l c h) or oklch(l, c, h)
  const oklchMatch = s.match(/^oklch\(\s*([\d.]+)\s*[,\s]\s*([\d.]+)\s*[,\s]\s*([\d.]+)\s*\)/i);
  if (oklchMatch) {
    const l = +oklchMatch[1], c = +oklchMatch[2], h = +oklchMatch[3];
    if (l >= 0 && l <= 1 && c >= 0 && c <= 0.5 && h >= 0 && h <= 360) {
      return { mode: "oklch", l, c, h };
    }
  }
  return null;
}

// ── Extended ramp color ──────────────────────────────────────────────

export interface HLRampColor extends RampColor {
  hlFg?: OklchColor;
  hlMeta?: string;
}

// ── Generation ───────────────────────────────────────────────────────

export interface HLGenParams {
  hue: number;
  steps: number;
  chromaMode: "max" | "fixed";
  fixedChroma: number;
  lValues: number[];
  fgPreset: HLFgPreset;
  fgLOverride: number | null;   // null = auto
  fgCOverride: number | null;   // null = preset default (relative 0–1)
  contrastLevel: ContrastLevel;
  isClash: boolean;
}

export function generateHueMode(params: HLGenParams): HLRampColor[] {
  const {
    hue, steps, chromaMode, fixedChroma, lValues,
    fgPreset, fgLOverride, fgCOverride, contrastLevel, isClash,
  } = params;

  const threshold = contrastThreshold(contrastLevel);
  const ramp: HLRampColor[] = [];

  for (let i = 0; i < steps; i++) {
    const l = lValues[i] ?? 0.54;
    const mc = getMaxChroma(l, hue);
    const c = chromaMode === "max" ? mc : Math.min(fixedChroma, mc);

    // HK correction for vivid bg
    const correctedL = c > 0.15 ? hkLightnessCorrection(l, c, hue) : l;
    const bg: OklchColor = { mode: "oklch", l: correctedL, c, h: hue };

    // ── FG ───────────────────────────────────────────────
    let fgH: number;
    if (isClash) {
      fgH = ((hue + 90 + (i % 6) * 10) % 360 + 360) % 360; // 90–150° spread
    } else {
      fgH = fgHueForPreset(fgPreset, hue, i);
    }

    const presetRelC = fgRelChromaForPreset(fgPreset);
    const relC = fgCOverride !== null ? fgCOverride : presetRelC;

    // FG lightness: level-aware gap
    let fgL_target: number;
    if (fgLOverride !== null) {
      fgL_target = fgLOverride;
    } else {
      const gap = minLGap(contrastLevel);
      if (isClash) {
        // Clash: close lightness, hue tension — small gap with slight randomness
        const clashGap = gap + (i % 5) * 0.015; // 0.15–0.21
        fgL_target = correctedL > 0.55
          ? Math.max(0.05, correctedL - clashGap)
          : Math.min(0.95, correctedL + clashGap);
      } else {
        // Display / Accessible: push away by the level's minimum gap
        fgL_target = correctedL > 0.55
          ? Math.max(0.05, correctedL - Math.max(gap, 0.30))
          : Math.min(0.95, correctedL + Math.max(gap, 0.30));
      }
    }

    const fgC = relativeToAbsoluteChroma(relC, fgL_target, fgH);
    let fg: OklchColor | null = { mode: "oklch", l: fgL_target, c: fgC, h: fgH };

    // Contrast enforcement (skip if user has manual L override)
    if (fgLOverride === null && contrastRatio(bg, fg) < threshold) {
      fg = findPassingFgWithHue(bg, fgH, fgC, fgL_target, contrastLevel);
    }
    if (!fg) fg = { mode: "oklch", l: correctedL > 0.55 ? 0.05 : 0.95, c: 0, h: 0 };

    const badge = `${Math.round(contrastRatio(bg, fg) * 10) / 10}`;
    const meta = hlGetNeutralMeta(bg);

    ramp.push({ color: bg, badge, hlFg: fg, hlMeta: meta });
  }

  return ramp;
}

// ── Flip ─────────────────────────────────────────────────────────────

export function hlFlipCard(
  bg: OklchColor,
  fg: OklchColor,
  level: ContrastLevel,
): { bg: OklchColor; fg: OklchColor } {
  const newBg = fg;
  const newFg = findPassingFgWithHue(newBg, bg.h, bg.c, bg.l, level);
  return { bg: newBg, fg: newFg || bg };
}

// ── Contrast range for bottom bar ────────────────────────────────────

export function hlContrastRange(ramp: HLRampColor[]): [number, number] {
  let min = Infinity, max = 0;
  for (const rc of ramp) {
    if (rc.hlFg) {
      const r = contrastRatio(rc.color, rc.hlFg);
      if (r < min) min = r;
      if (r > max) max = r;
    }
  }
  return [min === Infinity ? 0 : min, max];
}
