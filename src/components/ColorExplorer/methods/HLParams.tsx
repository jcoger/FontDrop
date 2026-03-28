import { useState, useMemo } from "react";
import { HueWheel } from "./HueWheel";
import { ToneCurve } from "./ToneCurve";
import type { ChromaMode, ColorVariety, ContrastLevel } from "../types";
import { SIDEBAR_SLIDER } from "../components/MethodSidebar";
import { oklchToCss, oklchToHex } from "../../../utils/oklch";
import {
  HL_FG_PRESETS,
  previewFgForPreset,
  parseColorInput,
  hlHueFamily,
} from "./hueLogic";
import type { HLFgPreset } from "./hueLogic";

// Re-exports for index.tsx
export { generateHueMode, hlFlipCard, hlGetNeutralMeta, hlContrastRange, hlHueFamily } from "./hueLogic";
export type { HLRampColor, HLFgPreset } from "./hueLogic";

// ── Section label ────────────────────────────────────────────────────

function SectionLabel({ children }: { children: string }) {
  return (
    <span className="font-mono uppercase" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>
      {children}
    </span>
  );
}

// ── Props ────────────────────────────────────────────────────────────

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
  // Accent (kept for backward compat but hidden in new UI)
  accentEnabled: boolean;
  onAccentEnabledChange: (v: boolean) => void;
  accentHue: number;
  onAccentHueChange: (v: number) => void;
  accentL: number;
  onAccentLChange: (v: number) => void;
  // New FG system
  fgPreset: HLFgPreset;
  onFgPresetChange: (v: HLFgPreset) => void;
  fgLOverride: number | null;
  onFgLOverrideChange: (v: number | null) => void;
  fgCOverride: number | null;
  onFgCOverrideChange: (v: number | null) => void;
  // Variety
  variety: ColorVariety;
  onVarietyChange: (v: ColorVariety) => void;
  activeFontCount: number;
  // Contrast
  contrastLevel: ContrastLevel;
}

// ── Component ────────────────────────────────────────────────────────

export function HLParams({
  hue, onHueChange,
  steps, onStepsChange,
  curveMidY, onCurveMidYChange,
  chromaMode, onChromaModeChange,
  fixedChroma, onFixedChromaChange,
  fgPreset, onFgPresetChange,
  fgLOverride, onFgLOverrideChange,
  fgCOverride, onFgCOverrideChange,
  variety, onVarietyChange,
  activeFontCount,
}: HLParamsProps) {
  // ── Hex input ──────────────────────────────────────────────
  const [hexInput, setHexInput] = useState("");
  const [hexError, setHexError] = useState(false);

  const currentHex = useMemo(() => {
    const c = oklchToHex({ mode: "oklch", l: 0.55, c: 0.20, h: hue });
    return typeof c === "string" && c.startsWith("#") ? c : `hue ${Math.round(hue)}°`;
  }, [hue]);

  function handleHexSubmit() {
    const parsed = parseColorInput(hexInput || currentHex);
    if (parsed) {
      onHueChange(Math.round(parsed.h));
      setHexError(false);
      setHexInput("");
    } else {
      setHexError(true);
    }
  }

  // ── FG preview chips ───────────────────────────────────────
  const fgPreviews = useMemo(() => {
    return HL_FG_PRESETS.map((p) => ({
      ...p,
      previewCss: oklchToCss(previewFgForPreset(p.id, hue)),
    }));
  }, [hue]);

  return (
    <div className="flex flex-col gap-5">
      {/* ── BG HUE ─────────────────────────────────────────── */}
      <div>
        <div className="flex justify-between items-end mb-2">
          <SectionLabel>BG Hue</SectionLabel>
          <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
            {hlHueFamily(hue)}
          </span>
        </div>
        <HueWheel
          hue={hue}
          onHueChange={onHueChange}
          accentEnabled={false}
          accentHue={0}
          onAccentHueChange={() => {}}
        />
        {/* Hex input below wheel */}
        <div className="mt-2">
          <input
            type="text"
            className="w-full bg-neutral-900 border rounded px-2.5 py-1.5 font-mono text-center outline-none transition-colors"
            style={{
              fontSize: "var(--text-body)",
              color: "var(--c-text-2)",
              borderColor: hexError ? "rgba(239,68,68,0.5)" : "rgba(255,255,255,0.08)",
            }}
            placeholder={currentHex}
            value={hexInput}
            onChange={(e) => { setHexInput(e.target.value); setHexError(false); }}
            onKeyDown={(e) => { if (e.key === "Enter") handleHexSubmit(); }}
            onBlur={() => { if (hexInput) handleHexSubmit(); }}
          />
        </div>
      </div>

      {/* ── BG SHADES ──────────────────────────────────────── */}
      <div>
        <div className="mb-2"><SectionLabel>BG Shades</SectionLabel></div>
        <ToneCurve
          midY={curveMidY}
          onMidYChange={onCurveMidYChange}
          steps={steps}
          onStepsChange={onStepsChange}
        />
      </div>

      {/* Chroma mode */}
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
              onChange={(e) => onFixedChromaChange(+e.target.value)} className={SIDEBAR_SLIDER} />
            <div className="text-right font-mono mt-0.5" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
              {fixedChroma.toFixed(2)}
            </div>
          </div>
        )}
      </div>

      {/* ── FOREGROUND ─────────────────────────────────────── */}
      <div>
        <div className="mb-2"><SectionLabel>Foreground</SectionLabel></div>
        <div className="flex flex-wrap gap-1.5">
          {fgPreviews.map((p) => {
            const isActive = fgPreset === p.id;
            return (
              <button
                key={p.id}
                className="flex items-center gap-1.5 px-2 py-1 rounded-full font-mono uppercase cursor-pointer transition-all"
                style={{
                  fontSize: "var(--text-micro)",
                  letterSpacing: "var(--track-caps)",
                  backgroundColor: isActive ? "rgba(255,255,255,0.18)" : "transparent",
                  color: isActive ? "var(--c-text)" : "var(--c-text-4)",
                  border: `1px solid ${isActive ? "rgba(255,255,255,0.20)" : "rgba(255,255,255,0.06)"}`,
                }}
                onClick={() => {
                  onFgPresetChange(p.id);
                  onFgLOverrideChange(null);
                  onFgCOverrideChange(null);
                }}
              >
                <div className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: p.previewCss }} />
                {p.label}
              </button>
            );
          })}
        </div>

        {/* FG fine-tune sliders */}
        <div className="mt-3 flex flex-col gap-2">
          <div>
            <div className="flex justify-between items-center mb-0.5">
              <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>Lightness</span>
              {fgLOverride !== null && (
                <button className="font-mono cursor-pointer" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}
                  onClick={() => onFgLOverrideChange(null)}>Reset</button>
              )}
            </div>
            <input type="range" min={0} max={100} step={1}
              value={fgLOverride !== null ? Math.round(fgLOverride * 100) : 50}
              onChange={(e) => onFgLOverrideChange(+e.target.value / 100)}
              className={SIDEBAR_SLIDER} style={{ opacity: fgLOverride !== null ? 1 : 0.4 }} />
          </div>
          <div>
            <div className="flex justify-between items-center mb-0.5">
              <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>Chroma</span>
              {fgCOverride !== null && (
                <button className="font-mono cursor-pointer" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}
                  onClick={() => onFgCOverrideChange(null)}>Reset</button>
              )}
            </div>
            <input type="range" min={0} max={100} step={1}
              value={fgCOverride !== null ? Math.round(fgCOverride * 100) : 50}
              onChange={(e) => onFgCOverrideChange(+e.target.value / 100)}
              className={SIDEBAR_SLIDER} style={{ opacity: fgCOverride !== null ? 1 : 0.4 }} />
          </div>
        </div>
      </div>

      {/* ── COLOR VARIETY ──────────────────────────────────── */}
      <div>
        <div className="flex justify-between items-end mb-2">
          <SectionLabel>Color Variety</SectionLabel>
          <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
            {variety === "tight" ? `Tight · ${Math.max(4, Math.ceil(activeFontCount / 2))}` : variety === "wide" ? `Wide · ${Math.min(24, activeFontCount * 2)}` : `Auto · ${activeFontCount}`}
          </span>
        </div>
        <div className="flex rounded-md overflow-hidden border border-neutral-700">
          {(["tight", "auto", "wide"] as const).map((v) => {
            const active = variety === v;
            return (
              <button key={v} className="flex-1 px-2 py-1 font-mono uppercase cursor-pointer transition-colors"
                style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", backgroundColor: active ? "#404040" : "transparent", color: active ? "var(--c-text)" : "var(--c-text-3)" }}
                onClick={() => onVarietyChange(v)}>{v}</button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ── Bottom bar ───────────────────────────────────────────────────────

interface HLBottomControlsProps {
  hue: number;
  shadeCount: number;
  contrastRange: [number, number];
  contrastLevel: ContrastLevel;
}

export function HLBottomControls({ hue, shadeCount, contrastRange, contrastLevel }: HLBottomControlsProps) {
  const levelLabel = contrastLevel === "clash" ? "CLASH ⚡" : contrastLevel === "accessible" ? "ACCESSIBLE" : "DISPLAY";
  return (
    <div className="flex items-center gap-4 bg-black/40 px-5 py-2 rounded-full border border-neutral-800/80 shadow-inner">
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>
        {hlHueFamily(hue)}
      </span>
      <div className="w-px h-3.5 bg-neutral-800/80" />
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {shadeCount} shades
      </span>
      <div className="w-px h-3.5 bg-neutral-800/80" />
      <span className="font-mono tabular-nums" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {contrastRange[0].toFixed(1)}–{contrastRange[1].toFixed(1)}
      </span>
      <div className="w-px h-3.5 bg-neutral-800/80" />
      <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {levelLabel}
      </span>
    </div>
  );
}
