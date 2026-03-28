import { useRef, useCallback, useEffect, useState } from "react";
import { SIDEBAR_SLIDER } from "../components/MethodSidebar";
import { oklchToCss } from "../../../utils/oklch";
import {
  energyDescriptor,
  glowForKnob,
  hueFamily,
  mkReadout,
  REL_MODES,
  computeWaveform,
} from "./mkLogic";
import type { RelModeId } from "./mkLogic";
import type { ContrastLevel } from "../types";

export { generateMacroKnob, flipCard, findPassingFg, getNeutralMeta, computeWaveform } from "./mkLogic";
export type { MKRampColor, RelModeId, VariMode } from "./mkLogic";

// ── Props ────────────────────────────────────────────────────────────

interface MKParamsProps {
  knob: number;
  onKnobChange: (v: number) => void;
  hue: number;
  onHueChange: (v: number) => void;
  spread: number;
  onSpreadChange: (v: number) => void;
  variMode: import("./mkLogic").VariMode;
  onVariModeChange: (v: import("./mkLogic").VariMode) => void;
  activeFontCount: number;
  relMode: RelModeId;
  onRelModeChange: (v: RelModeId) => void;
  contrastLevel: ContrastLevel;
}

// ── Knob constants ───────────────────────────────────────────────────

const KNOB_SIZE = 160;
const KNOB_R = KNOB_SIZE / 2;
const TRACK_R = KNOB_R - 12;
const INDICATOR_R = KNOB_R - 8;

// ── Section label ────────────────────────────────────────────────────

function SectionLabel({ children }: { children: string }) {
  return (
    <span
      className="font-mono uppercase"
      style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}
    >
      {children}
    </span>
  );
}

// ── Component ────────────────────────────────────────────────────────

export function MKParams({
  knob, onKnobChange,
  hue, onHueChange,
  spread, onSpreadChange,
  variMode, onVariModeChange,
  activeFontCount,
  relMode, onRelModeChange,
  contrastLevel,
}: MKParamsProps) {
  const dragging = useRef(false);
  const dragStart = useRef({ y: 0, startVal: 0 });
  const [displayKnob, setDisplayKnob] = useState(knob);

  useEffect(() => { setDisplayKnob(knob); }, [knob]);

  const isClash = contrastLevel === "clash";

  // ── Knob drag — wrapping, not clamping (Fix 5) ────────────
  const onPointerDown = useCallback((e: React.PointerEvent) => {
    dragging.current = true;
    dragStart.current = { y: e.clientY, startVal: knob };
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  }, [knob]);

  const onPointerMove = useCallback((e: React.PointerEvent) => {
    if (!dragging.current) return;
    const dy = dragStart.current.y - e.clientY;
    const raw = dragStart.current.startVal + dy * 1.2;
    const wrapped = ((raw % 360) + 360) % 360;
    onKnobChange(Math.round(wrapped));
    setDisplayKnob(wrapped);
  }, [onKnobChange]);

  const onPointerUp = useCallback(() => { dragging.current = false; }, []);

  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault();
    const raw = knob + (e.deltaY > 0 ? -3 : 3);
    const wrapped = ((raw % 360) + 360) % 360;
    onKnobChange(wrapped);
    setDisplayKnob(wrapped);
  }, [knob, onKnobChange]);

  // ── Hue strip drag ─────────────────────────────────────────
  const hueBarRef = useRef<HTMLDivElement>(null);
  const hueDragging = useRef(false);

  const updateHueFromPointer = useCallback((clientX: number) => {
    const bar = hueBarRef.current;
    if (!bar) return;
    const rect = bar.getBoundingClientRect();
    const t = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    onHueChange(Math.round(t * 360));
  }, [onHueChange]);

  const onHuePointerDown = useCallback((e: React.PointerEvent) => {
    hueDragging.current = true;
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    updateHueFromPointer(e.clientX);
  }, [updateHueFromPointer]);

  const onHuePointerMove = useCallback((e: React.PointerEvent) => {
    if (!hueDragging.current) return;
    updateHueFromPointer(e.clientX);
  }, [updateHueFromPointer]);

  const onHuePointerUp = useCallback(() => { hueDragging.current = false; }, []);

  // ── Visual ─────────────────────────────────────────────────
  const angle = (displayKnob / 360) * 360 - 135;
  const indicatorAngle = ((angle - 90) * Math.PI) / 180;
  const ix = KNOB_R + Math.cos(indicatorAngle) * INDICATOR_R;
  const iy = KNOB_R + Math.sin(indicatorAngle) * INDICATOR_R;

  const glowColor = oklchToCss(glowForKnob(displayKnob, hue));
  const descriptor = energyDescriptor(displayKnob);
  const readout = mkReadout(displayKnob, relMode, hue);
  const hueThumbColor = oklchToCss({ mode: "oklch", l: 0.65, c: 0.25, h: hue });
  const activeRelMode = REL_MODES.find((m) => m.id === relMode)!;

  return (
    <div className="flex flex-col gap-5 items-center">
      {/* ── ENERGY ───────────────────────────────────────── */}
      <div className="w-full"><SectionLabel>Energy</SectionLabel></div>

      {/* Dial */}
      <div
        className="relative cursor-ns-resize select-none"
        style={{ width: KNOB_SIZE, height: KNOB_SIZE }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onWheel={onWheel}
      >
        <div className="absolute inset-0 rounded-full" style={{ boxShadow: `0 0 24px 6px ${glowColor}40, 0 0 48px 12px ${glowColor}20`, transition: "box-shadow 200ms ease" }} />
        <svg width={KNOB_SIZE} height={KNOB_SIZE} className="absolute inset-0">
          <circle cx={KNOB_R} cy={KNOB_R} r={TRACK_R} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth={3} />
          <circle cx={KNOB_R} cy={KNOB_R} r={TRACK_R} fill="none" stroke={glowColor} strokeWidth={3} strokeLinecap="round"
            strokeDasharray={`${(displayKnob / 360) * 2 * Math.PI * TRACK_R} ${2 * Math.PI * TRACK_R}`}
            transform={`rotate(-135 ${KNOB_R} ${KNOB_R})`}
            style={{ transition: dragging.current ? "none" : "stroke 200ms ease" }} />
        </svg>
        <div className="absolute rounded-full border border-neutral-700" style={{ top: 12, left: 12, right: 12, bottom: 12, background: "radial-gradient(circle at 40% 35%, #2a2a2a, #1a1a1a)" }} />
        <div className="absolute w-2.5 h-2.5 rounded-full" style={{ left: ix - 5, top: iy - 5, backgroundColor: glowColor, boxShadow: `0 0 6px ${glowColor}` }} />
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span className="font-mono tabular-nums font-medium" style={{ fontSize: "var(--text-title)", color: "var(--c-text)" }}>
            {Math.round(displayKnob)}°
          </span>
        </div>
      </div>

      {/* Descriptor + readout */}
      <div className="text-center" style={{ marginTop: -4 }}>
        <div className="font-mono italic" style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)" }}>
          {descriptor}
        </div>
        <div className="font-mono italic mt-0.5" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
          {readout}
        </div>
      </div>

      {/* ── HUE ──────────────────────────────────────────── */}
      <div className="w-full">
        <div className="flex justify-between items-end mb-1.5">
          <SectionLabel>Hue</SectionLabel>
          <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
            {hueFamily(hue)}
          </span>
        </div>
        <div
          ref={hueBarRef}
          className="relative h-5 rounded-full cursor-pointer"
          style={{ background: "linear-gradient(to right, oklch(0.65 0.25 0), oklch(0.65 0.25 60), oklch(0.65 0.25 120), oklch(0.65 0.25 180), oklch(0.65 0.25 240), oklch(0.65 0.25 300), oklch(0.65 0.25 360))" }}
          onPointerDown={onHuePointerDown}
          onPointerMove={onHuePointerMove}
          onPointerUp={onHuePointerUp}
        >
          <div className="absolute top-1/2 -translate-y-1/2 w-4 h-4 rounded-full border-2 border-white shadow-md pointer-events-none"
            style={{ left: `calc(${(hue / 360) * 100}% - 8px)`, backgroundColor: hueThumbColor }} />
        </div>
      </div>

      {/* ── ACCENT ───────────────────────────────────────── */}
      <div className="w-full">
        <div className="mb-2"><SectionLabel>Accent</SectionLabel></div>
        <div
          className="flex flex-wrap gap-1.5 justify-center w-full transition-opacity"
          style={{ opacity: isClash ? 0.3 : 1 }}
        >
          {REL_MODES.map((m) => {
            const isActive = relMode === m.id;
            return (
              <button
                key={m.id}
                className="px-2.5 py-1 rounded-full font-mono uppercase cursor-pointer transition-all"
                style={{
                  fontSize: "var(--text-micro)",
                  letterSpacing: "var(--track-caps)",
                  backgroundColor: isActive ? "rgba(255,255,255,0.18)" : "transparent",
                  color: isActive ? "var(--c-text)" : "var(--c-text-4)",
                  border: `1px solid ${isActive ? "rgba(255,255,255,0.20)" : "rgba(255,255,255,0.06)"}`,
                }}
                onClick={() => onRelModeChange(m.id)}
              >
                {m.label}
              </button>
            );
          })}
        </div>
        {/* Descriptor line — mode description or CLASH override notice */}
        <div className="font-mono italic text-center mt-2" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
          {isClash ? "Hue locked to clash range" : activeRelMode.description}
        </div>
      </div>

      {/* ── VARIATION ─────────────────────────────────────── */}
      <div className="w-full">
        <div className="mb-2"><SectionLabel>Variation</SectionLabel></div>

        {/* Waveform display */}
        <div className="w-full h-12 rounded bg-neutral-900 border border-neutral-800 relative overflow-hidden mb-2">
          {(() => {
            const wave = computeWaveform(activeFontCount, spread, variMode);
            const maxDev = spread * 144;
            const viewMax = Math.max(maxDev, 20); // minimum visible range
            return (
              <svg width="100%" height="100%" viewBox={`0 0 ${Math.max(2, activeFontCount - 1)} 2`} preserveAspectRatio="none">
                {/* Center line */}
                <line x1="0" y1="1" x2={activeFontCount - 1} y2="1" stroke="rgba(255,255,255,0.06)" strokeWidth="0.04" />
                {/* Waveform */}
                {wave.length > 1 && (
                  <polyline
                    fill="none"
                    stroke={glowColor}
                    strokeWidth="0.06"
                    strokeLinejoin="round"
                    strokeLinecap="round"
                    points={wave.map((d, idx) => `${idx},${1 - (d / viewMax) * 0.8}`).join(" ")}
                  />
                )}
                {/* Dots */}
                {wave.map((d, idx) => (
                  <circle key={idx} cx={idx} cy={1 - (d / viewMax) * 0.8} r="0.06" fill={glowColor} />
                ))}
              </svg>
            );
          })()}
        </div>

        {/* Smooth / Wild toggle */}
        <div className="flex rounded-md overflow-hidden border border-neutral-700 mb-3">
          {(["smooth", "wild"] as const).map((m) => {
            const active = variMode === m;
            return (
              <button key={m} className="flex-1 px-2 py-1 font-mono uppercase cursor-pointer transition-colors"
                style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", backgroundColor: active ? "#404040" : "transparent", color: active ? "var(--c-text)" : "var(--c-text-3)" }}
                onClick={() => onVariModeChange(m)}>{m}</button>
            );
          })}
        </div>

        {/* Spread slider */}
        <input
          type="range"
          min={0}
          max={100}
          step={1}
          value={Math.round(spread * 100)}
          onChange={(e) => onSpreadChange(+e.target.value / 100)}
          className={SIDEBAR_SLIDER}
        />
      </div>
    </div>
  );
}

// ── Bottom bar ───────────────────────────────────────────────────────

interface MKBottomControlsProps {
  knob: number;
  hue: number;
  spread: number;
  contrastLevel: ContrastLevel;
  colorCount: number;
}

export function MKBottomControls({ knob, hue, spread, contrastLevel, colorCount }: MKBottomControlsProps) {
  const descriptor = energyDescriptor(knob);
  const levelLabel = contrastLevel === "clash" ? "CLASH ⚡" : contrastLevel === "accessible" ? "ACCESSIBLE" : "DISPLAY";
  return (
    <div className="flex items-center gap-4 bg-black/40 px-5 py-2 rounded-full border border-neutral-800/80 shadow-inner">
      <span className="font-mono italic" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>
        {descriptor}
      </span>
      <div className="w-px h-3.5 bg-neutral-800/80" />
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {hueFamily(hue)}
      </span>
      <div className="w-px h-3.5 bg-neutral-800/80" />
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {colorCount} colors
      </span>
      <div className="w-px h-3.5 bg-neutral-800/80" />
      <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {levelLabel}
      </span>
      {spread > 0 && (
        <>
          <div className="w-px h-3.5 bg-neutral-800/80" />
          <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
            ±{Math.round(spread * 40)}%
          </span>
        </>
      )}
    </div>
  );
}
