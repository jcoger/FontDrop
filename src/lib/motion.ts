import { useReducedMotion } from "framer-motion";

// ── Easing curves (mirrors CSS custom properties) ────────────────────────────
export const easeOut: [number, number, number, number] = [0.25, 0.46, 0.45, 0.94];
export const easeInOut: [number, number, number, number] = [0.45, 0.03, 0.515, 0.955];
export const easeHover: [number, number, number, number] = [0.25, 0.1, 0.25, 1];

// ── Durations (seconds, for Framer Motion) ───────────────────────────────────
export const dur = {
  micro: 0.1,
  fast: 0.15,
  normal: 0.2,
  exit: 0.16,
} as const;

// ── Spring presets ───────────────────────────────────────────────────────────
export const springSnap = { type: "spring" as const, bounce: 0.15, duration: 0.25 };
export const springModal = { type: "spring" as const, bounce: 0.1, duration: 0.2 };

// ── Reduced motion hook ──────────────────────────────────────────────────────
export { useReducedMotion };

/** Returns `false` (skip animation) when user prefers reduced motion. */
export function initialIfMotion<T>(value: T): T | false {
  const reduced = useReducedMotion();
  return reduced ? false : value;
}
