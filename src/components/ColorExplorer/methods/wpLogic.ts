import type { RampColor, TempCorridorParams, ContrastLevel } from "../types";
import type { OklchColor } from "../../../utils/oklch";
import { contrastRatio, relativeToAbsoluteChroma, halton, hkLightnessCorrection, oklchToCss } from "../../../utils/oklch";
import { generateTemperatureCorridor, generateDualCorridor } from "./tcLogic";

// ── Word Picker preset type ──────────────────────────────────────────

export interface WPPreset {
  hCenter: number;
  hueWidth: number;
  chromaFloor: number;
  chromaCeiling: number;
  lMin: number;
  lMax: number;
  lBias: number;        // -1 to +1
  accentOffset: number;
}

export type WPTagName =
  // Hue-opinionated
  | "WARM" | "COOL" | "GOLDEN" | "EARTHY" | "ICY" | "ELECTRIC" | "BOTANICAL" | "DUSK"
  // Energy-opinionated
  | "VIVID" | "MUTED" | "DEEP" | "NEON" | "EDITORIAL" | "PASTEL" | "BOLD" | "RETRO";

export const WP_TAGS: WPTagName[] = [
  // Row 1: hue-opinionated
  "WARM", "COOL", "GOLDEN", "EARTHY",
  "ICY", "ELECTRIC", "BOTANICAL", "DUSK",
  // Row 2: energy-opinionated
  "VIVID", "MUTED", "DEEP", "NEON",
  "EDITORIAL", "PASTEL", "BOLD", "RETRO",
];

// ── Presets ──────────────────────────────────────────────────────────
// Hue-opinionated tags: specific hue territory + energy character
// Energy-opinionated tags: neutral hCenter (180°), wide hueWidth, energy-defined

export const WP_PRESETS: Record<WPTagName, WPPreset> = {
  // ── Hue-opinionated ────────────────────────────────────────────
  WARM:      { hCenter: 30,  hueWidth: 50,  chromaFloor: 0.30, chromaCeiling: 0.65, lMin: 0.35, lMax: 0.72, lBias: 0.0,  accentOffset: 180 },
  COOL:      { hCenter: 220, hueWidth: 50,  chromaFloor: 0.20, chromaCeiling: 0.55, lMin: 0.32, lMax: 0.75, lBias: 0.0,  accentOffset: 180 },
  GOLDEN:    { hCenter: 70,  hueWidth: 35,  chromaFloor: 0.45, chromaCeiling: 0.75, lMin: 0.52, lMax: 0.80, lBias: 0.15, accentOffset: 200 },
  EARTHY:    { hCenter: 90,  hueWidth: 45,  chromaFloor: 0.12, chromaCeiling: 0.38, lMin: 0.22, lMax: 0.55, lBias: -0.2, accentOffset: 160 },
  ICY:       { hCenter: 210, hueWidth: 40,  chromaFloor: 0.05, chromaCeiling: 0.20, lMin: 0.75, lMax: 0.93, lBias: 0.3,  accentOffset: 60 },
  ELECTRIC:  { hCenter: 285, hueWidth: 35,  chromaFloor: 0.70, chromaCeiling: 1.00, lMin: 0.40, lMax: 0.65, lBias: 0.0,  accentOffset: 150 },
  BOTANICAL: { hCenter: 145, hueWidth: 40,  chromaFloor: 0.25, chromaCeiling: 0.55, lMin: 0.28, lMax: 0.60, lBias: -0.1, accentOffset: 300 },
  DUSK:      { hCenter: 320, hueWidth: 45,  chromaFloor: 0.20, chromaCeiling: 0.50, lMin: 0.18, lMax: 0.48, lBias: -0.2, accentOffset: 90 },

  // ── Energy-opinionated ─────────────────────────────────────────
  VIVID:     { hCenter: 180, hueWidth: 90,  chromaFloor: 0.65, chromaCeiling: 1.00, lMin: 0.42, lMax: 0.68, lBias: 0.0,  accentOffset: 180 },
  MUTED:     { hCenter: 180, hueWidth: 100, chromaFloor: 0.02, chromaCeiling: 0.22, lMin: 0.30, lMax: 0.78, lBias: 0.1,  accentOffset: 90 },
  DEEP:      { hCenter: 180, hueWidth: 80,  chromaFloor: 0.50, chromaCeiling: 0.88, lMin: 0.10, lMax: 0.40, lBias: -0.3, accentOffset: 180 },
  NEON:      { hCenter: 180, hueWidth: 80,  chromaFloor: 0.88, chromaCeiling: 1.00, lMin: 0.52, lMax: 0.72, lBias: 0.05, accentOffset: 150 },
  EDITORIAL: { hCenter: 180, hueWidth: 360, chromaFloor: 0.00, chromaCeiling: 0.12, lMin: 0.12, lMax: 0.92, lBias: 0.0,  accentOffset: 0 },
  PASTEL:    { hCenter: 180, hueWidth: 100, chromaFloor: 0.08, chromaCeiling: 0.28, lMin: 0.72, lMax: 0.92, lBias: 0.35, accentOffset: 90 },
  BOLD:      { hCenter: 180, hueWidth: 80,  chromaFloor: 0.55, chromaCeiling: 0.92, lMin: 0.18, lMax: 0.78, lBias: 0.0,  accentOffset: 180 },
  RETRO:     { hCenter: 35,  hueWidth: 65,  chromaFloor: 0.18, chromaCeiling: 0.42, lMin: 0.38, lMax: 0.68, lBias: 0.0,  accentOffset: 60 },
};

// ── Blend / interpolate ──────────────────────────────────────────────

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function lerpHue(a: number, b: number, t: number): number {
  let d = b - a;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return ((a + d * t) % 360 + 360) % 360;
}

function blendPresets(a: WPPreset, b: WPPreset, t: number): WPPreset {
  return {
    hCenter: lerpHue(a.hCenter, b.hCenter, t),
    hueWidth: lerp(a.hueWidth, b.hueWidth, t),
    chromaFloor: lerp(a.chromaFloor, b.chromaFloor, t),
    chromaCeiling: lerp(a.chromaCeiling, b.chromaCeiling, t),
    lMin: lerp(a.lMin, b.lMin, t),
    lMax: lerp(a.lMax, b.lMax, t),
    lBias: lerp(a.lBias, b.lBias, t),
    accentOffset: lerp(a.accentOffset, b.accentOffset, t),
  };
}

// ── Resolve preset with intensity (single-tag) or blend (two-tag) ────

export function resolvePreset(
  tags: [WPTagName] | [WPTagName, WPTagName] | [],
  drift: number, // 0–100
): WPPreset {
  if (tags.length === 0) {
    // No tags: return a gentle neutral
    return { hCenter: 180, hueWidth: 120, chromaFloor: 0.15, chromaCeiling: 0.45, lMin: 0.30, lMax: 0.75, lBias: 0.0, accentOffset: 180 };
  }

  // Two tags: blend between them (unchanged)
  if (tags.length === 2) {
    return blendPresets(WP_PRESETS[tags[0]], WP_PRESETS[tags[1]], drift / 100);
  }

  // Single tag: INTENSITY mode (0 = softer, 50 = exact, 100 = amplified)
  const preset = WP_PRESETS[tags[0]];
  const t = drift / 100;

  // Create a softer version: chroma pulled toward floor, lightness toward mid
  const soft: WPPreset = {
    ...preset,
    chromaFloor: preset.chromaFloor * 0.3,
    chromaCeiling: lerp(preset.chromaFloor, preset.chromaCeiling, 0.4),
    lMin: lerp(preset.lMin, 0.45, 0.4),
    lMax: lerp(preset.lMax, 0.70, 0.4),
    lBias: preset.lBias * 0.3,
  };

  // Create an amplified version: chroma pushed toward ceiling, bias more pronounced
  const amp: WPPreset = {
    ...preset,
    chromaFloor: lerp(preset.chromaFloor, preset.chromaCeiling, 0.5),
    chromaCeiling: Math.min(1, preset.chromaCeiling * 1.1),
    lBias: preset.lBias * 1.5,
  };

  if (t <= 0.5) {
    return blendPresets(soft, preset, t * 2); // 0→soft, 0.5→preset
  }
  return blendPresets(preset, amp, (t - 0.5) * 2); // 0.5→preset, 1.0→amplified
}

// ── Contrast helpers (shared with Macro Knob philosophy) ─────────────

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
  // Fallback: achromatic
  const extremeL = direction > 0 ? 0 : 1;
  return { mode: "oklch", l: extremeL, c: 0, h: 0 };
}

// ── Neutral meta color for secondary card text ───────────────────────

export function wpGetNeutralMeta(bgColor: OklchColor): string {
  return bgColor.l > 0.55
    ? oklchToCss({ mode: "oklch", l: 0.15, c: 0.02, h: bgColor.h })
    : oklchToCss({ mode: "oklch", l: 0.92, c: 0.02, h: bgColor.h });
}

// ── Extended ramp color with fg and meta ─────────────────────────────

export interface WPRampColor extends RampColor {
  wpFg?: OklchColor;
  wpMeta?: string;
}

// ── Generation ───────────────────────────────────────────────────────

export function generateWordPicker(
  tags: [WPTagName] | [WPTagName, WPTagName] | [],
  drift: number,
  count: number,
  useAccent: boolean,
  level: ContrastLevel,
): WPRampColor[] {
  const p = resolvePreset(tags, drift);
  const lMidBias = (p.lBias + 1) / 2;
  const isClash = level === "clash";

  const tcParams: TempCorridorParams = {
    hCenter: p.hCenter,
    tempWidth: p.hueWidth,
    chromaMin: p.chromaFloor,
    chromaMax: p.chromaCeiling,
    lRange: [p.lMin, p.lMax],
    count: level === "accessible" ? count * 2 : count,
    useRelativeChroma: true,
    lMidBias,
  };

  // Generate BG colors via TC engine
  let bgRamp: RampColor[];
  if (useAccent && p.accentOffset !== 0) {
    const accentH = ((p.hCenter + p.accentOffset) % 360 + 360) % 360;
    bgRamp = generateDualCorridor({
      node1: tcParams,
      node2: { ...tcParams, hCenter: accentH },
      accentWeight: 0.30,
    });
  } else {
    bgRamp = generateTemperatureCorridor(tcParams);
  }

  // Generate independent FG per card
  const result: WPRampColor[] = [];
  for (let i = 0; i < bgRamp.length && result.length < count; i++) {
    const bg = bgRamp[i].color;

    // FG hue: accent offset when enabled, otherwise same hue family
    let fgH: number;
    if (isClash) {
      const clashOffset = 90 + halton(i, 13) * 60;
      fgH = ((bg.h + clashOffset) % 360 + 360) % 360;
    } else if (useAccent && p.accentOffset !== 0) {
      fgH = ((bg.h + p.accentOffset) % 360 + 360) % 360;
    } else {
      fgH = bg.h + (halton(i, 7) - 0.5) * 10; // mono: same hue ±5°
    }

    // FG lightness: push away from bg
    const gap = isClash
      ? (0.15 + halton(i, 17) * 0.07)
      : Math.max(minLGap(level), 0.30);
    const fgL = bg.l > 0.55
      ? Math.max(0.05, bg.l - gap)
      : Math.min(0.95, bg.l + gap);

    // FG chroma: from the preset's range
    const fgRelC = p.chromaFloor + halton(i, 11) * (p.chromaCeiling - p.chromaFloor);
    const fgC = relativeToAbsoluteChroma(fgRelC, fgL, fgH);

    // HK correction
    const correctedFgL = p.chromaCeiling >= 0.50 ? hkLightnessCorrection(fgL, fgC, fgH) : fgL;
    let fg: OklchColor | null = { mode: "oklch", l: correctedFgL, c: fgC, h: fgH };

    // Contrast enforcement
    if (contrastRatio(bg, fg) < contrastThreshold(level)) {
      fg = findPassingFgWithHue(bg, fgH, fgC, correctedFgL, level);
      if (!fg) continue;
    }

    // Badge: tag name(s)
    const badge = tags.length === 2
      ? `${tags[0]} · ${tags[1]}`
      : tags.length === 1
        ? tags[0]
        : "—";

    const meta = wpGetNeutralMeta(bg);
    result.push({ ...bgRamp[i], badge, wpFg: fg, wpMeta: meta });
  }

  return result.slice(0, count);
}

// ── Plain-english readout ────────────────────────────────────────────

function hueFamilyName(h: number): string {
  const n = ((h % 360) + 360) % 360;
  if (n < 15 || n >= 345) return "reds";
  if (n < 45) return "oranges";
  if (n < 75) return "yellows";
  if (n < 150) return "greens";
  if (n < 195) return "teals";
  if (n < 255) return "blues";
  if (n < 315) return "purples";
  return "pinks";
}

function intensityWord(ceiling: number): string {
  if (ceiling > 0.8) return "vivid";
  if (ceiling > 0.5) return "rich";
  if (ceiling > 0.25) return "moderate";
  return "muted";
}

function lightnessWord(lMin: number, lMax: number, lBias: number): string {
  const mid = (lMin + lMax) / 2 + lBias * 0.15;
  if (mid > 0.7) return "light";
  if (mid < 0.4) return "deep";
  return "";
}

export function wpReadout(
  tags: [WPTagName] | [WPTagName, WPTagName] | [],
  drift: number,
): string {
  if (tags.length === 0) return "Select a mood to begin";

  if (tags.length === 2) {
    const t = drift / 100;
    if (t < 0.3) return `Mostly ${tags[0].toLowerCase()} with a hint of ${tags[1].toLowerCase()}`;
    if (t > 0.7) return `Mostly ${tags[1].toLowerCase()} with a hint of ${tags[0].toLowerCase()}`;
    return `Blending ${tags[0].toLowerCase()} + ${tags[1].toLowerCase()}`;
  }

  const p = resolvePreset(tags, drift);
  const intensity = intensityWord(p.chromaCeiling);
  const lightness = lightnessWord(p.lMin, p.lMax, p.lBias);
  const family = hueFamilyName(p.hCenter);
  const parts = [intensity, lightness, family].filter(Boolean);
  return parts.join(" ");
}
