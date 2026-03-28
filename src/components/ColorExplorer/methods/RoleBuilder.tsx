import { useState } from "react";
import { HexColorPicker } from "react-colorful";
import { oklchToCss } from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type { RoleTheme, RoleName, RoleOverrides, DerivedRoles } from "../types";
import {
  CONNECTORS,
  NODE_ORDER,
  hexToOklch,
} from "./rbLogic";

// Re-export generation functions for use in index.tsx
export { deriveRoles, rolePairings } from "./rbLogic";
export type { RoleName, RoleOverrides, DerivedRoles, RoleBuilderParams } from "./rbLogic";

// ── Helpers ───────────────────────────────────────────────────────────

const NODE_H = 36;

function contrastFg(bg: OklchColor): string {
  return bg.l > 0.6 ? "rgba(0,0,0,0.85)" : "rgba(255,255,255,0.9)";
}

// ── Sidebar ───────────────────────────────────────────────────────────

interface RBParamsProps {
  primaryHex: string;
  onPrimaryHexChange: (hex: string) => void;
  theme: RoleTheme;
  onThemeChange: (v: RoleTheme) => void;
  roles: DerivedRoles;
  overrides: RoleOverrides;
  onOverrideChange: (role: RoleName, color: OklchColor) => void;
  onOverrideReset: (role: RoleName) => void;
}

export function RBParams({
  primaryHex,
  onPrimaryHexChange,
  theme,
  onThemeChange,
  roles,
  overrides,
  onOverrideChange,
  onOverrideReset,
}: RBParamsProps) {
  const [hexInput, setHexInput] = useState(primaryHex);
  const [editingSlot, setEditingSlot] = useState<RoleName | null>(null);
  // Override hex values derived from roles — no local state that can drift
  const [pulsing, setPulsing] = useState<RoleName | null>(null);

  function commitPrimaryHex(raw: string) {
    const cleaned = raw.replace(/[^0-9a-fA-F]/g, "").slice(0, 6);
    if (cleaned.length === 6) { const hex = `#${cleaned}`; setHexInput(hex); onPrimaryHexChange(hex); }
  }

  function handlePickerPrimary(hex: string) { setHexInput(hex); onPrimaryHexChange(hex); }

  function handleOverridePick(role: RoleName, hex: string) {
    onOverrideChange(role, hexToOklch(hex));
  }

  function resetOverride(role: RoleName) {
    onOverrideReset(role);
    if (editingSlot === role) setEditingSlot(null);
  }

  function roleState(key: RoleName): "LOCKED" | "AUTO" | "OVERRIDE" {
    if (key === "primary") return "LOCKED";
    if (overrides[key as keyof RoleOverrides] !== null) return "OVERRIDE";
    return "AUTO";
  }

  function handleNodeClick(key: RoleName) {
    if (key === "primary") {
      setPulsing("primary");
      setTimeout(() => setPulsing(null), 200);
      return;
    }
    setEditingSlot(editingSlot === key ? null : key);
  }

  // Helper to get the current hex for a role — comes from DerivedRoles which pre-computes hexes
  function roleHex(key: RoleName): string {
    return roles[`${key}Hex` as keyof DerivedRoles] as string;
  }

  return (
    <>
      {/* Primary color picker */}
      <div>
        <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
          Primary Color
        </div>
        <div className="rounded-lg overflow-hidden mb-3">
          <HexColorPicker color={primaryHex} onChange={handlePickerPrimary} style={{ width: "100%" }} />
        </div>
        <div className="flex items-center gap-2">
          <div className="w-7 h-7 rounded border border-border-strong shrink-0" style={{ backgroundColor: primaryHex }} />
          <input className="flex-1 bg-surface-4 font-mono rounded px-2 py-1.5 outline-none placeholder:text-fg-3 focus:ring-1 focus:ring-border-strong uppercase"
            style={{ fontSize: "var(--text-body)", color: "var(--c-text)" }}
            value={hexInput} onChange={(e) => setHexInput(e.target.value)}
            onBlur={(e) => commitPrimaryHex(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") commitPrimaryHex(e.currentTarget.value); }}
            spellCheck={false} />
        </div>
      </div>

      {/* Theme toggle */}
      <div>
        <div className="font-mono uppercase mb-1" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>Theme</div>
        <div className="flex rounded-md overflow-hidden border border-border-strong">
          {(["light", "dark"] as const).map((t) => (
            <button key={t} className="flex-1 px-3 py-1 font-medium transition-colors capitalize cursor-pointer"
              style={{ fontSize: "var(--text-body)", backgroundColor: theme === t ? "var(--surface-active)" : "transparent", color: theme === t ? "var(--c-text)" : "var(--c-text-2)" }}
              onClick={() => onThemeChange(t)}>{t}</button>
          ))}
        </div>
      </div>

      {/* Patch bay */}
      <div>
        <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
          Role Derivation
        </div>

        <div className="flex flex-col gap-2">
          {NODE_ORDER.map(({ key, label }) => {
            const state = roleState(key);
            const color = roles[key];
            const colorCss = oklchToCss(color);
            const fg = contrastFg(color);
            const isEditing = editingSlot === key;
            const isPulsing = pulsing === key;
            const stateColor = state === "LOCKED" ? "var(--c-text-3)" : state === "OVERRIDE" ? "var(--c-accent)" : "var(--c-success)";

            const conn = CONNECTORS.find((c) => c.to === key);
            const connLabel = conn && state !== "OVERRIDE" ? conn.label : null;
            const connColor = conn ? oklchToCss(roles[conn.from]) : null;

            return (
              <div key={key}>
                {connLabel && (
                  <div className="flex items-center gap-1.5 mb-0.5 ml-3">
                    <div className="w-3 border-t" style={{ borderColor: connColor || "var(--c-text-4)", borderStyle: state === "OVERRIDE" ? "dashed" : key === "secondary" ? "dashed" : "solid", opacity: 0.4 }} />
                    <span className="font-mono" style={{ fontSize: 7, color: connColor || "var(--c-text-4)", opacity: 0.5 }}>{connLabel}</span>
                  </div>
                )}

                <div
                  className="rounded-lg px-3 flex items-center gap-2 cursor-pointer relative select-none"
                  style={{
                    height: NODE_H,
                    backgroundColor: colorCss,
                    color: fg,
                    transform: isPulsing ? "scale(1.03)" : "scale(1)",
                    transition: "transform var(--dur-micro) var(--ease-hover)",
                    boxShadow: isEditing ? "0 0 0 2px var(--accent-ring)" : "0 1px 3px rgba(0,0,0,0.3)",
                  }}
                  onClick={() => handleNodeClick(key)}
                >
                  <span className="font-medium flex-1 truncate" style={{ fontSize: "var(--text-body)" }}>{label}</span>
                  <span className="font-mono uppercase shrink-0" style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: stateColor }}>
                    {state}
                  </span>
                  {state === "LOCKED" && (
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke={fg} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0" style={{ opacity: 0.5 }}>
                      <rect x="3" y="11" width="18" height="11" rx="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />
                    </svg>
                  )}
                  {state === "OVERRIDE" && (
                    <button
                      className="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-surface-4 border border-border-strong flex items-center justify-center cursor-pointer hover:bg-surface-active transition-colors"
                      style={{ fontSize: 10, color: "var(--c-text-2)" }}
                      onClick={(e) => { e.stopPropagation(); resetOverride(key); }}
                    >×</button>
                  )}
                </div>

                {/* Color picker, opens inline in normal flow */}
                {isEditing && state !== "LOCKED" && (
                  <div className="mt-1.5 mb-1 compact-picker">
                    <HexColorPicker
                      color={roleHex(key)}
                      onChange={(hex) => handleOverridePick(key, hex)}
                      style={{ width: "100%" }}
                    />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </>
  );
}

// ── Bottom bar controls ───────────────────────────────────────────────

interface RBBottomControlsProps {
  accentOffset: number;
  onAccentOffsetChange: (v: number) => void;
  accentChromaMult: number;
  onAccentChromaMultChange: (v: number) => void;
}

export function RBBottomControls({
  accentOffset,
  onAccentOffsetChange,
  accentChromaMult,
  onAccentChromaMultChange,
}: RBBottomControlsProps) {
  return (
    <div className="flex items-center gap-6 bg-black/40 px-5 py-2 rounded-full border border-border-default shadow-inner">
      <div className="flex items-center gap-3 w-[200px]">
        <span className="text-[length:var(--text-badge)] font-mono text-fg-4 w-14 shrink-0">HUE Δ</span>
        <input type="range" min={0} max={360} value={accentOffset}
          onChange={(e) => onAccentOffsetChange(+e.target.value)}
          className="w-full" aria-label="Accent hue offset" aria-valuetext={`${accentOffset} degrees`} />
        <span className="text-[length:var(--text-label)] font-mono text-fg w-8 text-right shrink-0">{accentOffset}°</span>
      </div>

      <div className="w-px h-3.5 bg-border-default" />

      <div className="flex items-center gap-3 w-[180px]">
        <span className="text-[length:var(--text-badge)] font-mono text-fg-4 w-14 shrink-0">C MULT</span>
        <input type="range" min={0.2} max={1.2} step={0.05} value={accentChromaMult}
          onChange={(e) => onAccentChromaMultChange(+e.target.value)}
          className="w-full" aria-label="Accent chroma multiplier" aria-valuetext={`${accentChromaMult.toFixed(1)} times`} />
        <span className="text-[length:var(--text-label)] font-mono text-fg w-8 text-right shrink-0">{accentChromaMult.toFixed(1)}×</span>
      </div>
    </div>
  );
}
