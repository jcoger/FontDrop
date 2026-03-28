import {
  maxChroma as getMaxChroma,
  contrastRatio,
  oklchToCss,
  oklchToHex,
  hexToOklch,
} from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type {
  RampColor,
  RoleName,
  RoleOverrides,
  DerivedRoles,
  RoleBuilderParams,
} from "../types";

export type { RoleName, RoleOverrides, DerivedRoles, RoleBuilderParams };

// ── Binary-search helpers ─────────────────────────────────────────────

/** Find L for text that passes AA contrast against background. */
function findTextL(primaryH: number, background: OklchColor, isLight: boolean): number {
  const P = 0.002;
  if (isLight) {
    let lo = 0, hi = background.l;
    while (hi - lo > P) {
      const mid = (lo + hi) / 2;
      const t: OklchColor = { mode: "oklch", l: mid, c: 0.02, h: primaryH };
      if (contrastRatio(t, background) >= 4.5) lo = mid; else hi = mid;
    }
    return lo;
  }
  let lo = background.l, hi = 1;
  while (hi - lo > P) {
    const mid = (lo + hi) / 2;
    const t: OklchColor = { mode: "oklch", l: mid, c: 0.02, h: primaryH };
    if (contrastRatio(t, background) >= 4.5) hi = mid; else lo = mid;
  }
  return hi;
}

/** Find highlight L that passes AA against background. */
function findHighlightL(startL: number, background: OklchColor, isLight: boolean): number {
  const H = 25;
  const mc = getMaxChroma(startL, H);
  const test: OklchColor = { mode: "oklch", l: startL, c: mc, h: H };
  if (contrastRatio(test, background) >= 4.5) return startL;

  const P = 0.002;
  if (isLight) {
    let lo = 0, hi = startL;
    while (hi - lo > P) {
      const mid = (lo + hi) / 2;
      const t: OklchColor = { mode: "oklch", l: mid, c: getMaxChroma(mid, H), h: H };
      if (contrastRatio(t, background) >= 4.5) lo = mid; else hi = mid;
    }
    return lo;
  }
  let lo = startL, hi = 1;
  while (hi - lo > P) {
    const mid = (lo + hi) / 2;
    const t: OklchColor = { mode: "oklch", l: mid, c: getMaxChroma(mid, H), h: H };
    if (contrastRatio(t, background) >= 4.5) hi = mid; else lo = mid;
  }
  return hi;
}

// ── Derivation ────────────────────────────────────────────────────────

export function deriveRoles(params: RoleBuilderParams): DerivedRoles {
  const { primary, theme, accentOffset, accentChromaMult, overrides } = params;
  const isLight = theme === "light";

  const background: OklchColor = overrides.background || {
    mode: "oklch",
    l: isLight ? 0.95 : 0.15,
    c: 0.01,
    h: primary.h,
  };

  const text: OklchColor = overrides.text || {
    mode: "oklch",
    l: findTextL(primary.h, background, isLight),
    c: 0.02,
    h: primary.h,
  };

  const secondaryH = ((primary.h + accentOffset) % 360 + 360) % 360;
  const secondaryC = Math.min(primary.c * accentChromaMult, getMaxChroma(primary.l, secondaryH));
  const secondary: OklchColor = overrides.secondary || {
    mode: "oklch",
    l: primary.l,
    c: secondaryC,
    h: secondaryH,
  };

  const highlightH = 25;
  const highlightL = findHighlightL(primary.l, background, isLight);
  const highlightC = getMaxChroma(highlightL, highlightH);
  const highlight: OklchColor = overrides.highlight || { mode: "oklch", l: highlightL, c: highlightC, h: highlightH };

  return {
    primary,        primaryHex:    oklchToHex(primary),
    background,     backgroundHex: oklchToHex(background),
    text,           textHex:       oklchToHex(text),
    secondary,      secondaryHex:  oklchToHex(secondary),
    highlight,      highlightHex:  oklchToHex(highlight),
  };
}

// ── Ramp pairings ─────────────────────────────────────────────────────

const PAIRINGS: { bg: RoleName; fg: RoleName; badge: string }[] = [
  { bg: "background", fg: "primary",   badge: "PRIMARY" },
  { bg: "background", fg: "secondary", badge: "SECONDARY" },
  { bg: "primary",    fg: "text",      badge: "TEXT" },
  { bg: "secondary",  fg: "text",      badge: "TEXT" },
  { bg: "background", fg: "highlight", badge: "HIGHLIGHT" },
];

export function rolePairings(roles: DerivedRoles): RampColor[] {
  return PAIRINGS.map(({ bg, fg, badge }) => ({
    color: roles[bg],
    badge,
    fgCss: oklchToCss(roles[fg]),
  }));
}

// ── Patch bay constants ───────────────────────────────────────────────

export const CONNECTORS: { from: RoleName; to: RoleName; label: string }[] = [
  { from: "primary",    to: "secondary",  label: "H +offset" },
  { from: "primary",    to: "background", label: "L adjust" },
  { from: "background", to: "text",       label: "AA search" },
  { from: "background", to: "highlight",  label: "H=25°" },
];

export const NODE_ORDER: { key: RoleName; label: string }[] = [
  { key: "primary",    label: "Primary" },
  { key: "secondary",  label: "Secondary" },
  { key: "background", label: "Background" },
  { key: "text",       label: "Text" },
  { key: "highlight",  label: "Highlight" },
];

export { hexToOklch };
