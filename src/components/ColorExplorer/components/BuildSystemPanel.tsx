import { useState } from "react";
import { HexColorPicker } from "react-colorful";
import { oklchToCss, contrastRatio, hexToOklch } from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type { RoleTheme, RoleName, RoleOverrides, DerivedRoles } from "../types";
import { NODE_ORDER } from "../methods/rbLogic";
import { fontFamily } from "../../../lib/fontFace";
import type { FontInfo } from "../../../hooks/useFonts";
import type { CollectionItem } from "../useCollection";

// ── Role descriptions ─────────────────────────────────────────────────

const ROLE_SUBS: Record<RoleName, string> = {
  primary: "Core brand action",
  accent: "Highlights & alerts",
  surface: "Cards, sheets, menus",
  onSurface: "Text & icons on surface",
  error: "Destructive actions",
};

// ── Pairing preview definitions ───────────────────────────────────────

const PAIRINGS: { bg: RoleName; fg: RoleName; label: string }[] = [
  { bg: "surface", fg: "primary", label: "SURFACE / PRIMARY" },
  { bg: "surface", fg: "accent", label: "SURFACE / ACCENT" },
  { bg: "primary", fg: "onSurface", label: "PRIMARY / ON-SURFACE" },
  { bg: "surface", fg: "error", label: "SURFACE / ERROR" },
];

// ── Props ─────────────────────────────────────────────────────────────

interface BuildSystemPanelProps {
  roles: DerivedRoles;
  overrides: RoleOverrides;
  onOverrideChange: (role: RoleName, color: OklchColor) => void;
  onOverrideReset: (role: RoleName) => void;
  theme: RoleTheme;
  onThemeChange: (v: RoleTheme) => void;
  previewFont?: FontInfo | null;
  collectionItems?: CollectionItem[];
  onExportCSS?: () => void;
  onExportJSON?: () => void;
}

function contrastFg(bg: OklchColor): string {
  return bg.l > 0.6 ? "rgba(0,0,0,0.85)" : "rgba(255,255,255,0.9)";
}

// ── Component ─────────────────────────────────────────────────────────

export function BuildSystemPanel({
  roles,
  overrides,
  onOverrideChange,
  onOverrideReset,
  theme,
  onThemeChange,
  previewFont,
  collectionItems = [],
  onExportCSS,
  onExportJSON,
}: BuildSystemPanelProps) {
  const [editingSlot, setEditingSlot] = useState<RoleName | null>(null);
  const [pickingSlot, setPickingSlot] = useState<RoleName | null>(null);

  function roleState(key: RoleName): "LOCKED" | "AUTO" | "OVERRIDE" {
    if (key === "primary") return "LOCKED";
    if (overrides[key as keyof RoleOverrides] !== null) return "OVERRIDE";
    return "AUTO";
  }

  function handleNodeClick(key: RoleName) {
    if (key === "primary") return;
    setEditingSlot(editingSlot === key ? null : key);
  }

  function handleOverridePick(role: RoleName, hex: string) {
    onOverrideChange(role, hexToOklch(hex));
  }

  function roleHex(key: RoleName): string {
    const hexKey = `${key}Hex` as keyof DerivedRoles;
    return (roles[hexKey] as string) || "#000000";
  }

  return (
    <div className="flex flex-1 overflow-hidden">
      {/* ── Left: Role list ──────────────────────────────── */}
      <div className="w-[280px] bg-[#141414] border-r border-neutral-800 flex flex-col shrink-0 overflow-y-auto">
        <div className="p-4 flex flex-col flex-1">
          <div className="font-mono uppercase mb-4 px-1"
            style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>
            System Roles
          </div>

          <div className="flex flex-col gap-2 px-1">
            {NODE_ORDER.map(({ key, label }) => {
              const state = roleState(key);
              const color = roles[key];
              const colorCss = oklchToCss(color);
              const fg = contrastFg(color);
              const isEditing = editingSlot === key;
              const stateColor = state === "LOCKED" ? "var(--c-text-3)" : state === "OVERRIDE" ? "var(--c-accent)" : "#4ade80";

              return (
                <div key={key}>
                  <div
                    className="rounded-lg px-3 py-2.5 cursor-pointer relative select-none"
                    style={{
                      backgroundColor: colorCss,
                      color: fg,
                      boxShadow: isEditing ? "0 0 0 2px rgba(217,119,54,0.5)" : "0 1px 3px rgba(0,0,0,0.3)",
                    }}
                    onClick={() => handleNodeClick(key)}
                  >
                    <div className="flex items-center gap-2">
                      <span className="font-medium flex-1" style={{ fontSize: "var(--text-body)" }}>{label}</span>
                      <span className="font-mono uppercase shrink-0"
                        style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: stateColor }}>
                        {state}
                      </span>
                      {state === "OVERRIDE" && (
                        <button
                          className="w-4 h-4 rounded-full bg-neutral-800/60 flex items-center justify-center cursor-pointer hover:bg-neutral-700 transition-colors"
                          style={{ fontSize: 10, color: "var(--c-text-2)" }}
                          onClick={(e) => { e.stopPropagation(); onOverrideReset(key); setEditingSlot(null); }}
                        >×</button>
                      )}
                    </div>
                    <div className="mt-0.5" style={{ fontSize: "var(--text-badge)", opacity: 0.6 }}>
                      {ROLE_SUBS[key]}
                    </div>
                  </div>

                  {isEditing && state !== "LOCKED" && (
                    <div className="mt-1.5 mb-1">
                      <div className="compact-picker">
                        <HexColorPicker
                          color={roleHex(key)}
                          onChange={(hex) => handleOverridePick(key, hex)}
                          style={{ width: "100%" }}
                        />
                      </div>
                      {collectionItems.length > 0 && (
                        <div className="mt-1.5">
                          <button
                            className="w-full text-left font-mono uppercase cursor-pointer py-1"
                            style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}
                            onClick={(e) => { e.stopPropagation(); setPickingSlot(pickingSlot === key ? null : key); }}
                          >
                            {pickingSlot === key ? "▾ Close" : "▸ Pick from collection"}
                          </button>
                          {pickingSlot === key && (
                            <div className="flex flex-wrap gap-1.5 mt-1 max-h-32 overflow-y-auto">
                              {collectionItems.map((item) => (
                                <button
                                  key={item.id}
                                  className="w-7 h-7 rounded border border-neutral-700 cursor-pointer transition-transform hover:scale-110"
                                  style={{ backgroundColor: oklchToCss(item.bg) }}
                                  title={item.fontName}
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    onOverrideChange(key, item.bg);
                                    setPickingSlot(null);
                                  }}
                                />
                              ))}
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          <div className="mt-6 px-1">
            <div className="font-mono uppercase mb-2"
              style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>
              System Preview Controls
            </div>
            {/* Theme toggle */}
            <div className="flex rounded-md overflow-hidden border border-neutral-700">
              {(["light", "dark"] as const).map((t) => (
                <button key={t} className="flex-1 px-3 py-1 font-medium transition-colors capitalize cursor-pointer"
                  style={{ fontSize: "var(--text-body)", backgroundColor: theme === t ? "#404040" : "transparent", color: theme === t ? "var(--c-text)" : "var(--c-text-2)" }}
                  onClick={() => onThemeChange(t)}>{t}</button>
              ))}
            </div>
          </div>

          {/* Export buttons */}
          {(onExportCSS || onExportJSON) && (
            <div className="mt-4 px-1 flex flex-col gap-1.5">
              <div className="font-mono uppercase mb-1" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>
                Download
              </div>
              {onExportCSS && (
                <button className="w-full text-left px-3 py-1.5 rounded font-mono cursor-pointer transition-colors hover:bg-white/5"
                  style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)", border: "1px solid rgba(255,255,255,0.08)" }}
                  onClick={onExportCSS}>
                  CSS File
                </button>
              )}
              {onExportJSON && (
                <button className="w-full text-left px-3 py-1.5 rounded font-mono cursor-pointer transition-colors hover:bg-white/5"
                  style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)", border: "1px solid rgba(255,255,255,0.08)" }}
                  onClick={onExportJSON}>
                  JSON File
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      {/* ── Right: Pairing previews ──────────────────────── */}
      <div className="flex-1 min-w-0 overflow-y-auto p-8 bg-[#0A0A0A]">
        <div className="font-mono uppercase mb-4"
          style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>
          Pairing Previews
        </div>

        <div className="grid grid-cols-2 gap-6">
          {PAIRINGS.map(({ bg, fg, label }) => {
            const bgColor = roles[bg];
            const fgColor = roles[fg];
            const bgCss = oklchToCss(bgColor);
            const fgCss = oklchToCss(fgColor);
            const ratio = contrastRatio(bgColor, fgColor);
            const pass = ratio >= 4.5;

            return (
              <div
                key={label}
                className="rounded-xl p-6 flex flex-col justify-between shadow-lg"
                style={{ backgroundColor: bgCss, color: fgCss, aspectRatio: "4/3" }}
              >
                {/* Top row: pairing label + contrast badge */}
                <div className="flex justify-between items-start">
                  <div className="px-2 py-0.5 rounded font-mono backdrop-blur-sm border uppercase"
                    style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", background: "rgba(0,0,0,0.15)", borderColor: "rgba(0,0,0,0.05)" }}>
                    {label}
                  </div>
                  <div className="px-2 py-0.5 rounded font-mono backdrop-blur-sm border"
                    style={{ fontSize: "var(--text-badge)", background: "rgba(0,0,0,0.15)", borderColor: "rgba(0,0,0,0.05)", color: pass ? "#4ade80" : "rgba(239,68,68,0.45)" }}>
                    {ratio.toFixed(1)}:1
                  </div>
                </div>

                {/* Preview text */}
                <div>
                  <div className="text-[32px] font-semibold tracking-tight leading-tight truncate"
                    style={previewFont ? { fontFamily: fontFamily(previewFont.file_path) } : undefined}>
                    Heading
                  </div>
                  <div className="text-[18px] italic mt-1 truncate opacity-80"
                    style={previewFont ? { fontFamily: fontFamily(previewFont.file_path) } : undefined}>
                    Subheading text here
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
