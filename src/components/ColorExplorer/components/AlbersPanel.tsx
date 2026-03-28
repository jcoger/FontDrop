import { useState, useMemo, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { springSnap } from "../../../lib/motion";
import type { OklchColor } from "../../../utils/oklch";
import {
  oklchToCss,
  contrastRatio,
  contrastLevel,
  safeColor,
} from "../../../utils/oklch";

// ── Swatch definitions (same 8 as original AlbersRow) ─────────────────

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
  AAA: "#4ade80",
  AA: "#facc15",
  "AA-large": "#fb923c",
  FAIL: "rgba(239, 68, 68, 0.45)",
};

// ── Component ─────────────────────────────────────────────────────────

interface AlbersPanelProps {
  open: boolean;
  onClose: () => void;
  workingColor: OklchColor;
  canvasColor: OklchColor;
}

export function AlbersPanel({ open, onClose, workingColor, canvasColor }: AlbersPanelProps) {
  const [tab, setTab] = useState<"context" | "scatter">("context");
  const panelRef = useRef<HTMLDivElement>(null);

  // Escape key closes
  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  // Click outside closes
  useEffect(() => {
    if (!open) return;
    function onClick(e: MouseEvent) {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        onClose();
      }
    }
    // Delay to avoid catching the toggle click itself
    const t = setTimeout(() => window.addEventListener("mousedown", onClick), 0);
    return () => { clearTimeout(t); window.removeEventListener("mousedown", onClick); };
  }, [open, onClose]);

  // Compute swatches
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
        labelColor: ctx.l > 0.5 ? "rgba(0,0,0,0.55)" : "rgba(255,255,255,0.55)",
      };
    });
  }, [workingColor, canvasColor]);

  // Force re-render for stagger animation when working color changes
  const [, setStaggerTick] = useState(0);
  useEffect(() => { setStaggerTick((k) => k + 1); }, [workingColor]);

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          ref={panelRef}
          className="absolute top-0 right-0 bottom-0 w-[280px] bg-[#141414] border-l border-neutral-800 z-30 flex flex-col overflow-hidden"
          initial={{ x: 280 }}
          animate={{ x: 0 }}
          exit={{ x: 280 }}
          transition={springSnap}
        >
          {/* Header */}
          <div className="flex items-center justify-between px-4 h-10 border-b border-neutral-800 shrink-0">
            <span
              className="font-mono uppercase"
              style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}
            >
              Albers Context
            </span>
            <button
              className="font-mono cursor-pointer"
              style={{ fontSize: "var(--text-ui)", color: "var(--c-text-3)", transition: "color var(--dur-fast) var(--ease-hover)" }}
              onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text)"; }}
              onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text-3)"; }}
              onClick={onClose}
              aria-label="Close Albers panel"
            >
              ×
            </button>
          </div>

          {/* Tab pills */}
          <div className="flex items-center gap-1 px-4 py-2 shrink-0">
            {(["context", "scatter"] as const).map((t) => (
              <button
                key={t}
                className="flex-1 px-2 py-1 rounded-md font-medium capitalize cursor-pointer transition-colors"
                style={{
                  fontSize: "var(--text-body)",
                  backgroundColor: tab === t ? "#404040" : "transparent",
                  color: tab === t ? "var(--c-text)" : "var(--c-text-2)",
                }}
                onClick={() => setTab(t)}
              >
                {t === "context" ? "Context" : "Scatter"}
              </button>
            ))}
          </div>

          {/* Tab content */}
          <div className="flex-1 overflow-y-auto px-4 pb-4">
            {tab === "context" ? (
              <div className="grid grid-cols-2 gap-2">
                {swatches.map((sw, i) => (
                  <motion.div
                    key={sw.label}
                    className="flex flex-col rounded-lg overflow-hidden"
                    initial={{ opacity: 0.5 }}
                    animate={{ opacity: 1 }}
                    transition={{ delay: i * 0.03, duration: 0.15 }}
                  >
                    {/* Label */}
                    <span
                      className="font-mono uppercase px-2 pt-1.5 pb-1"
                      style={{
                        fontSize: "var(--text-micro)",
                        letterSpacing: "var(--track-caps)",
                        color: "var(--c-text-4)",
                      }}
                    >
                      {sw.label}
                    </span>

                    {/* Swatch cell */}
                    <div
                      className="aspect-square flex items-center justify-center"
                      style={{ backgroundColor: sw.bgCss }}
                    >
                      <div
                        className="rounded-sm"
                        style={{
                          width: "35%",
                          height: "35%",
                          backgroundColor: workingCss,
                          boxShadow: "0 1px 3px rgba(0,0,0,0.2)",
                        }}
                      />
                    </div>

                    {/* Badge */}
                    <div
                      className="font-mono px-2 py-1.5"
                      style={{ fontSize: "var(--text-badge)", color: sw.levelColor }}
                    >
                      {sw.ratio.toFixed(1)}:1 {sw.level}
                    </div>
                  </motion.div>
                ))}
              </div>
            ) : (
              /* Scatter tab — placeholder */
              <div
                className="flex items-center justify-center rounded-lg"
                style={{
                  aspectRatio: "190/140",
                  backgroundColor: "#1a1a1a",
                  boxShadow: "inset 0 1px 4px rgba(0,0,0,0.4)",
                }}
              >
                <span
                  className="font-mono text-center"
                  style={{ fontSize: "var(--text-label)", color: "var(--c-text-4)" }}
                >
                  L × H Scatter
                  <br />
                  Select a working color
                </span>
              </div>
            )}
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
