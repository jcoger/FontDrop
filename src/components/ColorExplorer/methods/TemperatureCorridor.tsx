import { useRef, useEffect, useCallback, useMemo, useState } from "react";
import { SIDEBAR_SLIDER } from "../components/MethodSidebar";
import { oklchToCss, maxChroma as getMaxChroma } from "../../../utils/oklch";
import {
  xToHue,
  hueToX,
  chromaCeilingToY,
  paintPadBg,
} from "./tcLogic";

export { generateTemperatureCorridor, generateDualCorridor } from "./tcLogic";
export type { DualCorridorParams } from "./tcLogic";
export type { TempCorridorParams } from "../types";

// ── Hue family name from degree ──────────────────────────────────────

function hueFamily(h: number): string {
  const n = ((h % 360) + 360) % 360;
  if (n < 15 || n >= 345) return "reds";
  if (n < 45) return "oranges";
  if (n < 75) return "yellows";
  if (n < 150) return "greens";
  if (n < 195) return "teals";
  if (n < 255) return "blues";
  if (n < 315) return "purples";
  return "pinks";
}

function chromaZone(ceiling: number): string {
  return ceiling > 0.67 ? "vivid" : ceiling < 0.33 ? "muted" : "moderate";
}

function tempZone(hCenter: number): string {
  const hx = hueToX(hCenter);
  return hx > 0.7 ? "warm" : hx < 0.3 ? "cool" : "neutral";
}

function spreadWord(w: number): string {
  return w < 35 ? "narrow spread" : w > 70 ? "wide spread" : "spread across " + w + "°";
}

// ── Slider helpers — two tiers ───────────────────────────────────────

/** TIER 1 — RANGE: dimmed label, thin track, plain value text */
function RangeSlider({ label, value, children }: { label: string; value: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="flex justify-between items-end mb-1">
        <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-4)" }}>{label}</span>
        <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>{value}</span>
      </div>
      <div style={{ height: 2 }}>{children}</div>
    </div>
  );
}

/** TIER 2 — STYLE: full opacity label, normal track, badge value */
function StyleSlider({ label, value, children }: { label: string; value: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="flex justify-between items-end mb-1">
        <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>{label}</span>
        <span className="font-mono bg-black/30 px-1.5 py-0.5 rounded" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>{value}</span>
      </div>
      {children}
    </div>
  );
}

// ── Sidebar Props ────────────────────────────────────────────────────

interface TCParamsProps {
  hCenter: number;
  onHCenterChange: (v: number) => void;
  chromaFloor: number;
  onChromaFloorChange: (v: number) => void;
  chromaCeiling: number;
  onChromaCeilingChange: (v: number) => void;
  tempWidth: number;
  onTempWidthChange: (v: number) => void;
  hueWidth: number;
  onHueWidthChange: (v: number) => void;
  chromaCeiling2: number;
  onChromaCeiling2Change: (v: number) => void;
  tempWidth2: number;
  onTempWidth2Change: (v: number) => void;
  hueOffset: number;
  onHueOffsetChange: (v: number) => void;
  accentChromaOffset: number;
  onAccentChromaOffsetChange: (v: number) => void;
  count: number;
  onCountChange: (v: number) => void;
  variety: import("../types").ColorVariety;
  onVarietyChange: (v: import("../types").ColorVariety) => void;
  activeFontCount: number;
  lRange: [number, number];
  onLRangeChange: (v: [number, number]) => void;
  lMidBias: number;
  onLMidBiasChange: (v: number) => void;
  accentWeight: number;
  onAccentWeightChange: (v: number) => void;
}

export function TCParams({
  hCenter, onHCenterChange, chromaFloor, onChromaFloorChange, chromaCeiling, onChromaCeilingChange,
  tempWidth, onTempWidthChange, hueWidth, onHueWidthChange,
  chromaCeiling2, onChromaCeiling2Change, tempWidth2, onTempWidth2Change,
  hueOffset, onHueOffsetChange, accentChromaOffset, onAccentChromaOffsetChange,
  count, variety, onVarietyChange, activeFontCount,
  lRange, onLRangeChange, lMidBias, onLMidBiasChange,
  accentWeight, onAccentWeightChange,
}: TCParamsProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const padRef = useRef<HTMLDivElement>(null);
  const focusedNode = useRef<1 | 2>(1);
  const dragState = useRef<{ node: 1 | 2; mode: "position" | "ring"; startDist: number; startWidth: number } | null>(null);

  useEffect(() => {
    const el = canvasRef.current;
    if (!el) return;
    requestAnimationFrame(() => paintPadBg(el));
  }, []);

  const dot1X = hueToX(hCenter);
  const dot1Y = chromaCeilingToY(chromaCeiling);
  const ring1Pct = 8 + ((tempWidth - 10) / 110) * 32;
  const ring1Color = oklchToCss({ mode: "oklch", l: 0.75, c: 0.2, h: hCenter });

  const hCenter2 = ((hCenter + hueOffset) % 360 + 360) % 360;
  const dot2X = hueToX(hCenter2);
  const dot2Y = chromaCeilingToY(chromaCeiling2);
  const ring2Pct = 8 + ((tempWidth2 - 10) / 110) * 32;

  // Chroma floor overlay opacity
  const floorOverlayOpacity = chromaFloor * 0.6;

  const getRelPos = useCallback((clientX: number, clientY: number) => {
    const pad = padRef.current;
    if (!pad) return { x: 0.5, y: 0.5 };
    const rect = pad.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(1, (clientX - rect.left) / rect.width)),
      y: Math.max(0, Math.min(1, 1 - (clientY - rect.top) / rect.height)),
    };
  }, []);

  function distFromNode(clientX: number, clientY: number, nx: number, ny: number): number {
    const pad = padRef.current;
    if (!pad) return Infinity;
    const rect = pad.getBoundingClientRect();
    const dx = clientX - rect.left - nx * rect.width;
    const dy = clientY - rect.top - (1 - ny) * rect.height;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function onPointerDown(e: React.PointerEvent) {
    e.preventDefault();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    const pad = padRef.current;
    if (!pad) return;
    const rect = pad.getBoundingClientRect();
    const d1 = distFromNode(e.clientX, e.clientY, dot1X, dot1Y);
    const d2 = distFromNode(e.clientX, e.clientY, dot2X, dot2Y);
    const node: 1 | 2 = d2 < d1 ? 2 : 1;
    focusedNode.current = node;
    const nx = node === 1 ? dot1X : dot2X;
    const ny = node === 1 ? dot1Y : dot2Y;
    const ringPct = node === 1 ? ring1Pct : ring2Pct;
    const width = node === 1 ? tempWidth : tempWidth2;
    const dist = distFromNode(e.clientX, e.clientY, nx, ny);
    const ringPx = (ringPct / 100) * rect.width;
    if (Math.abs(dist - ringPx) < 12) {
      dragState.current = { node, mode: "ring", startDist: dist, startWidth: width };
    } else {
      dragState.current = { node, mode: "position", startDist: 0, startWidth: 0 };
      const { x, y } = getRelPos(e.clientX, e.clientY);
      if (node === 1) { onHCenterChange(xToHue(x)); onChromaCeilingChange(Math.max(0, Math.min(1, y))); }
      else { onChromaCeiling2Change(Math.max(0, Math.min(1, y))); }
    }
  }

  function onPointerMove(e: React.PointerEvent) {
    const ds = dragState.current;
    if (!ds) return;
    if (ds.mode === "ring") {
      const nx = ds.node === 1 ? dot1X : dot2X;
      const ny = ds.node === 1 ? dot1Y : dot2Y;
      const dist = distFromNode(e.clientX, e.clientY, nx, ny);
      const newW = Math.round(Math.max(10, Math.min(120, ds.startWidth + (dist - ds.startDist))));
      if (ds.node === 1) onTempWidthChange(newW); else onTempWidth2Change(newW);
    } else {
      const { x, y } = getRelPos(e.clientX, e.clientY);
      if (ds.node === 1) { onHCenterChange(xToHue(x)); onChromaCeilingChange(Math.max(0, Math.min(1, y))); }
      else { onChromaCeiling2Change(Math.max(0, Math.min(1, y))); }
    }
  }

  function onPointerUp() { dragState.current = null; }

  const n2Count = Math.max(1, Math.round(count * accentWeight));
  const n1Count = Math.max(1, count - n2Count);

  // ── Plain-English readout (debounced 200ms) ────────────────────────
  const [readout, setReadout] = useState("");
  const readoutTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (readoutTimer.current) clearTimeout(readoutTimer.current);
    readoutTimer.current = setTimeout(() => {
      const pChroma = chromaZone(chromaCeiling);
      const pTemp = tempZone(hCenter);
      const pFamily = hueFamily(hCenter);
      const aChroma = chromaZone(chromaCeiling2);
      const aTemp = tempZone(hCenter2);
      const sp = spreadWord(hueWidth);
      setReadout(`${pChroma} ${pTemp} ${pFamily} with a ${aChroma} ${aTemp} accent, ${sp}`);
    }, 200);
    return () => { if (readoutTimer.current) clearTimeout(readoutTimer.current); };
  }, [hCenter, hCenter2, chromaCeiling, chromaCeiling2, hueWidth]);

  // ── Hue strip preview ──────────────────────────────────────────────
  const stripColors = useMemo(() => {
    const colors: string[] = [];
    const steps = 30;
    const hMin1 = hCenter - hueWidth / 2;
    const cMid1 = (chromaFloor + chromaCeiling) / 2;
    for (let i = 0; i < steps; i++) {
      const h = ((hMin1 + (i / (steps - 1)) * hueWidth) % 360 + 360) % 360;
      const mc = getMaxChroma(0.65, h);
      colors.push(oklchToCss({ mode: "oklch", l: 0.65, c: Math.min(cMid1 * mc, mc), h }));
    }
    const hMin2 = hCenter2 - hueWidth / 2;
    const accentCeil = Math.max(0, Math.min(1, chromaCeiling2 + accentChromaOffset / 100));
    const cMid2 = (chromaFloor + accentCeil) / 2;
    for (let i = 0; i < steps; i++) {
      const h = ((hMin2 + (i / (steps - 1)) * hueWidth) % 360 + 360) % 360;
      const mc = getMaxChroma(0.65, h);
      colors.push(oklchToCss({ mode: "oklch", l: 0.65, c: Math.min(cMid2 * mc, mc), h }));
    }
    return colors;
  }, [hCenter, hCenter2, hueWidth, chromaFloor, chromaCeiling, chromaCeiling2, accentChromaOffset]);

  const showGap = hueOffset > 30;

  return (
    <>
      {/* ── STICKY: XY Pad + Strip ────────────────────────── */}
      <div className="sticky -top-4 -mx-1 px-1 pt-4 pb-3 z-10 bg-surface-1">
        <div className="relative" style={{ paddingBottom: "100%" }}>
          <div ref={padRef}
            className="absolute inset-0 rounded-lg overflow-hidden cursor-crosshair select-none"
            style={{ boxShadow: "inset 0 2px 8px rgba(0,0,0,0.5)" }}
            onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp}
            role="slider" aria-label="Hue and chroma">

            {/* Static background */}
            <canvas ref={canvasRef} className="absolute inset-0 w-full h-full" style={{ imageRendering: "auto" }} />

            {/* Reactive overlay: brightens when chroma floor is high */}
            <div className="absolute inset-0 pointer-events-none"
              style={{
                background: "linear-gradient(to top, transparent 0%, rgba(255,255,255,0.08) 50%, rgba(255,200,100,0.12) 100%)",
                opacity: floorOverlayOpacity,
                transition: "opacity 80ms ease",
                mixBlendMode: "screen",
              }} />

            {/* Dashed line between nodes */}
            <svg className="absolute inset-0 w-full h-full pointer-events-none" viewBox="0 0 100 100" preserveAspectRatio="none">
              <line x1={dot1X * 100} y1={(1 - dot1Y) * 100} x2={dot2X * 100} y2={(1 - dot2Y) * 100}
                stroke="rgba(255,255,255,0.15)" strokeWidth="0.5" strokeDasharray="2 2" />
            </svg>

            {/* Node 1 ring — hue-tinted */}
            <div className="absolute rounded-full pointer-events-none"
              style={{ width: `${ring1Pct * 2}%`, height: `${ring1Pct * 2}%`, left: `${dot1X * 100}%`, bottom: `${dot1Y * 100}%`, transform: "translate(-50%, 50%)",
                border: `1.5px solid ${ring1Color}`, opacity: 0.6 }} />
            <div className="absolute pointer-events-none" style={{ left: `${dot1X * 100}%`, bottom: `${dot1Y * 100}%`, transform: "translate(-50%, 50%)" }}>
              <div className="w-3.5 h-3.5 rounded-full bg-white border-2 border-black/40 shadow-[0_0_4px_rgba(0,0,0,0.6)]"
                style={{ outline: focusedNode.current === 1 ? `2px solid ${ring1Color}` : "none", outlineOffset: 2 }} />
            </div>

            {/* Node 2 ring + dot */}
            <div className="absolute rounded-full pointer-events-none"
              style={{ width: `${ring2Pct * 2}%`, height: `${ring2Pct * 2}%`, left: `${dot2X * 100}%`, bottom: `${dot2Y * 100}%`, transform: "translate(-50%, 50%)",
                border: "1px dashed rgba(255,255,255,0.25)" }} />
            <div className="absolute pointer-events-none" style={{ left: `${dot2X * 100}%`, bottom: `${dot2Y * 100}%`, transform: "translate(-50%, 50%)" }}>
              <div className="w-3 h-3 rounded-full border-2 border-dashed border-white/70 shadow-[0_0_4px_rgba(0,0,0,0.6)]"
                style={{ backgroundColor: "rgba(255,255,255,0.5)", outline: focusedNode.current === 2 ? "2px solid rgba(255,255,255,0.3)" : "none", outlineOffset: 2 }} />
            </div>

            {/* Axis labels */}
            <span className="absolute left-1.5 top-1/2 -translate-y-1/2 font-mono uppercase pointer-events-none" style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "rgba(255,255,255,0.45)" }}>Cool</span>
            <span className="absolute right-1.5 top-1/2 -translate-y-1/2 font-mono uppercase pointer-events-none" style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "rgba(255,255,255,0.45)" }}>Warm</span>
            <span className="absolute bottom-1 left-1/2 -translate-x-1/2 font-mono uppercase pointer-events-none" style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "rgba(255,255,255,0.45)" }}>Muted</span>
            <span className="absolute top-1 left-1/2 -translate-x-1/2 font-mono uppercase pointer-events-none" style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "rgba(255,255,255,0.45)" }}>Vivid</span>
          </div>
        </div>

        {/* Hue strip preview */}
        <div className="flex rounded-[5px] overflow-hidden mt-2" style={{ height: 10, gap: showGap ? 4 : 0 }}>
          <div className="flex-1 flex">
            {stripColors.slice(0, 30).map((c, i) => (
              <div key={i} className="flex-1" style={{ backgroundColor: c }} />
            ))}
          </div>
          <div className="flex-1 flex">
            {stripColors.slice(30).map((c, i) => (
              <div key={i} className="flex-1" style={{ backgroundColor: c }} />
            ))}
          </div>
        </div>
      </div>

      {/* ── Plain-English readout ─────────────────────────── */}
      {readout && (
        <div style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)", opacity: 0.6, lineHeight: 1.4 }}>
          {readout}
        </div>
      )}

      {/* ── TIER 1: RANGE CONTROLS ────────────────────────── */}
      <RangeSlider label="Hue Spread" value={`${hueWidth}°`}>
        <input type="range" min={20} max={120} value={hueWidth}
          onChange={(e) => onHueWidthChange(+e.target.value)} className={SIDEBAR_SLIDER}
          aria-label="Hue spread" />
      </RangeSlider>

      <RangeSlider label="Color Minimum" value={`${Math.round(chromaFloor * 100)}%`}>
        <input type="range" min={0} max={0.95} step={0.01} value={chromaFloor}
          onChange={(e) => onChromaFloorChange(Math.min(+e.target.value, chromaCeiling - 0.05))} className={SIDEBAR_SLIDER}
          aria-label="Color minimum" />
      </RangeSlider>

      <RangeSlider label="Brightness Range" value={`${Math.round(lRange[0] * 100)}–${Math.round(lRange[1] * 100)}`}>
        <div className="relative h-3 flex items-center">
          <div className="absolute inset-x-0 h-[2px] bg-surface-4 rounded-full" />
          <div className="absolute h-[2px] bg-surface-active/50 rounded-full"
            style={{ left: `${lRange[0] * 100}%`, right: `${(1 - lRange[1]) * 100}%` }} />
          <input type="range" min={0.1} max={1} step={0.01} value={lRange[0]}
            onChange={(e) => onLRangeChange([Math.min(+e.target.value, lRange[1] - 0.05), lRange[1]])}
            className="absolute inset-0 w-full bg-transparent pointer-events-none [&::-webkit-slider-thumb]:pointer-events-auto"
            aria-label="Brightness min" />
          <input type="range" min={0.1} max={1} step={0.01} value={lRange[1]}
            onChange={(e) => onLRangeChange([lRange[0], Math.max(+e.target.value, lRange[0] + 0.05)])}
            className="absolute inset-0 w-full bg-transparent pointer-events-none [&::-webkit-slider-thumb]:pointer-events-auto"
            aria-label="Brightness max" />
        </div>
      </RangeSlider>

      {/* ── TIER 2: STYLE CONTROLS ────────────────────────── */}
      <StyleSlider label="Brightness Push" value={lMidBias < 0.45 ? "Dark" : lMidBias > 0.55 ? "Light" : "Even"}>
        <input type="range" min={0.15} max={0.85} step={0.01} value={lMidBias}
          onChange={(e) => onLMidBiasChange(+e.target.value)} className={SIDEBAR_SLIDER}
          aria-label="Brightness push" />
      </StyleSlider>

      <StyleSlider label="Accent Hue" value={`${hueOffset}°`}>
        <input type="range" min={0} max={360} value={hueOffset}
          onChange={(e) => onHueOffsetChange(+e.target.value)} className={SIDEBAR_SLIDER}
          aria-label="Accent hue" />
      </StyleSlider>

      <StyleSlider label="Accent Intensity" value={`${accentChromaOffset > 0 ? "+" : ""}${accentChromaOffset}%`}>
        <input type="range" min={-50} max={50} value={accentChromaOffset}
          onChange={(e) => onAccentChromaOffsetChange(+e.target.value)} className={SIDEBAR_SLIDER}
          aria-label="Accent intensity" />
      </StyleSlider>

      <StyleSlider label="Primary / Accent" value={`${n1Count}:${n2Count}`}>
        <input type="range" min={0.1} max={0.9} step={0.05} value={accentWeight}
          onChange={(e) => onAccentWeightChange(+e.target.value)} className={SIDEBAR_SLIDER}
          aria-label="Primary accent ratio" />
      </StyleSlider>

      {/* ── COLOR VARIETY ──────────────────────────────────── */}
      <div>
        <div className="flex justify-between items-end mb-2">
          <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>Color Variety</span>
          <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
            {variety === "tight" ? `Tight · ${Math.max(4, Math.ceil(activeFontCount / 2))}` : variety === "wide" ? `Wide · ${Math.min(24, activeFontCount * 2)}` : `Auto · ${activeFontCount}`}
          </span>
        </div>
        <div className="flex rounded-md overflow-hidden border border-border-strong">
          {(["tight", "auto", "wide"] as const).map((v) => {
            const active = variety === v;
            return (
              <button key={v} className="flex-1 px-2 py-1 font-mono uppercase cursor-pointer transition-colors"
                style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", backgroundColor: active ? "var(--surface-active)" : "transparent", color: active ? "var(--c-text)" : "var(--c-text-3)" }}
                onClick={() => onVarietyChange(v)}>{v}</button>
            );
          })}
        </div>
      </div>
    </>
  );
}

// ── Bottom bar readout ───────────────────────────────────────────────

interface TCBottomControlsProps {
  lRange: [number, number];
  accentWeight: number;
  count: number;
  hueOffset: number;
}

export function TCBottomControls({ lRange, accentWeight, count, hueOffset }: TCBottomControlsProps) {
  const n2 = Math.max(1, Math.round(count * accentWeight));
  const n1 = Math.max(1, count - n2);
  return (
    <div className="flex items-center gap-4 bg-black/40 px-5 py-2 rounded-full border border-border-default shadow-inner">
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        L {Math.round(lRange[0] * 100)}–{Math.round(lRange[1] * 100)}
      </span>
      <div className="w-px h-3.5 bg-surface-4/80" />
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        Δ{hueOffset}°
      </span>
      <div className="w-px h-3.5 bg-surface-4/80" />
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {n1}:{n2}
      </span>
    </div>
  );
}
