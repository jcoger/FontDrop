import { useRef, useEffect, useMemo, useCallback, useState } from "react";
import {
  buildDots,
  paintScatter,
  PLOT_W,
  PLOT_H,
} from "./csLogic";
import type { ContrastRampColor, ScatterDot } from "./csLogic";
import type { OklchColor } from "../../../utils/oklch";
import type { Threshold, HueMode } from "../types";

interface ScatterPlotProps {
  results: ContrastRampColor[];
  primary: OklchColor;
  threshold: Threshold;
  hueMode: HueMode;
  onLRangeChange: (v: [number, number]) => void;
  onSetWorkingColor: (idx: number) => void;
}

export function ScatterPlot({
  results,
  primary,
  threshold,
  hueMode,
  onLRangeChange,
  onSetWorkingColor,
}: ScatterPlotProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const plotRef = useRef<HTMLDivElement>(null);
  const [tooltip, setTooltip] = useState<{ x: number; y: number; text: string } | null>(null);

  const dragMode = useRef<"select" | null>(null);
  const dragStart = useRef({ x: 0, y: 0 });
  const [selRect, setSelRect] = useState<{ x0: number; y0: number; x1: number; y1: number } | null>(null);

  // Hue axis range
  const hMin = hueMode === "full" ? 0 : ((primary.h - 60) % 360 + 360) % 360;
  const hMax = hueMode === "full" ? 360 : hMin + 120;

  const dots = useMemo(() => buildDots(results), [results]);

  useEffect(() => {
    if (canvasRef.current) paintScatter(canvasRef.current, dots, primary, threshold, hMin, hMax, selRect);
  }, [dots, primary, threshold, hMin, hMax, selRect]);

  const getRelPos = useCallback((clientX: number, clientY: number) => {
    const el = plotRef.current;
    if (!el) return { x: 0, y: 0 };
    const rect = el.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(1, (clientX - rect.left) / rect.width)),
      y: Math.max(0, Math.min(1, 1 - (clientY - rect.top) / rect.height)),
    };
  }, []);

  function onPlotPointerDown(e: React.PointerEvent) {
    e.preventDefault();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    const pos = getRelPos(e.clientX, e.clientY);
    dragMode.current = "select";
    dragStart.current = pos;
    setSelRect({ x0: pos.x, y0: pos.y, x1: pos.x, y1: pos.y });
  }

  function onPlotPointerMove(e: React.PointerEvent) {
    const pos = getRelPos(e.clientX, e.clientY);

    if (dragMode.current === "select") {
      setSelRect({ x0: dragStart.current.x, y0: dragStart.current.y, x1: pos.x, y1: pos.y });
      return;
    }

    // Hover tooltip — find nearest dot
    const hRange = hMax - hMin;
    let closest: ScatterDot | null = null;
    let closestDist = 12;
    const el = plotRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    for (const dot of dots) {
      const normH = ((dot.h - hMin) % 360 + 360) % 360;
      if (normH > hRange) continue;
      const dx = (normH / hRange) * rect.width - (e.clientX - rect.left);
      const dy = (1 - dot.l) * rect.height - (e.clientY - rect.top);
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d < closestDist) { closestDist = d; closest = dot; }
    }
    if (closest) {
      // Use relative position for tooltip to avoid scroll drift
      setTooltip({ x: e.clientX - plotRef.current!.getBoundingClientRect().left, y: e.clientY - plotRef.current!.getBoundingClientRect().top, text: `${closest.hex} · ${closest.ratio.toFixed(1)}:1 ${closest.badge.split(" ")[0]}` });
    } else {
      setTooltip(null);
    }
  }

  function onPlotPointerUp(e: React.PointerEvent) {
    if (dragMode.current === "select" && selRect) {
      const dx = Math.abs(selRect.x1 - selRect.x0);
      const dy = Math.abs(selRect.y1 - selRect.y0);

      if (dx < 0.02 && dy < 0.02) {
        // Tiny drag = click — find nearest dot
        const pos = getRelPos(e.clientX, e.clientY);
        const hRange = hMax - hMin;
        let bestIdx = -1, bestDist = Infinity;
        for (let i = 0; i < dots.length; i++) {
          const normH = ((dots[i].h - hMin) % 360 + 360) % 360;
          if (normH > hRange) continue;
          const ddx = normH / hRange - pos.x;
          const ddy = dots[i].l - pos.y;
          const d = ddx * ddx + ddy * ddy;
          if (d < bestDist) { bestDist = d; bestIdx = i; }
        }
        if (bestIdx >= 0) onSetWorkingColor(bestIdx);
        setSelRect(null);
      } else {
        // Apply selection as new L range
        const lMin = Math.min(selRect.y0, selRect.y1);
        const lMax = Math.max(selRect.y0, selRect.y1);
        onLRangeChange([Math.max(0, lMin), Math.min(1, lMax)]);
      }
    }
    dragMode.current = null;
  }

  return (
    <div>
      <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
        L × H Space
      </div>
      <div
        ref={plotRef}
        className="relative rounded-lg overflow-hidden cursor-crosshair select-none"
        style={{ width: "100%", aspectRatio: `${PLOT_W}/${PLOT_H}`, boxShadow: "inset 0 1px 4px rgba(0,0,0,0.4)" }}
        onPointerDown={onPlotPointerDown}
        onPointerMove={onPlotPointerMove}
        onPointerUp={onPlotPointerUp}
        onPointerLeave={() => setTooltip(null)}
        role="img"
        aria-label="Lightness vs Hue scatter plot"
      >
        <canvas ref={canvasRef} className="absolute inset-0 w-full h-full" />

        {tooltip && (
          <div className="absolute pointer-events-none font-mono bg-black/80 px-2 py-1 rounded shadow-lg whitespace-nowrap z-10"
            style={{ fontSize: "var(--text-badge)", color: "var(--c-text)", left: tooltip.x + 8, top: tooltip.y - 28 }}>
            {tooltip.text}
          </div>
        )}

        {/* Axis labels */}
        <span className="absolute left-1 bottom-1 font-mono uppercase pointer-events-none"
          style={{ fontSize: "var(--text-micro)", color: "rgba(255,255,255,0.3)" }}>
          {hueMode === "full" ? "0°" : `${Math.round(hMin)}°`}
        </span>
        <span className="absolute right-1 bottom-1 font-mono uppercase pointer-events-none"
          style={{ fontSize: "var(--text-micro)", color: "rgba(255,255,255,0.3)" }}>
          {hueMode === "full" ? "360°" : `${Math.round(hMax)}°`}
        </span>
        <span className="absolute left-1 top-1 font-mono pointer-events-none"
          style={{ fontSize: "var(--text-micro)", color: "rgba(255,255,255,0.3)" }}>L=1</span>
        <span className="absolute left-1 bottom-4 font-mono pointer-events-none"
          style={{ fontSize: "var(--text-micro)", color: "rgba(255,255,255,0.3)" }}>L=0</span>
      </div>

      <div className="mt-1 font-mono" style={{ fontSize: "var(--text-micro)", color: "var(--c-text-4)" }}>
        Drag to select L range · Click dot to preview
      </div>
    </div>
  );
}
