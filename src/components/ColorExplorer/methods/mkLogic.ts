import type { RampColor, ContrastLevel } from "../types";
import type { OklchColor } from "../../../utils/oklch";
import { contrastRatio, relativeToAbsoluteChroma, peakChromaL, halton, hkLightnessCorrection, oklchToCss } from "../../../utils/oklch";

// ── Continuous energy spectrum ────────────────────────────────────────
// The dial (0–360°, wrapping) maps to smooth parameter curves.
// Energy increases monotonically: 0° = whisper, 360° = scream.
// A natural "deep" dip in lightness occurs around the midpoint (~180°).

/** Normalized energy: 0→1 as knob goes 0→360. */
function energy(knob: number): number {
  return ((knob % 360) + 360) % 360 / 360;
}

/** Smooth cosine bump centered at `center` (0–1) with `width` (0–1). */
function bump(t: number, center: number, width: number): number {
  const d = Math.abs(t - center);
  if (d > width) return 0;
  return (1 + Math.cos((d / width) * Math.PI)) / 2;
}

interface EnergyParams {
  bgChromaFloor: number;
  bgChromaCeiling: number;
  bgLMin: number;
  bgLMax: number;
  bgLBias: number;
  fgChromaFloor: number;
  fgChromaCeiling: number;
  fgLBias: number;
  fgMinPush: number;
  fgBias: number;      // -1..+1: continuous direction bias for fg L search
  hueWidth: number;     // degrees: how much cards spread around center hue
  glowL: number;
  glowC: number;
}

/** Resolve dial position to continuous energy parameters. */
export function resolveEnergy(knob: number): EnergyParams {
  const e = energy(knob);

  // ── Chroma: monotonically increasing, steep ramp at high energy ───
  // Use a power curve so the top 30% of the dial really pushes hard
  const ePow = e * e; // accelerating curve — slow at bottom, fast at top
  const bgChromaFloor = 0.02 + ePow * 0.98;    // 0.02 → 1.00
  const bgChromaCeiling = Math.min(1, 0.12 + e * 0.50 + ePow * 0.50); // 0.12 → 1.00 (accelerating)

  // FG chroma tracks bg
  const fgChromaFloor = 0.04 + ePow * 0.96;
  const fgChromaCeiling = Math.min(1, 0.15 + e * 0.45 + ePow * 0.50);

  // ── Lightness: dark dip at midpoint, the rest follows energy ──
  const deepDip = bump(e, 0.50, 0.25);

  // Low energy: wide range. Dip: forced dark. High energy: let peakChromaL drive it.
  const bgLMin = 0.40 - deepDip * 0.30;
  const bgLMax = 0.85 - deepDip * 0.38;
  const bgLBias = -deepDip * 0.30;

  // FG direction: up during dark dip, away otherwise
  const fgBias = deepDip * 1.0;

  // FG push: just enough for the active contrast level
  const fgMinPush = 0.25 + deepDip * 0.20;
  const fgLBias = deepDip * 0.15;

  // Hue width: wide at low energy, tight at high
  const hueWidth = 55 - e * 30;

  // Glow
  const glowL = 0.55 + e * 0.20 - deepDip * 0.15;
  const glowC = 0.08 + e * 0.32;

  return {
    bgChromaFloor, bgChromaCeiling,
    bgLMin: Math.max(0.08, bgLMin),
    bgLMax: Math.max(bgLMin + 0.10, bgLMax),
    bgLBias,
    fgChromaFloor, fgChromaCeiling,
    fgLBias, fgMinPush, fgBias,
    hueWidth: Math.max(15, hueWidth),
    glowL, glowC,
  };
}

/** Get the glow color for the dial ring. */
export function glowForKnob(knob: number, hCenter: number): OklchColor {
  const p = resolveEnergy(knob);
  return { mode: "oklch", l: p.glowL, c: p.glowC, h: hCenter };
}

// ── Generative descriptor ────────────────────────────────────────────
// Reads the current parameter state and produces a plain-English feel phrase.

export function energyDescriptor(knob: number): string {
  const e = energy(knob);
  const deepDip = bump(e, 0.50, 0.25);

  // Deep dip override — this moment is distinctive
  if (deepDip > 0.6) return "rich, dark luxury";
  if (deepDip > 0.3) {
    return e < 0.5 ? "deepening warmth" : "emerging from depth";
  }

  if (e < 0.08) return "near silence";
  if (e < 0.18) return "soft editorial calm";
  if (e < 0.30) return "warm, grounded confidence";
  if (e < 0.42) return "building energy";
  // Post-dip climb
  if (e < 0.62) return "bold and direct";
  if (e < 0.75) return "vivid intensity";
  if (e < 0.88) return "vivid and electric";
  return "maximum energy";
}

/** Secondary readout combining feel + accent mode + hue family. */
export function mkReadout(knob: number, relMode: RelModeId, hCenter: number): string {
  const desc = energyDescriptor(knob);
  const mode = REL_MODES.find((m) => m.id === relMode)!;
  const family = hueFamily(hCenter).toLowerCase();
  return `${desc} · ${mode.description.toLowerCase()} · ${family}`;
}

// ── Neutral meta color for secondary card text ───────────────────────

export function getNeutralMeta(bgColor: OklchColor): string {
  return bgColor.l > 0.55
    ? oklchToCss({ mode: "oklch", l: 0.15, c: 0.02, h: bgColor.h })
    : oklchToCss({ mode: "oklch", l: 0.92, c: 0.02, h: bgColor.h });
}

// ── Hue family name ──────────────────────────────────────────────────

export function hueFamily(h: number): string {
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

// ── Relationship modes ───────────────────────────────────────────────

export type RelModeId = "mono" | "analog" | "split" | "complement" | "triad" | "neutral+" | "random";

export interface RelationshipMode {
  id: RelModeId;
  label: string;
  description: string;
}

export const REL_MODES: RelationshipMode[] = [
  { id: "mono",       label: "MONO",       description: "Same hue as primary" },
  { id: "analog",     label: "ANALOG",     description: "Close hue neighbor" },
  { id: "split",      label: "SPLIT",      description: "Flanks the opposite hue" },
  { id: "complement", label: "COMPLEMENT", description: "Opposite hue" },
  { id: "triad",      label: "TRIAD",      description: "Three-hue triangle rotation" },
  { id: "neutral+",   label: "NEUTRAL+",   description: "Primary goes neutral, accent goes vivid" },
  { id: "random",     label: "RANDOM",     description: "Accent hue varies per card" },
];

function relModeOffset(mode: RelModeId, cardIndex: number): number {
  switch (mode) {
    case "mono": return 0;
    case "analog": return (cardIndex % 2 === 0 ? 1 : -1) * (25 + Math.abs(((cardIndex * 7) % 16) - 8));
    case "split": return cardIndex % 2 === 0 ? 150 : 210;
    case "complement": return 180;
    case "triad": return cardIndex % 2 === 0 ? 120 : 240;
    case "neutral+": return 180;
    case "random": return Math.random() * 360;
  }
}

function fgHueVariance(mode: RelModeId): number {
  if (mode === "mono") return 5;
  if (mode === "random") return 180;
  return 10;
}

// ── Contrast helpers ─────────────────────────────────────────────────

export function contrastThreshold(level: ContrastLevel): number {
  switch (level) {
    case "accessible": return 4.5;
    case "display": return 3.0;
    case "clash": return 1.5;
  }
}

function minLGap(level: ContrastLevel): number {
  switch (level) {
    case "accessible": return 0.40;
    case "display": return 0.22;
    case "clash": return 0.15;
  }
}

export function findPassingFg(bg: OklchColor, level: ContrastLevel = "display"): OklchColor | null {
  const threshold = contrastThreshold(level);
  const gap = minLGap(level);
  const direction = bg.l > 0.55 ? -1 : 1;
  const startL = direction > 0 ? Math.max(0.05, bg.l - gap) : Math.min(0.95, bg.l + gap);
  let testL = startL;
  for (let step = 0; step < 20; step++) {
    const clamped = Math.max(0, Math.min(1, testL));
    const fg: OklchColor = { mode: "oklch", l: clamped, c: Math.min(bg.c * 0.3, 0.05), h: bg.h };
    if (contrastRatio(bg, fg) >= threshold) return fg;
    testL += direction * -0.03;
  }
  const extreme: OklchColor = { mode: "oklch", l: direction > 0 ? 0 : 1, c: 0, h: 0 };
  return contrastRatio(bg, extreme) >= threshold ? extreme : null;
}

function findPassingFgWithHue(bg: OklchColor, fgH: number, fgC: number, intendedL: number, fgBias: number, level: ContrastLevel = "display"): OklchColor | null {
  const threshold = contrastThreshold(level);
  let direction: number;
  if (fgBias > 0.5) direction = 1;
  else if (fgBias < -0.5) direction = -1;
  else direction = bg.l > 0.55 ? -1 : 1;

  let testL = intendedL;
  for (let step = 0; step < 25; step++) {
    const clamped = Math.max(0, Math.min(1, testL));
    const fg: OklchColor = { mode: "oklch", l: clamped, c: fgC, h: fgH };
    if (contrastRatio(bg, fg) >= threshold) return fg;
    testL += direction * 0.025;
  }
  return findPassingFg(bg, level);
}

// ── Variation waveform ────────────────────────────────────────────────

export type VariMode = "smooth" | "wild";

/** Compute deviation waveform: array of energy offsets per card (in degrees). */
export function computeWaveform(count: number, spread: number, mode: VariMode): number[] {
  const maxDev = spread * 144; // spread 1.0 → ±144° (40% of 360)
  const wave: number[] = [];
  for (let i = 0; i < count; i++) {
    if (spread === 0) { wave.push(0); continue; }
    if (mode === "smooth") {
      // Sine wave across the card grid
      const phase = (i / Math.max(1, count - 1)) * Math.PI * 2;
      wave.push(Math.sin(phase) * maxDev);
    } else {
      // Wild: seeded pseudo-random per card (deterministic per index)
      const h = halton(i, 7);
      wave.push((h * 2 - 1) * maxDev);
    }
  }
  return wave;
}

// ── Generation ───────────────────────────────────────────────────────

export interface MKRampColor extends RampColor {
  mkFg?: OklchColor;
  mkMeta?: string;
}

export function generateMacroKnob(
  knob: number,
  hCenter: number,
  count: number,
  spread: number,
  variMode: VariMode,
  relMode: RelModeId,
  level: ContrastLevel,
): MKRampColor[] {
  const waveform = computeWaveform(count, spread, variMode);
  const isNeutralPlus = relMode === "neutral+";
  const isClash = level === "clash";
  const threshold = contrastThreshold(level);
  const lGap = minLGap(level);

  const genCount = level === "accessible" ? count * 2 : count;
  const result: MKRampColor[] = [];

  for (let i = 0; i < genCount && result.length < count; i++) {
    const cardIdx = i % count;
    // Per-card energy: base knob + waveform deviation, clamped to [0, 360]
    const cardKnob = ((knob + waveform[cardIdx]) % 360 + 360) % 360;
    const p = resolveEnergy(cardKnob);

    const bgChromaCeiling = isNeutralPlus ? Math.min(p.bgChromaCeiling, 0.15) : p.bgChromaCeiling;
    const bgChromaFloor = isNeutralPlus ? Math.min(p.bgChromaFloor, 0.08) : p.bgChromaFloor;

    const usePeakBias = bgChromaCeiling >= 0.80;
    const peakBlendFactor = usePeakBias ? Math.min(1, (bgChromaCeiling - 0.50) / 0.50) : 0;

    const bgLBias = (p.bgLBias + 1) / 2;

    // ── BG ───────────────────────────────────────────────────
    const bgHueVar = (halton(i, 2) - 0.5) * p.hueWidth;
    const bgH = ((hCenter + bgHueVar) % 360 + 360) % 360;

    // Hue-aware lightness window tightening at high energy
    const cardE = energy(cardKnob);
    const tightenStart = 0.65;
    if (cardE > tightenStart) {
      const tightenT = (cardE - tightenStart) / (1 - tightenStart);
      const peak = peakChromaL(bgH);
      const halfWindow = 0.22 - tightenT * 0.10; // 0.22 → 0.12
      const tightMin = Math.max(0.08, peak - halfWindow);
      const tightMax = Math.min(0.95, peak + halfWindow);
      p.bgLMin = p.bgLMin + tightenT * (tightMin - p.bgLMin);
      p.bgLMax = p.bgLMax + tightenT * (tightMax - p.bgLMax);
    }

    const t = halton(i, 3);
    const uniformL = (1 - t) * (1 - t) * p.bgLMin + 2 * (1 - t) * t * (p.bgLMin + (p.bgLMax - p.bgLMin) * bgLBias) + t * t * p.bgLMax;

    let bgL: number;
    if (peakBlendFactor > 0) {
      const peak = peakChromaL(bgH);
      const clampedPeak = Math.max(p.bgLMin, Math.min(p.bgLMax, peak));
      bgL = uniformL + peakBlendFactor * (clampedPeak - uniformL);
    } else {
      bgL = uniformL;
    }

    const bgRelC = bgChromaFloor + halton(i, 5) * (bgChromaCeiling - bgChromaFloor);
    const bgC = relativeToAbsoluteChroma(bgRelC, bgL, bgH);

    const correctedBgL = bgChromaCeiling >= 0.50 ? hkLightnessCorrection(bgL, bgC, bgH) : bgL;
    const bg: OklchColor = { mode: "oklch", l: correctedBgL, c: bgC, h: bgH };

    // ── FG ───────────────────────────────────────────────────
    let fgH: number;
    if (isClash) {
      const clashOffset = 90 + halton(i, 13) * 60;
      fgH = ((bgH + clashOffset) % 360 + 360) % 360;
    } else {
      const offset = relModeOffset(relMode, i);
      const fgHueVar = (halton(i, 7) - 0.5) * fgHueVariance(relMode) * 2;
      fgH = ((hCenter + offset + fgHueVar) % 360 + 360) % 360;
    }

    const effectiveGap = isClash
      ? (0.15 + halton(i, 17) * 0.07)
      : Math.max(lGap, p.fgMinPush);

    let fgL: number;
    if (p.fgBias > 0.5) {
      fgL = Math.min(0.95, correctedBgL + effectiveGap);
    } else if (p.fgBias < -0.5) {
      fgL = Math.max(0.05, correctedBgL - effectiveGap);
    } else {
      fgL = correctedBgL > 0.55
        ? Math.max(0.05, correctedBgL - effectiveGap)
        : Math.min(0.95, correctedBgL + effectiveGap);
    }
    fgL = Math.max(0, Math.min(1, fgL + p.fgLBias * 0.15));

    const fgRelC = p.fgChromaFloor + halton(i, 11) * (p.fgChromaCeiling - p.fgChromaFloor);
    const fgC = relativeToAbsoluteChroma(fgRelC, fgL, fgH);

    const correctedFgL = p.fgChromaCeiling >= 0.50 ? hkLightnessCorrection(fgL, fgC, fgH) : fgL;
    let fg: OklchColor | null = { mode: "oklch", l: correctedFgL, c: fgC, h: fgH };

    if (contrastRatio(bg, fg) < threshold) {
      fg = findPassingFgWithHue(bg, fgH, fgC, correctedFgL, p.fgBias, level);
      if (!fg) continue;
    }

    const cardEnergy = energy(cardKnob);
    const badge = `${hueFamily(bgH).toUpperCase().slice(0, 3)} ${Math.round(cardEnergy * 100)}%`;
    const meta = getNeutralMeta(bg);

    result.push({ color: bg, badge, mkFg: fg, mkMeta: meta });
  }

  return result.slice(0, count);
}

// ── Flip ─────────────────────────────────────────────────────────────

export function flipCard(
  bg: OklchColor,
  fg: OklchColor,
  level: ContrastLevel,
): { bg: OklchColor; fg: OklchColor } {
  const newBg = fg;
  const newFg = findPassingFgWithHue(newBg, bg.h, bg.c, bg.l, 0, level);
  return { bg: newBg, fg: newFg || bg };
}
