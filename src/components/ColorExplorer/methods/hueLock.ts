import { maxChroma as getMaxChroma } from "../../../utils/oklch";
import type { RampColor, HueLockParams } from "../types";

export type { HueLockParams };

export function generateHueLock(params: HueLockParams): RampColor[] {
  const {
    hue,
    steps,
    chromaMode,
    fixedChroma,
    accentEnabled,
    accentHue,
    accentL,
    lValues,
  } = params;

  const ramp: RampColor[] = [];

  for (let i = 0; i < steps; i++) {
    const l = lValues
      ? lValues[i] ?? 0.54
      : steps === 1
        ? 0.54
        : L_MIN + (L_MAX - L_MIN) * (i / (steps - 1));
    const mc = getMaxChroma(l, hue);
    const c = chromaMode === "max" ? mc : Math.min(fixedChroma, mc);

    ramp.push({
      color: { mode: "oklch", l, c, h: hue },
      badge: `L: ${Math.round(l * 100)}%`,
    });
  }

  if (accentEnabled) {
    const mc = getMaxChroma(accentL, accentHue);
    ramp.push({
      color: { mode: "oklch", l: accentL, c: mc, h: accentHue },
      badge: "ACCENT",
    });
  }

  return ramp;
}

// ── Tone curve ────────────────────────────────────────────────────────

/** Lightness range boundaries shared by hueLock and ToneCurve canvas */
export const L_MIN = 0.15;
export const L_MAX = 0.93;

/**
 * Sample `count` L values from a quadratic bezier curve.
 * P0=(0, L_MIN), P1=(0.5, midY), P2=(1, L_MAX).
 * midY default = (L_MIN+L_MAX)/2 = 0.54 (linear).
 */
export function sampleToneCurve(count: number, midY: number): number[] {
  const values: number[] = [];
  for (let i = 0; i < count; i++) {
    const t = count === 1 ? 0.5 : i / (count - 1);
    const l =
      (1 - t) * (1 - t) * L_MIN +
      2 * (1 - t) * t * midY +
      t * t * L_MAX;
    values.push(Math.max(0, Math.min(1, l)));
  }
  return values;
}
