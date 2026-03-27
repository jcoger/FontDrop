import { useRef, useEffect, useCallback } from "react";
import { SIDEBAR_SLIDER } from "../components/MethodSidebar";
import {
  xToHue,
  hueToX,
  yToChroma,
  chromaToY,
  readoutLabel,
  paintPadBg,
} from "./tcLogic";

// Re-export generation function for use in index.tsx
export { generateTemperatureCorridor } from "./tcLogic";
export type { TempCorridorParams } from "../types";

// ── Sidebar: XY Pad + Width + Count ───────────────────────────────────

interface TCParamsProps {
  hCenter: number;
  onHCenterChange: (v: number) => void;
  chromaMin: number;
  onChromaChange: (min: number, max: number) => void;
  tempWidth: number;
  onTempWidthChange: (v: number) => void;
  count: number;
  onCountChange: (v: number) => void;
}

export function TCParams({
  hCenter,
  onHCenterChange,
  chromaMin,
  onChromaChange,
  tempWidth,
  onTempWidthChange,
  count,
  onCountChange,
}: TCParamsProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const padRef = useRef<HTMLDivElement>(null);
  const dragMode = useRef<"position" | "ring" | null>(null);
  const ringStartDist = useRef(0);
  const ringStartWidth = useRef(0);

  useEffect(() => {
    if (canvasRef.current) paintPadBg(canvasRef.current);
  }, []);

  const dotX = hueToX(hCenter);
  const dotY = chromaToY(chromaMin);
  const ringPct = 8 + ((tempWidth - 10) / 110) * 32;

  const getRelPos = useCallback((clientX: number, clientY: number): { x: number; y: number } => {
    const pad = padRef.current;
    if (!pad) return { x: 0.5, y: 0.5 };
    const rect = pad.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(1, (clientX - rect.left) / rect.width)),
      y: Math.max(0, Math.min(1, 1 - (clientY - rect.top) / rect.height)),
    };
  }, []);

  function applyPosition(x: number, y: number) {
    onHCenterChange(xToHue(x));
    const [cMin, cMax] = yToChroma(y);
    onChromaChange(cMin, cMax);
  }

  function distFromDot(clientX: number, clientY: number): number {
    const pad = padRef.current;
    if (!pad) return 0;
    const rect = pad.getBoundingClientRect();
    const pxX = dotX * rect.width;
    const pxY = (1 - dotY) * rect.height;
    const dx = clientX - rect.left - pxX;
    const dy = clientY - rect.top - pxY;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function onPointerDown(e: React.PointerEvent) {
    e.preventDefault();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    const pad = padRef.current;
    if (!pad) return;
    const rect = pad.getBoundingClientRect();
    const ringPx = (ringPct / 100) * rect.width;
    const dist = distFromDot(e.clientX, e.clientY);
    if (Math.abs(dist - ringPx) < 12) {
      dragMode.current = "ring";
      ringStartDist.current = dist;
      ringStartWidth.current = tempWidth;
    } else {
      dragMode.current = "position";
      const { x, y } = getRelPos(e.clientX, e.clientY);
      applyPosition(x, y);
    }
  }

  function onPointerMove(e: React.PointerEvent) {
    if (!dragMode.current) return;
    if (dragMode.current === "ring") {
      const dist = distFromDot(e.clientX, e.clientY);
      const delta = dist - ringStartDist.current;
      onTempWidthChange(Math.round(Math.max(10, Math.min(120, ringStartWidth.current + delta))));
    } else {
      const { x, y } = getRelPos(e.clientX, e.clientY);
      applyPosition(x, y);
    }
  }

  function onPointerUp() { dragMode.current = null; }

  const label = readoutLabel(hCenter, chromaMin);

  return (
    <>
      {/* XY Pad */}
      <div>
        <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
          Temperature × Saturation
        </div>

        <div className="relative" style={{ paddingBottom: "100%" }}>
          <div
            ref={padRef}
            className="absolute inset-0 rounded-lg overflow-hidden cursor-crosshair select-none"
            style={{ boxShadow: "inset 0 2px 8px rgba(0,0,0,0.5)" }}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            role="slider"
            aria-label="Temperature and saturation"
            aria-valuetext={label}
          >
            <canvas ref={canvasRef} className="absolute inset-0 w-full h-full" style={{ imageRendering: "auto" }} />

            {/* Width ring */}
            <div
              className="absolute rounded-full border border-white/30 pointer-events-none"
              style={{
                width: `${ringPct * 2}%`, height: `${ringPct * 2}%`,
                left: `${dotX * 100}%`, bottom: `${dotY * 100}%`,
                transform: "translate(-50%, 50%)",
                transition: dragMode.current === "ring" ? "none" : "width 100ms, height 100ms",
              }}
            />

            {/* Dot */}
            <div className="absolute pointer-events-none"
              style={{ left: `${dotX * 100}%`, bottom: `${dotY * 100}%`, transform: "translate(-50%, 50%)" }}>
              <div className="w-3.5 h-3.5 rounded-full bg-white border-2 border-black/40 shadow-[0_0_4px_rgba(0,0,0,0.6)]" />
            </div>

            {/* Axis labels */}
            <span className="absolute left-1.5 top-1/2 -translate-y-1/2 font-mono uppercase pointer-events-none"
              style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "rgba(255,255,255,0.45)" }}>Cool</span>
            <span className="absolute right-1.5 top-1/2 -translate-y-1/2 font-mono uppercase pointer-events-none"
              style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "rgba(255,255,255,0.45)" }}>Warm</span>
            <span className="absolute bottom-1 left-1/2 -translate-x-1/2 font-mono uppercase pointer-events-none"
              style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "rgba(255,255,255,0.45)" }}>Muted</span>
            <span className="absolute top-1 left-1/2 -translate-x-1/2 font-mono uppercase pointer-events-none"
              style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "rgba(255,255,255,0.45)" }}>Vivid</span>
          </div>
        </div>

        <div className="mt-2 text-center font-mono uppercase" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
          {label}
        </div>
      </div>

      {/* Width slider */}
      <div>
        <div className="flex justify-between items-end mb-1">
          <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>Width</span>
          <span className="font-mono bg-black/30 px-1.5 py-0.5 rounded" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>{tempWidth}°</span>
        </div>
        <input type="range" min={10} max={120} value={tempWidth}
          onChange={(e) => onTempWidthChange(+e.target.value)} className={SIDEBAR_SLIDER}
          aria-label="Corridor width" aria-valuetext={`${tempWidth} degrees`} />
      </div>

      {/* Count slider */}
      <div>
        <div className="flex justify-between items-end mb-1">
          <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>Count</span>
          <span className="font-mono bg-black/30 px-1.5 py-0.5 rounded" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>{count}</span>
        </div>
        <input type="range" min={6} max={24} value={count}
          onChange={(e) => onCountChange(+e.target.value)} className={SIDEBAR_SLIDER}
          aria-label="Color count" aria-valuetext={`${count} colors`} />
      </div>
    </>
  );
}

// ── Bottom bar controls ───────────────────────────────────────────────

const DUAL_INPUT =
  "absolute inset-0 w-full bg-transparent pointer-events-none " +
  "[&::-webkit-slider-thumb]:pointer-events-auto ";

interface TCBottomControlsProps {
  lRange: [number, number];
  onLRangeChange: (v: [number, number]) => void;
}

export function TCBottomControls({ lRange, onLRangeChange }: TCBottomControlsProps) {
  return (
    <div className="flex items-center gap-6 bg-black/40 px-5 py-2 rounded-full border border-neutral-800/80 shadow-inner">
      <div className="flex items-center gap-3 w-[240px]">
        <span className="font-mono w-16 shrink-0" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>LIGHTNESS</span>
        <div className="relative flex-1 h-2.5 flex items-center">
          <div className="absolute inset-x-0 h-[2px] bg-neutral-800 rounded-full" />
          <div className="absolute h-[2px] bg-neutral-500 rounded-full"
            style={{ left: `${lRange[0] * 100}%`, right: `${(1 - lRange[1]) * 100}%` }} />
          <input type="range" min={0} max={1} step={0.01} value={lRange[0]}
            onChange={(e) => onLRangeChange([Math.min(+e.target.value, lRange[1] - 0.05), lRange[1]])}
            className={DUAL_INPUT} aria-label="Lightness min" />
          <input type="range" min={0} max={1} step={0.01} value={lRange[1]}
            onChange={(e) => onLRangeChange([lRange[0], Math.max(+e.target.value, lRange[0] + 0.05)])}
            className={DUAL_INPUT} aria-label="Lightness max" />
        </div>
        <span className="font-mono w-14 text-right shrink-0" style={{ fontSize: "var(--text-label)", color: "var(--c-text)" }}>
          {Math.round(lRange[0] * 100)}–{Math.round(lRange[1] * 100)}
        </span>
      </div>
    </div>
  );
}
