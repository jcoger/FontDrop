import { useState, useCallback, useEffect, useRef } from "react";
import { SIDEBAR_SLIDER } from "../components/MethodSidebar";
import { WP_TAGS, wpReadout } from "./wpLogic";
import type { WPTagName } from "./wpLogic";

export { generateWordPicker, wpGetNeutralMeta } from "./wpLogic";
export type { WPTagName, WPRampColor } from "./wpLogic";

// ── Props ────────────────────────────────────────────────────────────

interface WPParamsProps {
  activeTags: WPTagName[];
  onTagsChange: (tags: WPTagName[]) => void;
  drift: number;
  onDriftChange: (v: number) => void;
  count: number;
  onCountChange: (v: number) => void;
  variety: import("../types").ColorVariety;
  onVarietyChange: (v: import("../types").ColorVariety) => void;
  activeFontCount: number;
  accent: boolean;
  onAccentChange: (v: boolean) => void;
}

// ── Component ────────────────────────────────────────────────────────

export function WPParams({
  activeTags,
  onTagsChange,
  drift,
  onDriftChange,
  variety,
  onVarietyChange,
  activeFontCount,
  accent,
  onAccentChange,
}: WPParamsProps) {
  // Debounced readout
  const [readoutText, setReadoutText] = useState("");
  const readoutTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const tagsTuple = activeTags as [] | [WPTagName] | [WPTagName, WPTagName];

  useEffect(() => {
    clearTimeout(readoutTimer.current);
    readoutTimer.current = setTimeout(() => {
      setReadoutText(wpReadout(tagsTuple, drift));
    }, 200);
    return () => clearTimeout(readoutTimer.current);
  }, [activeTags[0], activeTags[1], drift]);

  // Immediate readout on first render
  useEffect(() => {
    setReadoutText(wpReadout(tagsTuple, drift));
  }, []);

  const handleTagClick = useCallback(
    (tag: WPTagName) => {
      const idx = activeTags.indexOf(tag);
      if (idx >= 0) {
        // Deselect
        onTagsChange(activeTags.filter((t) => t !== tag));
      } else if (activeTags.length < 2) {
        // Add
        onTagsChange([...activeTags, tag]);
      } else {
        // Replace oldest (first) tag
        onTagsChange([activeTags[1], tag]);
      }
    },
    [activeTags, onTagsChange],
  );

  const isBlending = activeTags.length === 2;
  const driftLabel = isBlending ? "BLEND" : "INTENSITY";

  return (
    <div className="flex flex-col gap-5">
      {/* Tag grid */}
      <div>
        <div className="flex flex-wrap gap-1.5">
          {WP_TAGS.map((tag) => {
            const isActive = activeTags.includes(tag);
            const isBlendActive = isBlending && isActive;
            return (
              <button
                key={tag}
                className="px-2.5 py-1 rounded-full font-mono uppercase cursor-pointer transition-all"
                style={{
                  fontSize: "var(--text-micro)",
                  letterSpacing: "var(--track-caps)",
                  backgroundColor: isActive
                    ? isBlendActive
                      ? "var(--overlay-w-12)"
                      : "var(--overlay-w-20)"
                    : "transparent",
                  color: isActive ? "var(--c-text)" : "var(--c-text-4)",
                  border: `1px solid ${isActive ? "var(--border-strong)" : "var(--border-subtle)"}`,
                  opacity: isBlendActive ? 0.85 : 1,
                }}
                onClick={() => handleTagClick(tag)}
              >
                {tag}
              </button>
            );
          })}
        </div>
      </div>

      {/* Blend indicator */}
      {isBlending && (
        <div
          className="font-mono uppercase text-center"
          style={{
            fontSize: "var(--text-micro)",
            letterSpacing: "var(--track-caps)",
            color: "var(--c-text-3)",
          }}
        >
          Blending: {activeTags[0]} + {activeTags[1]}
        </div>
      )}

      {/* Readout */}
      <div
        className="font-mono italic text-center leading-snug"
        style={{
          fontSize: "var(--text-badge)",
          color: "var(--c-text-3)",
          minHeight: "1.4em",
        }}
      >
        {readoutText}
      </div>

      {/* Drift / Blend slider */}
      <div>
        <div className="flex justify-between items-end mb-1">
          <span
            className="font-mono uppercase"
            style={{
              fontSize: "var(--text-label)",
              letterSpacing: "var(--track-caps)",
              color: "var(--c-text-2)",
            }}
          >
            {driftLabel}
          </span>
          <span
            className="font-mono tabular-nums px-1.5 py-0.5 rounded bg-surface-4"
            style={{ fontSize: "var(--text-badge)", color: "var(--c-text)" }}
          >
            {drift}
          </span>
        </div>
        <input
          type="range"
          min={0}
          max={100}
          step={1}
          value={drift}
          onChange={(e) => onDriftChange(+e.target.value)}
          className={SIDEBAR_SLIDER}
        />
      </div>

      {/* Color Variety */}
      <div>
        <div className="flex justify-between items-end mb-2">
          <span
            className="font-mono uppercase"
            style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}
          >
            Color Variety
          </span>
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

      {/* Accent Hue toggle */}
      <div>
        <button
          className="flex items-center gap-2 cursor-pointer"
          onClick={() => onAccentChange(!accent)}
        >
          <div
            className="w-3.5 h-3.5 rounded border flex items-center justify-center"
            style={{
              borderColor: accent ? "var(--c-text-2)" : "var(--c-text-4)",
              backgroundColor: accent ? "var(--overlay-w-12)" : "transparent",
            }}
          >
            {accent && (
              <svg width="8" height="8" viewBox="0 0 10 10" fill="none" stroke="var(--c-text-2)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="2,5.5 4.5,8 8,2.5" />
              </svg>
            )}
          </div>
          <span
            className="font-mono uppercase"
            style={{
              fontSize: "var(--text-badge)",
              letterSpacing: "var(--track-caps)",
              color: accent ? "var(--c-text-2)" : "var(--c-text-4)",
            }}
          >
            Accent Hue
          </span>
        </button>
        <div className="font-mono italic mt-1 ml-5.5" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
          Adds a complementary hue family to every 3rd card
        </div>
      </div>
    </div>
  );
}

// ── Bottom bar controls ──────────────────────────────────────────────

interface WPBottomControlsProps {
  activeTags: WPTagName[];
  drift: number;
  count: number;
}

export function WPBottomControls({ activeTags, drift, count }: WPBottomControlsProps) {
  const label = activeTags.length === 0
    ? "—"
    : activeTags.length === 1
      ? activeTags[0]
      : `${activeTags[0]} + ${activeTags[1]}`;

  return (
    <div className="flex items-center gap-4 bg-black/40 px-5 py-2 rounded-full border border-border-default shadow-inner">
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {label}
      </span>
      <div className="w-px h-3.5 bg-surface-4/80" />
      <span className="font-mono tabular-nums" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        Drift {drift}
      </span>
      <div className="w-px h-3.5 bg-surface-4/80" />
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {count} colors
      </span>
    </div>
  );
}
