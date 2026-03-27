import {
  clampChroma,
  displayable,
  converter,
  type Oklch,
  type Rgb,
} from 'culori';

// ── Types ──────────────────────────────────────────────────────────────
export type OklchColor = { mode: 'oklch'; l: number; c: number; h: number };

// ── Helpers ────────────────────────────────────────────────────────────
const toOklch = converter('oklch');
const toRgb = converter('rgb');

// ── Core functions ─────────────────────────────────────────────────────

/** Clamp chroma until the color is displayable in sRGB. */
export function safeColor(color: OklchColor): OklchColor {
  return clampChroma(color, 'oklch', 'rgb') as OklchColor;
}

/** Check whether a color is displayable in sRGB. */
export function isDisplayable(color: OklchColor): boolean {
  return displayable(color);
}

/** Binary-search the maximum chroma at a given L and H that stays in sRGB. */
export function maxChroma(l: number, h: number, precision = 0.001): number {
  let lo = 0;
  let hi = 0.4;
  while (hi - lo > precision) {
    const mid = (lo + hi) / 2;
    if (displayable({ mode: 'oklch', l, c: mid, h })) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/** Relative luminance (WCAG definition) from an OklchColor. */
export function relativeLuminance(color: OklchColor): number {
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

/** Convert an OklchColor to an "rgb(R,G,B)" CSS string (0-255 channels). */
export function oklchToCss(color: OklchColor): string {
  const safe = clampChroma(color, 'oklch', 'rgb');
  const rgb = toRgb(safe) as Rgb;
  const to255 = (c: number) => Math.round(Math.min(1, Math.max(0, c)) * 255);
  return `rgb(${to255(rgb.r)},${to255(rgb.g)},${to255(rgb.b)})`;
}

/** Convert an OklchColor to a "#rrggbb" hex string. */
export function oklchToHex(color: OklchColor): string {
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
