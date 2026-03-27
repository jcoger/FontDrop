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

/** Find the lightest L that still passes AA contrast against surface. */
function findOnSurfaceL(primaryH: number, surface: OklchColor, isLight: boolean): number {
  const P = 0.002;
  if (isLight) {
    let lo = 0, hi = surface.l;
    while (hi - lo > P) {
      const mid = (lo + hi) / 2;
      const t: OklchColor = { mode: "oklch", l: mid, c: 0.02, h: primaryH };
      if (contrastRatio(t, surface) >= 4.5) lo = mid; else hi = mid;
    }
    return lo;
  }
  let lo = surface.l, hi = 1;
  while (hi - lo > P) {
    const mid = (lo + hi) / 2;
    const t: OklchColor = { mode: "oklch", l: mid, c: 0.02, h: primaryH };
    if (contrastRatio(t, surface) >= 4.5) hi = mid; else lo = mid;
  }
  return hi;
}

/** Find error L that passes AA against surface. */
function findErrorL(startL: number, surface: OklchColor, isLight: boolean): number {
  const H = 25;
  const mc = getMaxChroma(startL, H);
  const test: OklchColor = { mode: "oklch", l: startL, c: mc, h: H };
  if (contrastRatio(test, surface) >= 4.5) return startL;

  const P = 0.002;
  if (isLight) {
    let lo = 0, hi = startL;
    while (hi - lo > P) {
      const mid = (lo + hi) / 2;
      const t: OklchColor = { mode: "oklch", l: mid, c: getMaxChroma(mid, H), h: H };
      if (contrastRatio(t, surface) >= 4.5) lo = mid; else hi = mid;
    }
    return lo;
  }
  let lo = startL, hi = 1;
  while (hi - lo > P) {
    const mid = (lo + hi) / 2;
    const t: OklchColor = { mode: "oklch", l: mid, c: getMaxChroma(mid, H), h: H };
    if (contrastRatio(t, surface) >= 4.5) hi = mid; else lo = mid;
  }
  return hi;
}

// ── Derivation ────────────────────────────────────────────────────────

export function deriveRoles(params: RoleBuilderParams): DerivedRoles {
  const { primary, theme, accentOffset, accentChromaMult, overrides } = params;
  const isLight = theme === "light";

  const surface: OklchColor = overrides.surface || {
    mode: "oklch",
    l: isLight ? 0.95 : 0.15,
    c: 0.01,
    h: primary.h,
  };

  const onSurface: OklchColor = overrides.onSurface || {
    mode: "oklch",
    l: findOnSurfaceL(primary.h, surface, isLight),
    c: 0.02,
    h: primary.h,
  };

  const accentH = ((primary.h + accentOffset) % 360 + 360) % 360;
  const accentC = Math.min(primary.c * accentChromaMult, getMaxChroma(primary.l, accentH));
  const accent: OklchColor = overrides.accent || {
    mode: "oklch",
    l: primary.l,
    c: accentC,
    h: accentH,
  };

  const errorH = 25;
  const errorL = findErrorL(primary.l, surface, isLight);
  const errorC = getMaxChroma(errorL, errorH);
  const error: OklchColor = overrides.error || { mode: "oklch", l: errorL, c: errorC, h: errorH };

  // Hex values computed once here — no need for rgbCssToHex hacks in UI
  return {
    primary,      primaryHex:   oklchToHex(primary),
    surface,      surfaceHex:   oklchToHex(surface),
    onSurface,    onSurfaceHex: oklchToHex(onSurface),
    accent,       accentHex:    oklchToHex(accent),
    error,        errorHex:     oklchToHex(error),
  };
}

// ── Ramp pairings ─────────────────────────────────────────────────────

const PAIRINGS: { bg: RoleName; fg: RoleName; badge: string }[] = [
  { bg: "surface",  fg: "primary",   badge: "PRIMARY" },
  { bg: "surface",  fg: "accent",    badge: "ACCENT" },
  { bg: "primary",  fg: "onSurface", badge: "ON-SURFACE" },
  { bg: "accent",   fg: "onSurface", badge: "ON-SURFACE" },
  { bg: "surface",  fg: "error",     badge: "ERROR" },
];

export function rolePairings(roles: DerivedRoles): RampColor[] {
  return PAIRINGS.map(({ bg, fg, badge }) => ({
    color: roles[bg],
    badge,
    fgCss: oklchToCss(roles[fg]),
  }));
}

// ── Patch bay constants ───────────────────────────────────────────────

// Connector wires shown in the patch bay: [from-role → to-role, label]
export const CONNECTORS: { from: RoleName; to: RoleName; label: string }[] = [
  { from: "primary", to: "accent",    label: "H +offset" },
  { from: "primary", to: "surface",   label: "L adjust" },
  { from: "surface", to: "onSurface", label: "AA search" },
  { from: "surface", to: "error",     label: "H=25°" },
];

// Display order for nodes in the patch bay
export const NODE_ORDER: { key: RoleName; label: string }[] = [
  { key: "primary",   label: "Primary" },
  { key: "accent",    label: "Accent" },
  { key: "surface",   label: "Surface" },
  { key: "onSurface", label: "On-Surface" },
  { key: "error",     label: "Error" },
];

// Re-export hexToOklch for convenience in the UI file
export { hexToOklch };
