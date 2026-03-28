import {
  clampChroma,
  displayable,
  converter,
  type Oklch,
  type Rgb,
} from 'culori';

// ── Types ──────────────────────────────────────────────────────────────
export type OklchColor = { mode: 'oklch'; l: number; c: number; h: number };

// ── Display-P3 detection ──────────────────────────────────────────────
// Evaluated once at module load. True on all modern Macs.
export const supportsP3 = typeof CSS !== 'undefined' && CSS.supports('color', 'color(display-p3 0 0 0)');

/** The gamut target for clampChroma: 'p3' on P3 displays, 'rgb' on sRGB. */
const GAMUT: 'p3' | 'rgb' = supportsP3 ? 'p3' : 'rgb';

// ── Helpers ────────────────────────────────────────────────────────────
const toOklch = converter('oklch');
const toRgb = converter('rgb');
const toP3 = converter('p3');

// ── Core functions ─────────────────────────────────────────────────────

/** Clamp chroma until the color is displayable in the active gamut (P3 or sRGB). */
export function safeColor(color: OklchColor): OklchColor {
  return clampChroma(color, 'oklch', GAMUT) as OklchColor;
}

/** Check whether a color is displayable in the active gamut. */
export function isDisplayable(color: OklchColor): boolean {
  if (supportsP3) {
    const p3 = toP3(color);
    return p3.r >= -0.001 && p3.r <= 1.001 && p3.g >= -0.001 && p3.g <= 1.001 && p3.b >= -0.001 && p3.b <= 1.001;
  }
  return displayable(color);
}

/** Binary-search the maximum chroma at a given L and H that stays in the active gamut. */
export function maxChroma(l: number, h: number, precision = 0.001): number {
  let lo = 0;
  let hi = supportsP3 ? 0.5 : 0.4; // P3 gamut is wider
  while (hi - lo > precision) {
    const mid = (lo + hi) / 2;
    if (isDisplayable({ mode: 'oklch', l, c: mid, h })) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/** Return the lightness (0–1) at which maxChroma is highest for a given hue.
 *  Cached by integer hue so only computed once per degree. */
const _peakLCache = new Map<number, number>();
export function peakChromaL(h: number): number {
  const key = Math.round(((h % 360) + 360) % 360);
  const cached = _peakLCache.get(key);
  if (cached !== undefined) return cached;
  let bestL = 0.5;
  let bestC = 0;
  for (let l = 0.20; l <= 0.85; l += 0.05) {
    const c = maxChroma(l, key);
    if (c > bestC) { bestC = c; bestL = l; }
  }
  _peakLCache.set(key, bestL);
  return bestL;
}

/**
 * Helmholtz-Kohlrausch lightness correction.
 * Reduces L for high-chroma greens/yellows to match perceived brightness
 * of other hues at the same L value.
 *
 * Effect peaks at hue ~145° (yellow-green), tapers to zero at
 * blues (~230°) and reds (~10°/350°).
 * Only applies above chroma threshold — muted colors unaffected.
 */
export function hkLightnessCorrection(l: number, c: number, h: number): number {
  const chromaWeight = Math.max(0, Math.min(1, (c - 0.15) / 0.20));
  const huePeak = 145;
  const angleDiff = Math.abs(((h - huePeak + 180) % 360) - 180);
  const hueWeight = angleDiff >= 90 ? 0 : Math.max(0, Math.cos((angleDiff / 90) * (Math.PI / 2)));
  const correction = chromaWeight * hueWeight * 0.09;
  return Math.max(0.08, l - correction);
}

/** Convert a relative chroma (0-1, fraction of gamut) to absolute chroma.
 *  Accounts for the fact that cool hues have lower max chroma than warm ones.
 *  relChroma=1 means "as vivid as this hue can get at this lightness". */
export function relativeToAbsoluteChroma(relChroma: number, l: number, h: number): number {
  const mc = maxChroma(l, h);
  return Math.min(relChroma * mc, mc);
}

/** Relative luminance (WCAG definition) from an OklchColor.
 *  Uses the active gamut for clamping, then converts to linear sRGB for the WCAG formula.
 *  WCAG luminance is always defined in sRGB — P3 colors are mapped to their sRGB
 *  representation for the contrast calculation. */
export function relativeLuminance(color: OklchColor): number {
  // Always compute luminance in sRGB space (WCAG spec requirement)
  const safe = clampChroma(color, 'oklch', 'rgb');
  const rgb = toRgb(safe) as Rgb;

  const linearize = (c: number): number =>
    c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;

  const R = linearize(rgb.r);
  const G = linearize(rgb.g);
  const B = linearize(rgb.b);

  return 0.2126 * R + 0.7152 * G + 0.0722 * B;
}

/** WCAG contrast ratio between two colors. */
export function contrastRatio(a: OklchColor, b: OklchColor): number {
  const lA = relativeLuminance(a);
  const lB = relativeLuminance(b);
  const lighter = Math.max(lA, lB);
  const darker = Math.min(lA, lB);
  return (lighter + 0.05) / (darker + 0.05);
}

/** Map a contrast ratio to a WCAG level string. */
export function contrastLevel(ratio: number): 'AAA' | 'AA' | 'AA-large' | 'FAIL' {
  if (ratio >= 7) return 'AAA';
  if (ratio >= 4.5) return 'AA';
  if (ratio >= 3) return 'AA-large';
  return 'FAIL';
}

/** Convert an OklchColor to a CSS color string.
 *  P3 displays: color(display-p3 r g b) — wider gamut, more vivid colors.
 *  sRGB displays: rgb(R,G,B) — standard fallback. */
export function oklchToCss(color: OklchColor): string {
  if (supportsP3) {
    const safe = clampChroma(color, 'oklch', 'p3');
    const p3 = toP3(safe);
    const clamp = (c: number) => Math.min(1, Math.max(0, c));
    return `color(display-p3 ${clamp(p3.r).toFixed(4)} ${clamp(p3.g).toFixed(4)} ${clamp(p3.b).toFixed(4)})`;
  }
  const safe = clampChroma(color, 'oklch', 'rgb');
  const rgb = toRgb(safe) as Rgb;
  const to255 = (c: number) => Math.round(Math.min(1, Math.max(0, c)) * 255);
  return `rgb(${to255(rgb.r)},${to255(rgb.g)},${to255(rgb.b)})`;
}

/** Convert an OklchColor to a hex-like string for export/clipboard.
 *  P3 displays: returns color(display-p3 r g b) since hex can't represent P3.
 *  sRGB displays: returns #rrggbb hex. */
export function oklchToHex(color: OklchColor): string {
  if (supportsP3) {
    const safe = clampChroma(color, 'oklch', 'p3');
    const p3 = toP3(safe);
    const clamp = (c: number) => Math.min(1, Math.max(0, c));
    return `color(display-p3 ${clamp(p3.r).toFixed(4)} ${clamp(p3.g).toFixed(4)} ${clamp(p3.b).toFixed(4)})`;
  }
  const safe = clampChroma(color, 'oklch', 'rgb');
  const rgb = toRgb(safe) as Rgb;
  const to255 = (c: number) => Math.round(Math.min(1, Math.max(0, c)) * 255);
  return '#' + [to255(rgb.r), to255(rgb.g), to255(rgb.b)].map(v => v.toString(16).padStart(2, '0')).join('');
}

/** Always returns a #rrggbb hex string (sRGB), even on P3 displays.
 *  Used for contexts that require hex format (clipboard, etc). */
export function oklchToSrgbHex(color: OklchColor): string {
  const safe = clampChroma(color, 'oklch', 'rgb');
  const rgb = toRgb(safe) as Rgb;
  const to255 = (c: number) => Math.round(Math.min(1, Math.max(0, c)) * 255);
  return '#' + [to255(rgb.r), to255(rgb.g), to255(rgb.b)].map(v => v.toString(16).padStart(2, '0')).join('');
}

/** Parse a hex string to an OklchColor. */
export function hexToOklch(hex: string): OklchColor {
  const clean = hex.replace('#', '');
  const r = parseInt(clean.slice(0, 2), 16) / 255;
  const g = parseInt(clean.slice(2, 4), 16) / 255;
  const b = parseInt(clean.slice(4, 6), 16) / 255;

  const oklch = toOklch({ mode: 'rgb', r, g, b }) as Oklch;
  return { mode: 'oklch', l: oklch.l, c: oklch.c, h: oklch.h ?? 0 };
}

/** Shortest-arc hue difference in degrees (0-180). */
export function hueDifference(h1: number, h2: number): number {
  const d = Math.abs(h1 - h2);
  return Math.min(d, 360 - d);
}

/** Circular mean of an array of hue angles (degrees). */
export function circularMean(hues: number[]): number {
  if (hues.length === 0) return 0;
  let sinSum = 0;
  let cosSum = 0;
  for (const h of hues) {
    const rad = (h * Math.PI) / 180;
    sinSum += Math.sin(rad);
    cosSum += Math.cos(rad);
  }
  const mean = (Math.atan2(sinSum / hues.length, cosSum / hues.length) * 180) / Math.PI;
  return ((mean % 360) + 360) % 360;
}

/** Halton low-discrepancy sequence value for a given index and base. */
export function halton(index: number, base: number): number {
  let result = 0;
  let f = 1;
  let i = index + 1;
  while (i > 0) {
    f /= base;
    result += f * (i % base);
    i = Math.floor(i / base);
  }
  return result;
}

// ── Sanity checks ──────────────────────────────────────────────────────
const black: OklchColor = { mode: 'oklch', l: 0, c: 0, h: 0 };
const white: OklchColor = { mode: 'oklch', l: 1, c: 0, h: 0 };

console.log('[oklch] contrastRatio(black, white):', contrastRatio(black, white));
console.log('[oklch] maxChroma(0.5, 270):', maxChroma(0.5, 270));

const testColor: OklchColor = { mode: 'oklch', l: 0.7, c: 0.1, h: 150 };
const safed = safeColor(testColor);
console.log('[oklch] safeColor identity test:', { input: testColor, output: safed });
