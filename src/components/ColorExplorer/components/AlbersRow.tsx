import { useMemo } from "react";
import type { OklchColor } from "../../../utils/oklch";
import {
  oklchToCss,
  contrastRatio,
  contrastLevel,
  safeColor,
} from "../../../utils/oklch";

// ── Swatch definitions ────────────────────────────────────────────────

interface SwatchDef {
  label: string;
  getColor: (working: OklchColor, canvas: OklchColor) => OklchColor;
}

const SWATCHES: SwatchDef[] = [
  { label: "White", getColor: () => ({ mode: "oklch", l: 1, c: 0, h: 0 }) },
  { label: "Cream", getColor: () => ({ mode: "oklch", l: 0.96, c: 0.01, h: 90 }) },
  { label: "Lt Gray", getColor: () => ({ mode: "oklch", l: 0.85, c: 0, h: 0 }) },
  { label: "Mid Gray", getColor: () => ({ mode: "oklch", l: 0.6, c: 0, h: 0 }) },
  { label: "Dk Gray", getColor: () => ({ mode: "oklch", l: 0.3, c: 0, h: 0 }) },
  { label: "Black", getColor: () => ({ mode: "oklch", l: 0, c: 0, h: 0 }) },
  {
    label: "Complement",
    getColor: (wc) => ({ mode: "oklch", l: wc.l, c: wc.c * 0.6, h: (wc.h + 180) % 360 }),
  },
  { label: "Canvas", getColor: (_, canvas) => canvas },
];

const LEVEL_COLORS: Record<string, string> = {
  AAA: "var(--c-success)",
  AA: "var(--c-warning)",
  "AA-large": "var(--c-caution)",
  FAIL: "var(--c-error)",
};

// ── Component ─────────────────────────────────────────────────────────

interface AlbersRowProps {
  workingColor: OklchColor;
  canvasColor: OklchColor;
  expanded: boolean;
}

export function AlbersRow({ workingColor, canvasColor, expanded }: AlbersRowProps) {
  const workingCss = oklchToCss(workingColor);

  const swatches = useMemo(() => {
    return SWATCHES.map((s) => {
      const ctx = safeColor(s.getColor(workingColor, canvasColor));
      const ratio = contrastRatio(ctx, workingColor);
      const level = contrastLevel(ratio);
      return {
        label: s.label,
        bgCss: oklchToCss(ctx),
        ratio,
        level,
        levelColor: LEVEL_COLORS[level],
        labelColor: ctx.l > 0.5 ? "rgba(0,0,0,0.45)" : "rgba(255,255,255,0.45)",
      };
    });
  }, [workingColor, canvasColor]);

  return (
    <div
      className="shrink-0 overflow-hidden border-b border-border-default/60"
      style={{ maxHeight: expanded ? 120 : 0, transition: "max-height var(--dur-normal) var(--ease-out)" }}
    >
      <div className="flex h-[108px] min-w-0 overflow-x-auto" style={{ scrollbarWidth: "none" }}>
        {swatches.map((sw) => (
          <div
            key={sw.label}
            className="flex-1 min-w-[80px] flex flex-col items-center justify-center gap-1.5 px-1"
            style={{ backgroundColor: sw.bgCss }}
          >
            <span
              className="font-mono uppercase leading-none"
              style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: sw.labelColor }}
            >
              {sw.label}
            </span>
            <div
              className="w-[40%] aspect-square rounded-sm"
              style={{ backgroundColor: workingCss, boxShadow: "0 1px 3px rgba(0,0,0,0.2)" }}
            />
            <span
              className="font-mono leading-none whitespace-nowrap"
              style={{ fontSize: "var(--text-badge)", color: sw.levelColor }}
            >
              {sw.ratio.toFixed(1)}:1 {sw.level}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
