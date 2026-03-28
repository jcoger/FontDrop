import { HexColorPicker } from "react-colorful";
import { useState } from "react";
import type { OklchColor } from "../../../utils/oklch";
import { ScatterPlot } from "./ScatterPlot";
import type { HueMode, Threshold, ContrastRampColor } from "../types";

// Re-export generation function for use in index.tsx
export { generateContrastSafe } from "./csLogic";
export type { ContrastRampColor };

// ── Sidebar ───────────────────────────────────────────────────────────

interface CSParamsProps {
  primaryHex: string;
  onPrimaryHexChange: (hex: string) => void;
  primary: OklchColor;
  threshold: Threshold;
  onThresholdChange: (v: Threshold) => void;
  hueMode: HueMode;
  onHueModeChange: (v: HueMode) => void;
  density: number;
  onDensityChange: (v: number) => void;
  fgLock: boolean;
  onFgLockChange: (v: boolean) => void;
  lRange: [number, number];
  onLRangeChange: (v: [number, number]) => void;
  results: ContrastRampColor[];
  onSetWorkingColor: (idx: number) => void;
}

export function CSParams({
  primaryHex,
  onPrimaryHexChange,
  primary,
  threshold,
  onThresholdChange,
  hueMode,
  onHueModeChange,
  density,
  onDensityChange,
  fgLock,
  onFgLockChange,
  lRange: _lRange,
  onLRangeChange,
  results,
  onSetWorkingColor,
}: CSParamsProps) {
  const [hexInput, setHexInput] = useState(primaryHex);

  function commitHex(raw: string) {
    const cleaned = raw.replace(/[^0-9a-fA-F]/g, "").slice(0, 6);
    if (cleaned.length === 6) { const hex = `#${cleaned}`; setHexInput(hex); onPrimaryHexChange(hex); }
  }

  function handlePickerChange(hex: string) { setHexInput(hex); onPrimaryHexChange(hex); }

  return (
    <>
      {/* Primary color picker */}
      <div>
        <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
          Primary Color
        </div>
        <div className="rounded-lg overflow-hidden mb-3">
          <HexColorPicker color={primaryHex} onChange={handlePickerChange} style={{ width: "100%" }} />
        </div>
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded border border-border-strong shrink-0" style={{ backgroundColor: primaryHex }} />
          <input className="flex-1 bg-surface-4 text-fg font-mono rounded px-2 py-1.5 outline-none placeholder:text-fg-3 focus:ring-1 focus:ring-border-strong uppercase"
            style={{ fontSize: "var(--text-body)" }}
            value={hexInput} onChange={(e) => setHexInput(e.target.value)}
            onBlur={(e) => commitHex(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") commitHex(e.currentTarget.value); }}
            spellCheck={false} placeholder="#000000" />
        </div>
      </div>

      {/* Threshold toggle */}
      <div>
        <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>Threshold</div>
        <div className="flex rounded-md overflow-hidden border border-border-strong">
          {(["AA", "AAA"] as const).map((t) => (
            <button key={t} className="flex-1 px-3 py-1.5 font-medium transition-colors cursor-pointer"
              style={{ fontSize: "var(--text-body)", backgroundColor: threshold === t ? "var(--surface-active)" : "transparent", color: threshold === t ? "var(--c-text)" : "var(--c-text-2)" }}
              onClick={() => onThresholdChange(t)}>{t}</button>
          ))}
        </div>
      </div>

      {/* Scatter plot widget */}
      <ScatterPlot
        results={results}
        primary={primary}
        threshold={threshold}
        hueMode={hueMode}
        onLRangeChange={onLRangeChange}
        onSetWorkingColor={onSetWorkingColor}
      />

      {/* Hue zoom + density */}
      <div className="flex items-center gap-3">
        <div className="flex rounded-md overflow-hidden border border-border-strong flex-1">
          {(["full", "neighborhood"] as const).map((m) => (
            <button key={m} className="flex-1 px-2 py-1 font-medium transition-colors capitalize cursor-pointer"
              style={{ fontSize: "var(--text-badge)", backgroundColor: hueMode === m ? "var(--surface-active)" : "transparent", color: hueMode === m ? "var(--c-text)" : "var(--c-text-2)" }}
              onClick={() => onHueModeChange(m)}>
              {m === "full" ? "Full" : "Near"}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-1">
          <button className="w-5 h-5 rounded flex items-center justify-center font-mono cursor-pointer border border-border-strong hover:border-border-strong transition-colors"
            style={{ fontSize: "var(--text-ui)", color: "var(--c-text-2)" }}
            onClick={() => onDensityChange(Math.max(8, density - 2))} aria-label="Decrease density">-</button>
          <span className="font-mono w-5 text-center tabular-nums" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>{density}</span>
          <button className="w-5 h-5 rounded flex items-center justify-center font-mono cursor-pointer border border-border-strong hover:border-border-strong transition-colors"
            style={{ fontSize: "var(--text-ui)", color: "var(--c-text-2)" }}
            onClick={() => onDensityChange(Math.min(32, density + 2))} aria-label="Increase density">+</button>
        </div>
      </div>

      {/* Foreground lock */}
      <div>
        <label className="flex items-center gap-2.5 cursor-pointer">
          <button className="w-8 h-[18px] rounded-full relative transition-colors shrink-0"
            style={{ backgroundColor: fgLock ? "var(--c-accent)" : "var(--surface-active)" }}
            onClick={() => onFgLockChange(!fgLock)}>
            <div className="absolute top-[3px] w-3 h-3 rounded-full bg-white shadow transition-transform"
              style={{ transform: fgLock ? "translateX(17px)" : "translateX(3px)" }} />
          </button>
          <span style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)" }}>Foreground Lock</span>
        </label>
        <div className="font-mono mt-1 pl-[42px]" style={{ fontSize: "var(--text-micro)", color: "var(--c-text-4)" }}>
          {fgLock ? "Test colors as BG" : "Primary as BG"}
        </div>
      </div>
    </>
  );
}

// ── Bottom bar ────────────────────────────────────────────────────────

interface CSBottomControlsProps {
  lRange: [number, number];
  cRange: [number, number];
}

export function CSBottomControls({ lRange, cRange }: CSBottomControlsProps) {
  return (
    <div className="flex items-center gap-4 bg-black/40 px-5 py-2 rounded-full border border-border-default shadow-inner">
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        L {Math.round(lRange[0] * 100)}–{Math.round(lRange[1] * 100)}
      </span>
      <div className="w-px h-3.5 bg-border-default" />
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        C {cRange[0].toFixed(2)}–{cRange[1].toFixed(2)}
      </span>
    </div>
  );
}
