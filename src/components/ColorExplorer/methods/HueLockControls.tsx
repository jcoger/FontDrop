import { useRef, useEffect, useCallback } from "react";
import {
  maxChroma as getMaxChroma,
  oklchToCss,
} from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import { sampleToneCurve } from "./hueLock";
import type { ChromaMode } from "../types";
import { SIDEBAR_SLIDER } from "../components/MethodSidebar";

// ── Hue Wheel ─────────────────────────────────────────────────────────

function paintWheel(canvas: HTMLCanvasElement) {
  const SIZE = 160;
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext("2d")!;
  const cx = SIZE / 2, cy = SIZE / 2;
  const outerR = SIZE / 2 - 1, innerR = outerR - 18;

  // Draw ring with conic gradient approximation (36 segments)
  for (let i = 0; i < 360; i++) {
    const a0 = ((i - 0.5) * Math.PI) / 180;
    const a1 = ((i + 1.5) * Math.PI) / 180;
    const color: OklchColor = { mode: "oklch", l: 0.6, c: 0.15, h: i };
    ctx.beginPath();
    ctx.arc(cx, cy, outerR, a0, a1);
    ctx.arc(cx, cy, innerR, a1, a0, true);
    ctx.closePath();
    ctx.fillStyle = oklchToCss(color);
    ctx.fill();
  }
}

interface HueWheelProps {
  hue: number;
  onHueChange: (h: number) => void;
  accentEnabled: boolean;
  accentHue: number;
  onAccentHueChange: (h: number) => void;
}

export function HueWheel({
  hue,
  onHueChange,
  accentEnabled,
  accentHue,
  onAccentHueChange,
}: HueWheelProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const dragTarget = useRef<"main" | "accent" | null>(null);

  useEffect(() => {
    if (canvasRef.current) paintWheel(canvasRef.current);
  }, []);

  const getAngle = useCallback((clientX: number, clientY: number): number => {
    const el = containerRef.current;
    if (!el) return 0;
    const rect = el.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    let angle = Math.atan2(clientY - cy, clientX - cx) * (180 / Math.PI);
    angle = (angle + 90 + 360) % 360; // 0 = top
    return Math.round(angle);
  }, []);

  function onPointerDown(e: React.PointerEvent) {
    e.preventDefault();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    const angle = getAngle(e.clientX, e.clientY);

    // Decide if dragging accent or main
    if (accentEnabled) {
      const distMain = Math.min(Math.abs(angle - hue), 360 - Math.abs(angle - hue));
      const distAccent = Math.min(Math.abs(angle - accentHue), 360 - Math.abs(angle - accentHue));
      if (distAccent < distMain && distAccent < 30) {
        dragTarget.current = "accent";
        onAccentHueChange(angle);
        return;
      }
    }
    dragTarget.current = "main";
    onHueChange(angle);
  }

  function onPointerMove(e: React.PointerEvent) {
    if (!dragTarget.current) return;
    const angle = getAngle(e.clientX, e.clientY);
    if (dragTarget.current === "accent") onAccentHueChange(angle);
    else onHueChange(angle);
  }

  function onPointerUp() {
    dragTarget.current = null;
  }

  // Live preview color for center
  const previewCss = oklchToCss({
    mode: "oklch",
    l: 0.6,
    c: getMaxChroma(0.6, hue),
    h: hue,
  });

  // Handle positions (CSS transforms for dots on the ring)
  const ringR = 42; // % from center — dot sits at middle of the ring
  function dotStyle(angle: number) {
    const rad = ((angle - 90) * Math.PI) / 180;
    return {
      left: `${50 + ringR * Math.cos(rad)}%`,
      top: `${50 + ringR * Math.sin(rad)}%`,
      transform: "translate(-50%, -50%)",
    };
  }

  return (
    <div>
      <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
        Hue
      </div>
      <div
        ref={containerRef}
        className="relative mx-auto select-none cursor-crosshair"
        style={{ width: 160, height: 160 }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        role="slider"
        aria-label="Hue wheel"
        aria-valuetext={`${hue} degrees`}
      >
        <canvas ref={canvasRef} className="absolute inset-0 w-full h-full rounded-full" />

        {/* Center preview */}
        <div
          className="absolute rounded-full"
          style={{
            width: "60%", height: "60%",
            left: "20%", top: "20%",
            backgroundColor: previewCss,
            boxShadow: "inset 0 2px 6px rgba(0,0,0,0.3)",
          }}
        />

        {/* Hue readout in center */}
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <span className="font-mono font-medium" style={{ fontSize: "var(--text-ui)", color: "var(--c-text)" }}>
            {hue}°
          </span>
        </div>

        {/* Main handle */}
        <div className="absolute pointer-events-none" style={dotStyle(hue)}>
          <div className="w-4 h-4 rounded-full bg-white border-2 border-black/40 shadow-[0_0_4px_rgba(0,0,0,0.6)]" />
        </div>

        {/* Accent handle */}
        {accentEnabled && (
          <div className="absolute pointer-events-none" style={dotStyle(accentHue)}>
            <div className="w-3 h-3 rounded-full border-2 border-white/80 shadow-[0_0_4px_rgba(0,0,0,0.6)]"
              style={{ backgroundColor: oklchToCss({ mode: "oklch", l: 0.6, c: getMaxChroma(0.6, accentHue), h: accentHue }) }} />
          </div>
        )}
      </div>
    </div>
  );
}

// ── Tone Curve Editor ─────────────────────────────────────────────────

const CURVE_W = 190;
const CURVE_H = 120;
const L_MIN = 0.15;
const L_MAX = 0.93;

function paintCurve(
  canvas: HTMLCanvasElement,
  midY: number,
  steps: number,
) {
  canvas.width = CURVE_W * 2; // 2x for retina
  canvas.height = CURVE_H * 2;
  const ctx = canvas.getContext("2d")!;
  ctx.scale(2, 2);

  // Background
  ctx.fillStyle = "#1a1a1a";
  ctx.fillRect(0, 0, CURVE_W, CURVE_H);

  // Gridlines at L=0.25, 0.5, 0.75
  ctx.strokeStyle = "rgba(255,255,255,0.06)";
  ctx.lineWidth = 1;
  for (const gl of [0.25, 0.5, 0.75]) {
    const y = CURVE_H - ((gl - L_MIN) / (L_MAX - L_MIN)) * CURVE_H;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(CURVE_W, y);
    ctx.stroke();
  }

  // Draw curve
  ctx.strokeStyle = "rgba(255,255,255,0.85)";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  const pts = 60;
  for (let i = 0; i <= pts; i++) {
    const t = i / pts;
    const l =
      (1 - t) * (1 - t) * L_MIN +
      2 * (1 - t) * t * midY +
      t * t * L_MAX;
    const x = t * CURVE_W;
    const y = CURVE_H - ((l - L_MIN) / (L_MAX - L_MIN)) * CURVE_H;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.stroke();

  // Draw step sample dots
  const samples = sampleToneCurve(steps, midY);
  ctx.fillStyle = "rgba(217,119,54,0.9)";
  for (let i = 0; i < samples.length; i++) {
    const t = samples.length === 1 ? 0.5 : i / (samples.length - 1);
    const x = t * CURVE_W;
    const y = CURVE_H - ((samples[i] - L_MIN) / (L_MAX - L_MIN)) * CURVE_H;
    ctx.beginPath();
    ctx.arc(x, y, 2.5, 0, Math.PI * 2);
    ctx.fill();
  }
}

interface ToneCurveProps {
  midY: number;
  onMidYChange: (v: number) => void;
  steps: number;
  onStepsChange: (v: number) => void;
}

export function ToneCurve({
  midY,
  onMidYChange,
  steps,
  onStepsChange,
}: ToneCurveProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const dragging = useRef(false);

  useEffect(() => {
    if (canvasRef.current) paintCurve(canvasRef.current, midY, steps);
  }, [midY, steps]);

  function applyDrag(_clientX: number, clientY: number) {
    const el = containerRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const y = 1 - (clientY - rect.top) / rect.height;
    const lVal = L_MIN + Math.max(0, Math.min(1, y)) * (L_MAX - L_MIN);
    onMidYChange(Math.max(L_MIN + 0.05, Math.min(L_MAX - 0.05, lVal)));
  }

  function onPointerDown(e: React.PointerEvent) {
    e.preventDefault();
    dragging.current = true;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    applyDrag(e.clientX, e.clientY);
  }

  function onPointerMove(e: React.PointerEvent) {
    if (!dragging.current) return;
    applyDrag(e.clientX, e.clientY);
  }

  function onPointerUp() {
    dragging.current = false;
  }

  // Midpoint dot position
  const midDotX = 50; // always at center X
  const midDotY = ((midY - L_MIN) / (L_MAX - L_MIN)) * 100;

  return (
    <div>
      <div className="flex justify-between items-center mb-2">
        <span className="font-mono uppercase" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
          Lightness Curve
        </span>
        <div className="flex items-center gap-1.5">
          <button
            className="w-5 h-5 rounded flex items-center justify-center font-mono cursor-pointer border border-neutral-700 hover:border-neutral-500 transition-colors"
            style={{ fontSize: "var(--text-ui)", color: "var(--c-text-2)" }}
            onClick={() => onStepsChange(Math.max(3, steps - 1))}
            aria-label="Decrease steps"
          >-</button>
          <span className="font-mono w-5 text-center tabular-nums" style={{ fontSize: "var(--text-label)", color: "var(--c-text)" }}>
            {steps}
          </span>
          <button
            className="w-5 h-5 rounded flex items-center justify-center font-mono cursor-pointer border border-neutral-700 hover:border-neutral-500 transition-colors"
            style={{ fontSize: "var(--text-ui)", color: "var(--c-text-2)" }}
            onClick={() => onStepsChange(Math.min(12, steps + 1))}
            aria-label="Increase steps"
          >+</button>
        </div>
      </div>

      <div
        ref={containerRef}
        className="relative rounded-lg overflow-hidden cursor-ns-resize select-none"
        style={{ width: "100%", aspectRatio: `${CURVE_W}/${CURVE_H}`, boxShadow: "inset 0 1px 4px rgba(0,0,0,0.4)" }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        role="slider"
        aria-label="Lightness curve midpoint"
        aria-valuetext={`Midpoint at ${Math.round(midY * 100)}% lightness`}
      >
        <canvas ref={canvasRef} className="absolute inset-0 w-full h-full" />

        {/* Draggable midpoint */}
        <div
          className="absolute pointer-events-none"
          style={{
            left: `${midDotX}%`,
            bottom: `${midDotY}%`,
            transform: "translate(-50%, 50%)",
          }}
        >
          <div className="w-3 h-3 rounded-full bg-white border-2 border-black/40 shadow-[0_0_4px_rgba(0,0,0,0.6)]" />
        </div>
      </div>
    </div>
  );
}

// ── Combined Hue Lock sidebar params ──────────────────────────────────

interface HLParamsProps {
  hue: number;
  onHueChange: (v: number) => void;
  steps: number;
  onStepsChange: (v: number) => void;
  curveMidY: number;
  onCurveMidYChange: (v: number) => void;
  chromaMode: ChromaMode;
  onChromaModeChange: (v: ChromaMode) => void;
  fixedChroma: number;
  onFixedChromaChange: (v: number) => void;
  accentEnabled: boolean;
  onAccentEnabledChange: (v: boolean) => void;
  accentHue: number;
  onAccentHueChange: (v: number) => void;
  accentL: number;
  onAccentLChange: (v: number) => void;
}

export function HLParams({
  hue,
  onHueChange,
  steps,
  onStepsChange,
  curveMidY,
  onCurveMidYChange,
  chromaMode,
  onChromaModeChange,
  fixedChroma,
  onFixedChromaChange,
  accentEnabled,
  onAccentEnabledChange,
  accentHue,
  onAccentHueChange,
  accentL,
  onAccentLChange,
}: HLParamsProps) {
  return (
    <>
      {/* Hue Wheel */}
      <HueWheel
        hue={hue}
        onHueChange={onHueChange}
        accentEnabled={accentEnabled}
        accentHue={accentHue}
        onAccentHueChange={onAccentHueChange}
      />

      {/* Tone Curve */}
      <ToneCurve
        midY={curveMidY}
        onMidYChange={onCurveMidYChange}
        steps={steps}
        onStepsChange={onStepsChange}
      />

      {/* Chroma mode pill */}
      <div>
        <div className="font-mono uppercase mb-1" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>
          Chroma
        </div>
        <div className="flex rounded-md overflow-hidden border border-neutral-700">
          {(["max", "fixed"] as const).map((m) => (
            <button key={m} className="flex-1 px-3 py-1 font-medium transition-colors capitalize cursor-pointer"
              style={{ fontSize: "var(--text-body)", backgroundColor: chromaMode === m ? "#404040" : "transparent", color: chromaMode === m ? "var(--c-text)" : "var(--c-text-2)" }}
              onClick={() => onChromaModeChange(m)}>{m}</button>
          ))}
        </div>
        {chromaMode === "fixed" && (
          <div className="mt-2">
            <input type="range" min={0} max={0.4} step={0.005} value={fixedChroma}
              onChange={(e) => onFixedChromaChange(+e.target.value)} className={SIDEBAR_SLIDER}
              aria-label="Fixed chroma" aria-valuetext={fixedChroma.toFixed(2)} />
            <div className="text-right font-mono mt-0.5" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
              {fixedChroma.toFixed(2)}
            </div>
          </div>
        )}
      </div>

      {/* Accent toggle */}
      <div>
        <label className="flex items-center gap-2.5 cursor-pointer">
          <button className="w-8 h-[18px] rounded-full relative transition-colors shrink-0"
            style={{ backgroundColor: accentEnabled ? "var(--c-accent)" : "#404040" }}
            onClick={() => onAccentEnabledChange(!accentEnabled)}>
            <div className="absolute top-[3px] w-3 h-3 rounded-full bg-white shadow transition-transform"
              style={{ transform: accentEnabled ? "translateX(17px)" : "translateX(3px)" }} />
          </button>
          <span style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)" }}>Accent</span>
        </label>
      </div>

      {/* Accent L slider (hue is on the wheel) */}
      {accentEnabled && (
        <div>
          <div className="flex justify-between items-end mb-1">
            <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>Accent Lightness</span>
            <span className="font-mono bg-black/30 px-1.5 py-0.5 rounded" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>{Math.round(accentL * 100)}%</span>
          </div>
          <input type="range" min={0} max={1} step={0.01} value={accentL}
            onChange={(e) => onAccentLChange(+e.target.value)} className={SIDEBAR_SLIDER}
            aria-label="Accent lightness" aria-valuetext={`${Math.round(accentL * 100)} percent`} />
        </div>
      )}
    </>
  );
}
