import {
  maxChroma as getMaxChroma,
  contrastRatio,
  safeColor,
  hueDifference,
} from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type { BrandKitColors } from "../types";

// ── Binary-search: find L that passes AA (4.5:1) against a surface ───

function searchL(
  hue: number,
  chroma: number,
  surface: OklchColor,
  searchDark: boolean,
): number {
  const P = 0.002;
  let lo = searchDark ? 0 : surface.l;
  let hi = searchDark ? surface.l : 1;
  while (hi - lo > P) {
    const mid = (lo + hi) / 2;
    const t: OklchColor = { mode: "oklch", l: mid, c: chroma, h: hue };
    const passes = contrastRatio(t, surface) >= 4.5;
    if (searchDark) {
      if (passes) lo = mid; else hi = mid;
    } else {
      if (passes) hi = mid; else lo = mid;
    }
  }
  return searchDark ? lo : hi;
}

// ── Derivation functions ─────────────────────────────────────────────

/**
 * Body text: softer version of the headline color.
 * Same hue as fg, lightness pulled toward bg, chroma reduced ~30%.
 * Guaranteed AA (4.5:1) against bg.
 */
export function deriveBody(fg: OklchColor, bg: OklchColor): OklchColor {
  const hue = fg.h;
  const chroma = Math.max(fg.c * 0.7, 0.005);

  // Pull lightness 30% toward bg
  let l = fg.l + (bg.l - fg.l) * 0.3;
  l = Math.max(0.05, Math.min(0.95, l));

  const candidate: OklchColor = { mode: "oklch", l, c: chroma, h: hue };

  // If it already passes AA, use it
  if (contrastRatio(candidate, bg) >= 4.5) return safeColor(candidate);

  // Otherwise binary-search for a lightness that passes
  const isLightBg = bg.l > 0.5;
  const safeL = searchL(hue, chroma, bg, isLightBg);
  return safeColor({ mode: "oklch", l: safeL, c: chroma, h: hue });
}

/**
 * Surface: alternate background for cards, sections, footers.
 * Same hue as bg, lightness nudged 5-8% toward midpoint (0.5).
 */
export function deriveSurface(bg: OklchColor): OklchColor {
  const direction = bg.l > 0.5 ? -1 : 1;
  const nudge = 0.065; // ~6.5% shift
  const l = Math.max(0.05, Math.min(0.95, bg.l + direction * nudge));
  const c = Math.min(bg.c * 1.1, 0.02); // keep very low chroma
  return safeColor({ mode: "oklch", l, c, h: bg.h });
}

/**
 * Accent: action color for buttons, links, CTAs.
 * Fg hue shifted 120-150 degrees (direction furthest from bg hue),
 * max chroma, must pass AA against both bg and surface.
 */
export function deriveAccent(
  fg: OklchColor,
  bg: OklchColor,
  surface: OklchColor,
): OklchColor {
  // Pick hue shift direction furthest from bg hue
  const shiftAmount = 135; // midpoint of 120-150
  const optionA = ((fg.h + shiftAmount) % 360 + 360) % 360;
  const optionB = ((fg.h - shiftAmount) % 360 + 360) % 360;
  const hue =
    hueDifference(optionA, bg.h) >= hueDifference(optionB, bg.h)
      ? optionA
      : optionB;

  // Start at mid-lightness with max chroma
  const startL = 0.55;
  const c = getMaxChroma(startL, hue) * 0.9; // 90% of max for safety margin

  // Check if starting point passes AA against both surfaces
  const candidate: OklchColor = { mode: "oklch", l: startL, c, h: hue };
  const passesBg = contrastRatio(candidate, bg) >= 4.5;
  const passesSurface = contrastRatio(candidate, surface) >= 4.5;

  if (passesBg && passesSurface) return safeColor(candidate);

  // Binary-search for L that passes against BOTH
  const isLightBg = bg.l > 0.5;
  const P = 0.002;
  let lo = isLightBg ? 0 : 0.5;
  let hi = isLightBg ? 0.5 : 1;

  while (hi - lo > P) {
    const mid = (lo + hi) / 2;
    const mc = getMaxChroma(mid, hue) * 0.9;
    const t: OklchColor = { mode: "oklch", l: mid, c: mc, h: hue };
    const ok = contrastRatio(t, bg) >= 4.5 && contrastRatio(t, surface) >= 4.5;
    if (isLightBg) {
      if (ok) lo = mid; else hi = mid;
    } else {
      if (ok) hi = mid; else lo = mid;
    }
  }

  const finalL = isLightBg ? lo : hi;
  const finalC = getMaxChroma(finalL, hue) * 0.9;
  return safeColor({ mode: "oklch", l: finalL, c: finalC, h: hue });
}

// ── Orchestrator ─────────────────────────────────────────────────────

/**
 * Derive a complete 5-color brand kit from a bg + fg pair.
 */
export function deriveBrandKit(
  bg: OklchColor,
  fg: OklchColor,
): BrandKitColors {
  const surface = deriveSurface(bg);
  const body = deriveBody(fg, bg);
  const accent = deriveAccent(fg, bg, surface);
  return { bg, headline: fg, body, surface, accent };
}
