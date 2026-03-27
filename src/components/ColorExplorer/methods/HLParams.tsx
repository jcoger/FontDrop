import { HueWheel } from "./HueWheel";
import { ToneCurve } from "./ToneCurve";
import type { ChromaMode } from "../types";
import { SIDEBAR_SLIDER } from "../components/MethodSidebar";

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
      <HueWheel
        hue={hue}
        onHueChange={onHueChange}
        accentEnabled={accentEnabled}
        accentHue={accentHue}
        onAccentHueChange={onAccentHueChange}
      />

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
