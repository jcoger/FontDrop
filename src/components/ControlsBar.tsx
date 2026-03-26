import { Controls } from "../types/controls";
import { ColorControls } from "./ColorSwatch";

interface Props {
  controls: Controls;
  onChange: (patch: Partial<Controls>) => void;
  onShowShortcuts?: () => void;
}

interface SliderProps {
  label: string;
  min: number;
  max: number;
  step: number;
  value: number;
  display: string;
  onChange: (v: number) => void;
}

function Slider({ label, min, max, step, value, display, onChange }: SliderProps) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-[10px] text-neutral-600 font-mono uppercase tracking-widest w-7 leading-none">
        {label}
      </span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        className="w-20"
      />
      <span className="text-[11px] text-neutral-500 font-mono tabular-nums w-9 text-right leading-none">
        {display}
      </span>
    </div>
  );
}

export function ControlsBar({ controls, onChange, onShowShortcuts }: Props) {
  const trackDisplay =
    controls.letterSpacing === 0
      ? "0"
      : controls.letterSpacing > 0
        ? `+${controls.letterSpacing.toFixed(2)}`
        : controls.letterSpacing.toFixed(2);

  return (
    <div className="flex-shrink-0 flex items-center gap-4 px-4 h-12 border-t border-neutral-800 bg-neutral-950">
      {/* Typography sliders */}
      <Slider
        label="size"
        min={12}
        max={120}
        step={1}
        value={controls.fontSize}
        display={`${controls.fontSize}`}
        onChange={(v) => onChange({ fontSize: v })}
      />

      <div className="w-px h-4 bg-neutral-800 flex-shrink-0" />

      <Slider
        label="track"
        min={-0.05}
        max={0.3}
        step={0.005}
        value={controls.letterSpacing}
        display={trackDisplay}
        onChange={(v) => onChange({ letterSpacing: parseFloat(v.toFixed(3)) })}
      />

      <div className="w-px h-4 bg-neutral-800 flex-shrink-0" />

      <Slider
        label="wt"
        min={100}
        max={900}
        step={100}
        value={controls.fontWeight}
        display={`${controls.fontWeight}`}
        onChange={(v) => onChange({ fontWeight: v })}
      />

      {/* Spacer */}
      <div className="flex-1" />

      {/* Unified color controls */}
      <ColorControls
        bgColor={controls.bgColor}
        fgColor={controls.fgColor}
        onChangeBg={(hex) => onChange({ bgColor: hex })}
        onChangeFg={(hex) => onChange({ fgColor: hex })}
      />

      {/* Keyboard shortcuts ? button */}
      {onShowShortcuts && (
        <>
          <div className="w-px h-4 bg-neutral-800 flex-shrink-0" />
          <button
            className="w-6 h-6 rounded-full border border-neutral-700 hover:border-neutral-500
                       flex items-center justify-center text-neutral-600 hover:text-neutral-300
                       text-xs font-mono transition-colors cursor-pointer flex-shrink-0"
            onClick={onShowShortcuts}
            aria-label="Keyboard shortcuts"
          >
            ?
          </button>
        </>
      )}
    </div>
  );
}
