import type { OklchColor } from "../../utils/oklch";

// ── Shared ramp types ─────────────────────────────────────────────────

export interface RampColor {
  color: OklchColor;
  badge: string;
  /** Pre-computed foreground CSS — used by Role Builder pairings */
  fgCss?: string;
}

export type ChromaMode = "max" | "fixed";
export type RoleTheme = "light" | "dark";
export type ContrastLevel = "display" | "clash" | "accessible";
export type ColorVariety = "tight" | "auto" | "wide";

export type MethodName =
  | "Hue Lock"
  | "Temperature Corridor"
  | "Contrast Safe"
  | "Role Builder"
  | "Extract"
  | "Word Picker"
  | "Macro Knob";

// ── Hue Lock ──────────────────────────────────────────────────────────

export interface HueLockParams {
  hue: number;
  steps: number;
  chromaMode: ChromaMode;
  fixedChroma: number;
  accentEnabled: boolean;
  accentHue: number;
  accentL: number;
  /** Pre-computed L values from tone curve. If omitted, uses linear ramp. */
  lValues?: number[];
}

// ── Temperature Corridor ──────────────────────────────────────────────

export interface TempCorridorParams {
  hCenter: number;
  tempWidth: number;
  chromaMin: number;
  chromaMax: number;
  lRange: [number, number];
  count: number;
  /** 0-1: fraction of gamut. When true, chromaMin/Max are relative to maxChroma. */
  useRelativeChroma?: boolean;
  /** 0-1: lightness midpoint bias. 0.5 = linear. <0.5 biases dark, >0.5 biases light. */
  lMidBias?: number;
}

// ── Contrast Safe ─────────────────────────────────────────────────────

export type HueMode = "full" | "neighborhood";
export type Threshold = "AA" | "AAA";

export interface ContrastSafeParams {
  primary: OklchColor;
  lRange: [number, number];
  cRange: [number, number];
  hueMode: HueMode;
  threshold: Threshold;
  density: number;
  fgLock: boolean;
}

export interface ContrastRampColor extends RampColor {
  passes: boolean;
  ratio: number;
}

// ── Brand Kit roles ───────────────────────────────────────────────────

export type RoleName = "primary" | "background" | "text" | "secondary" | "highlight";

export type RoleOverrides = {
  background: OklchColor | null;
  text: OklchColor | null;
  secondary: OklchColor | null;
  highlight: OklchColor | null;
};

export interface DerivedRoles {
  primary: OklchColor;
  primaryHex: string;
  background: OklchColor;
  backgroundHex: string;
  text: OklchColor;
  textHex: string;
  secondary: OklchColor;
  secondaryHex: string;
  highlight: OklchColor;
  highlightHex: string;
}

export interface RoleBuilderParams {
  primary: OklchColor;
  theme: RoleTheme;
  accentOffset: number;
  accentChromaMult: number;
  overrides: RoleOverrides;
}

// ── Extract ───────────────────────────────────────────────────────────

export interface ExtractedCluster {
  color: OklchColor;
  label: string;
  size: number;
}
