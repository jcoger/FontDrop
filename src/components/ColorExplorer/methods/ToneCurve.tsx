import { useRef, useEffect } from "react";
import { sampleToneCurve, L_MIN, L_MAX } from "./hueLock";

// ── Canvas painter ────────────────────────────────────────────────────

function paintCurve(canvas: HTMLCanvasElement, midY: number, steps: number): void {
  const CURVE_W = 190;
  const CURVE_H = 120;
  canvas.width = CURVE_W * 2; // 2× for retina
  canvas.height = CURVE_H * 2;
  const ctx = canvas.getContext("2d")!;
  ctx.scale(2, 2);

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

  // Bezier curve
  ctx.strokeStyle = "rgba(255,255,255,0.85)";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  const pts = 60;
  for (let i = 0; i <= pts; i++) {
    const t = i / pts;
    const l = (1 - t) * (1 - t) * L_MIN + 2 * (1 - t) * t * midY + t * t * L_MAX;
    const x = t * CURVE_W;
    const y = CURVE_H - ((l - L_MIN) / (L_MAX - L_MIN)) * CURVE_H;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.stroke();

  // Step sample dots
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

// ── Component ─────────────────────────────────────────────────────────

interface ToneCurveProps {
  midY: number;
  onMidYChange: (v: number) => void;
  steps: number;
  onStepsChange: (v: number) => void;
}

export function ToneCurve({ midY, onMidYChange, steps, onStepsChange }: ToneCurveProps) {
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

  const CURVE_W = 190;
  const CURVE_H = 120;
  const midDotX = 50;
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

        {/* Draggable midpoint dot */}
        <div
          className="absolute pointer-events-none"
          style={{ left: `${midDotX}%`, bottom: `${midDotY}%`, transform: "translate(-50%, 50%)" }}
        >
          <div className="w-3 h-3 rounded-full bg-white border-2 border-black/40 shadow-[0_0_4px_rgba(0,0,0,0.6)]" />
        </div>
      </div>
    </div>
  );
}
