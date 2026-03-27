import { useRef, useEffect, useCallback } from "react";
import { maxChroma as getMaxChroma, oklchToCss } from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";

// ── Canvas painter ────────────────────────────────────────────────────

function paintWheel(canvas: HTMLCanvasElement): void {
  const SIZE = 160;
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext("2d")!;
  const cx = SIZE / 2, cy = SIZE / 2;
  const outerR = SIZE / 2 - 1, innerR = outerR - 18;

  // Draw ring with conic gradient approximation (360 segments)
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

// ── Component ─────────────────────────────────────────────────────────

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

  // Paint wheel once on mount — static gradient, no need to repaint
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

  const previewCss = oklchToCss({ mode: "oklch", l: 0.6, c: getMaxChroma(0.6, hue), h: hue });

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
