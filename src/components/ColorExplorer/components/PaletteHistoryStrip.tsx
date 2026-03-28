import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { springSnap } from "../../../lib/motion";
import { oklchToCss } from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type { MethodName } from "../types";

// ── Types ─────────────────────────────────────────────────────────────

export interface HistoryEntry {
  method: MethodName;
  colors: OklchColor[];
  timestamp: number;
  params?: Record<string, unknown>;
}

interface PaletteHistoryStripProps {
  /** Current palette colors (first 5) */
  currentColors: OklchColor[];
  currentMethod: MethodName;
  currentParams?: Record<string, unknown>;
  onRestore?: (entry: HistoryEntry) => void;
}

const SS_KEY_OPEN = "fontdrop-palette-history-open";
const SS_KEY_ENTRIES = "fontdrop-palette-history";
const MAX_ENTRIES = 6;

// ── Component ─────────────────────────────────────────────────────────

export function PaletteHistoryStrip({
  currentColors,
  currentMethod,
  currentParams,
  onRestore,
}: PaletteHistoryStripProps) {
  const [open, setOpen] = useState(() => sessionStorage.getItem(SS_KEY_OPEN) === "true");
  const [entries, setEntries] = useState<HistoryEntry[]>(() => {
    try { return JSON.parse(sessionStorage.getItem(SS_KEY_ENTRIES) || "[]"); }
    catch { return []; }
  });
  const [pulsingIdx, setPulsingIdx] = useState<number | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Persist open state
  useEffect(() => { sessionStorage.setItem(SS_KEY_OPEN, String(open)); }, [open]);

  // Debounced recording: add entry 800ms after last palette change
  const colorsKey = currentColors.map((c) => `${c.l.toFixed(2)}-${c.h.toFixed(0)}`).join("|");
  useEffect(() => {
    if (currentColors.length === 0) return;
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setEntries((prev) => {
        // Don't add duplicate if colors match the most recent entry
        if (prev.length > 0) {
          const lastKey = prev[0].colors.map((c) => `${c.l.toFixed(2)}-${c.h.toFixed(0)}`).join("|");
          if (lastKey === colorsKey) return prev;
        }
        const entry: HistoryEntry = { method: currentMethod, colors: currentColors.slice(0, 5), timestamp: Date.now(), params: currentParams };
        const next = [entry, ...prev].slice(0, MAX_ENTRIES);
        sessionStorage.setItem(SS_KEY_ENTRIES, JSON.stringify(next));
        // Pulse newest entry
        setPulsingIdx(0);
        setTimeout(() => setPulsingIdx(null), 200);
        return next;
      });
    }, 800);
    return () => { if (debounceRef.current) clearTimeout(debounceRef.current); };
  }, [colorsKey, currentMethod, currentColors]);

  if (entries.length === 0 && !open) return null;

  return (
    <div className="shrink-0">
      {/* Toggle bar */}
      <div className="flex items-center justify-end px-4 h-6 border-t border-border-default bg-surface-2">
        <button
          className="flex items-center gap-1 font-mono uppercase cursor-pointer"
          style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "var(--c-text-4)", transition: "color var(--dur-fast) var(--ease-hover)" }}
          onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text-2)"; }}
          onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text-4)"; }}
          onClick={() => setOpen((p) => !p)}
          aria-label={open ? "Collapse palette history" : "Expand palette history"}
        >
          {/* Clock icon */}
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" />
          </svg>
          History
          <svg width="8" height="5" viewBox="0 0 8 5" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"
            style={{ transform: open ? "rotate(180deg)" : "rotate(0deg)", transition: "transform var(--dur-fast) var(--ease-hover)" }}>
            <path d="M1 1L4 4L7 1" />
          </svg>
        </button>
      </div>

      {/* Expandable strip */}
      <AnimatePresence>
        {open && entries.length > 0 && (
          <motion.div
            className="border-t border-border-default bg-surface-2 overflow-hidden"
            initial={{ height: 0 }}
            animate={{ height: 48 }}
            exit={{ height: 0 }}
            transition={springSnap}
          >
            <div className="flex items-center h-12 px-4 gap-3">
              {entries.map((entry, i) => (
                <motion.div
                  key={entry.timestamp}
                  className="flex flex-col items-center gap-1 cursor-pointer shrink-0 rounded px-1 transition-colors hover:bg-white/5"
                  style={{
                    transform: pulsingIdx === i ? "scale(1.1)" : "scale(1)",
                    transition: "transform var(--dur-normal) var(--ease-hover)",
                  }}
                  title={`${entry.method} — click to restore`}
                  onClick={() => onRestore?.(entry)}
                >
                  {/* Color dots */}
                  <div className="flex gap-0.5">
                    {entry.colors.map((c, ci) => (
                      <div key={ci} className="w-2 h-2 rounded-full" style={{ backgroundColor: oklchToCss(c) }} />
                    ))}
                  </div>
                  {/* Method label */}
                  <span className="font-mono uppercase truncate max-w-[60px]"
                    style={{ fontSize: 6, letterSpacing: "var(--track-caps)", color: "var(--c-text-4)" }}>
                    {entry.method}
                  </span>
                </motion.div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
