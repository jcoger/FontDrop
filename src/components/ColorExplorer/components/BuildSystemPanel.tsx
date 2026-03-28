import { useState } from "react";
import { HexColorPicker } from "react-colorful";
import { oklchToCss, oklchToHex, contrastRatio, hexToOklch } from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type { RoleTheme, RoleName, RoleOverrides, RoleAssignments, DerivedRoles } from "../types";
// NODE_ORDER available for future use
// import { NODE_ORDER } from "../methods/rbLogic";
import { fontFamily } from "../../../lib/fontFace";
import type { FontInfo } from "../../../hooks/useFonts";
import type { CollectionItem } from "../useCollection";

// ── Supporting role definitions (excludes primary — it's the hero) ───

const SUPPORT_ROLES: { key: RoleName; label: string; description: string }[] = [
  { key: "secondary",  label: "Secondary",  description: "Accent color" },
  { key: "background", label: "Background", description: "Page tone" },
  { key: "text",       label: "Text",       description: "Body copy" },
  { key: "highlight",  label: "Highlight",  description: "Emphasis" },
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
  brandName?: string;
  collectionItems?: CollectionItem[];
  roleAssignments?: RoleAssignments;
  onRoleAssign?: (role: RoleName, itemId: string) => void;
  onRoleUnassign?: (role: RoleName) => void;
  onExportCSS?: () => void;
  onExportJSON?: () => void;
  onExportPrompt?: () => void;
  /** The exact card selected before opening Brand Kit */
  heroCard?: { bg: OklchColor; fg: OklchColor; fontName: string; fontWeight: string; fontPath?: string };
}

// ── Component ─────────────────────────────────────────────────────────

export function BuildSystemPanel({
  roles,
  onOverrideChange,
  theme,
  onThemeChange,
  previewFont,
  brandName = "",
  collectionItems = [],
  roleAssignments,
  onRoleAssign,
  onRoleUnassign,
  onExportCSS,
  onExportJSON,
  onExportPrompt,
  heroCard,
}: BuildSystemPanelProps) {
  const [editingRole, setEditingRole] = useState<RoleName | null>(null);
  const [pickingRole, setPickingRole] = useState<RoleName | null>(null);

  function assignedItem(key: RoleName): CollectionItem | null {
    const id = roleAssignments?.[key];
    if (!id) return null;
    return collectionItems.find((i) => i.id === id) || null;
  }

  // Hero card: use the directly-passed card data (bypasses collection timing)
  const hero = heroCard || (() => {
    const item = assignedItem("primary");
    return item ? { bg: item.bg, fg: item.fg, fontName: item.fontName, fontWeight: item.fontWeight, fontPath: undefined } : null;
  })();
  const primaryBg = hero ? oklchToCss(hero.bg) : oklchToCss(roles.primary);
  const primaryFg = hero ? oklchToCss(hero.fg) : (roles.primary.l > 0.55 ? "rgba(0,0,0,0.85)" : "rgba(255,255,255,0.9)");
  const primaryRatio = hero ? contrastRatio(hero.bg, hero.fg) : null;
  const displayText = brandName || hero?.fontName || "Brand";

  // Unassigned collection items
  const assignedIds = new Set(Object.values(roleAssignments || {}).filter(Boolean) as string[]);
  const unassignedItems = collectionItems.filter((i) => !assignedIds.has(i.id));

  function handlePickForRole(role: RoleName, itemId: string) {
    if (onRoleAssign) onRoleAssign(role, itemId);
    setPickingRole(null);
    setEditingRole(null);
  }

  return (
    <div className="flex flex-1 overflow-hidden">
      {/* ── Left: Sidebar controls ───────────────────────── */}
      <div className="w-[280px] bg-surface-1 border-r border-border-default flex flex-col shrink-0 overflow-y-auto">
        <div className="p-4 flex flex-col flex-1 gap-5">

          {/* Supporting roles */}
          <div>
            <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>
              Supporting Colors
            </div>
            <div className="flex flex-col gap-1.5">
              {SUPPORT_ROLES.map(({ key, label, description }) => {
                const item = assignedItem(key);
                const color = roles[key];
                const colorCss = oklchToCss(color);
                const isEditing = editingRole === key;
                const isFromCollection = !!item;

                return (
                  <div key={key}>
                    <div
                      className="flex items-center gap-2.5 px-2 py-1.5 rounded-lg cursor-pointer transition-colors hover:bg-white/5"
                      style={{ boxShadow: isEditing ? "0 0 0 1px var(--c-accent)" : undefined }}
                      onClick={() => setEditingRole(isEditing ? null : key)}
                    >
                      <div className="w-8 h-8 rounded shrink-0" style={{ backgroundColor: colorCss }}>
                        {item && (
                          <div className="w-full h-full flex items-center justify-center">
                            <span className="font-semibold truncate px-0.5" style={{ fontSize: 7, color: oklchToCss(item.fg) }}>Aa</span>
                          </div>
                        )}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-1.5">
                          <span className="font-medium truncate" style={{ fontSize: "var(--text-body)", color: "var(--c-text)" }}>{label}</span>
                          <span className="font-mono uppercase shrink-0" style={{ fontSize: 6, letterSpacing: "0.12em", color: isFromCollection ? "var(--c-accent)" : "var(--c-text-4)" }}>
                            {isFromCollection ? "SAVED" : "AUTO"}
                          </span>
                        </div>
                        <span className="font-mono truncate block" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
                          {item ? item.fontName : description}
                        </span>
                      </div>
                      {isFromCollection && (
                        <button
                          className="w-4 h-4 rounded-full bg-surface-4/60 flex items-center justify-center cursor-pointer hover:bg-surface-active transition-colors shrink-0"
                          style={{ fontSize: 10, color: "var(--c-text-2)" }}
                          onClick={(e) => { e.stopPropagation(); onRoleUnassign?.(key); setEditingRole(null); }}
                        >×</button>
                      )}
                    </div>

                    {/* Editing area */}
                    {isEditing && (
                      <div className="mt-1.5 mb-1 ml-10">
                        <div className="compact-picker mb-1.5">
                          <HexColorPicker
                            color={oklchToHex(color)}
                            onChange={(hex) => onOverrideChange(key, hexToOklch(hex))}
                            style={{ width: "100%" }}
                          />
                        </div>
                        {collectionItems.length > 0 && (
                          <div>
                            <button
                              className="w-full text-left font-mono uppercase cursor-pointer py-1"
                              style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}
                              onClick={(e) => { e.stopPropagation(); setPickingRole(pickingRole === key ? null : key); }}
                            >
                              {pickingRole === key ? "▾ Close" : "▸ Pick from saved"}
                            </button>
                            {pickingRole === key && (
                              <div className="flex flex-wrap gap-1.5 mt-1 max-h-28 overflow-y-auto">
                                {collectionItems.map((ci) => (
                                  <button
                                    key={ci.id}
                                    className="w-7 h-7 rounded border border-border-strong cursor-pointer transition-transform hover:scale-110"
                                    style={{ backgroundColor: oklchToCss(ci.bg) }}
                                    title={ci.fontName}
                                    onClick={(e) => { e.stopPropagation(); handlePickForRole(key, ci.id); }}
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
          </div>

          {/* Unassigned collection swatches */}
          {unassignedItems.length > 0 && (
            <div>
              <div className="font-mono uppercase mb-1.5" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>
                Available ({unassignedItems.length})
              </div>
              <div className="flex flex-wrap gap-1.5">
                {unassignedItems.map((item) => (
                  <div
                    key={item.id}
                    className="w-8 h-8 rounded border border-border-strong"
                    style={{ backgroundColor: oklchToCss(item.bg) }}
                    title={item.fontName}
                  />
                ))}
              </div>
            </div>
          )}

          {/* Theme toggle */}
          <div>
            <div className="font-mono uppercase mb-1.5" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>
              Theme
            </div>
            <div className="flex rounded-md overflow-hidden border border-border-strong">
              {(["light", "dark"] as const).map((t) => (
                <button key={t} className="flex-1 px-3 py-1 font-medium transition-colors capitalize cursor-pointer"
                  style={{ fontSize: "var(--text-body)", backgroundColor: theme === t ? "var(--surface-active)" : "transparent", color: theme === t ? "var(--c-text)" : "var(--c-text-2)" }}
                  onClick={() => onThemeChange(t)}>{t}</button>
              ))}
            </div>
          </div>

          {/* Export */}
          <div className="flex flex-col gap-1.5">
            <div className="font-mono uppercase mb-0.5" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>
              Export
            </div>
            {onExportCSS && (
              <button className="w-full text-left px-3 py-1.5 rounded font-mono cursor-pointer transition-colors hover:bg-white/5"
                style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)", border: "1px solid var(--border-subtle)" }}
                onClick={onExportCSS}>CSS File</button>
            )}
            {onExportJSON && (
              <button className="w-full text-left px-3 py-1.5 rounded font-mono cursor-pointer transition-colors hover:bg-white/5"
                style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)", border: "1px solid var(--border-subtle)" }}
                onClick={onExportJSON}>JSON File</button>
            )}
            {onExportPrompt && (
              <button className="w-full text-left px-3 py-1.5 rounded font-mono cursor-pointer transition-colors hover:bg-white/5"
                style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)", border: "1px solid var(--border-subtle)" }}
                onClick={onExportPrompt}>Copy Prompt</button>
            )}
          </div>
        </div>
      </div>

      {/* ── Right: Brand Kit Canvas ──────────────────────── */}
      <div className="flex-1 min-w-0 overflow-y-auto p-8 bg-surface-0">

        {/* ── Hero card: the primary pairing ────────────── */}
        <div
          className="rounded-2xl p-10 flex flex-col justify-between shadow-2xl mb-8"
          style={{ backgroundColor: primaryBg, color: primaryFg, minHeight: 280 }}
        >
          <div className="flex justify-between items-start">
            <span className="font-mono uppercase px-2.5 py-1 rounded backdrop-blur-sm border"
              style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", background: "rgba(0,0,0,0.12)", borderColor: "rgba(0,0,0,0.06)", color: primaryFg }}>
              Primary
            </span>
            {primaryRatio && (
              <span className="font-mono px-2.5 py-1 rounded backdrop-blur-sm border"
                style={{ fontSize: "var(--text-badge)", background: "rgba(0,0,0,0.12)", borderColor: "rgba(0,0,0,0.06)", color: primaryFg }}>
                {primaryRatio.toFixed(1)}:1
              </span>
            )}
          </div>
          <div>
            <div
              className="text-[52px] font-semibold tracking-tight leading-none truncate"
              style={hero?.fontPath ? { fontFamily: fontFamily(hero.fontPath) } : (previewFont ? { fontFamily: fontFamily(previewFont.file_path) } : undefined)}
            >
              {displayText}
            </div>
            {hero && (
              <div className="font-mono mt-2 opacity-60" style={{ fontSize: "var(--text-body)" }}>
                {hero.fontName} · {hero.fontWeight}
              </div>
            )}
          </div>
        </div>

        {/* ── Supporting color swatches ──────────────────── */}
        <div className="grid grid-cols-4 gap-4 mb-8">
          {SUPPORT_ROLES.map(({ key, label }) => {
            const item = assignedItem(key);
            const color = roles[key];
            const colorCss = oklchToCss(color);
            const fgCss = item ? oklchToCss(item.fg) : (color.l > 0.55 ? "rgba(0,0,0,0.75)" : "rgba(255,255,255,0.75)");

            return (
              <div key={key} className="rounded-xl overflow-hidden shadow-lg" style={{ backgroundColor: colorCss }}>
                <div className="p-4 flex flex-col gap-2" style={{ minHeight: 100 }}>
                  <span className="font-mono uppercase" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: fgCss, opacity: 0.6 }}>
                    {label}
                  </span>
                  <span className="text-[20px] font-semibold tracking-tight truncate" style={{ color: fgCss }}>
                    {item ? displayText : "Aa"}
                  </span>
                  <span className="font-mono mt-auto" style={{ fontSize: "var(--text-badge)", color: fgCss, opacity: 0.5 }}>
                    {oklchToHex(color)}
                  </span>
                </div>
              </div>
            );
          })}
        </div>

        {/* ── Combo previews: how they work together ───── */}
        <div className="font-mono uppercase mb-3" style={{ fontSize: "var(--text-micro)", letterSpacing: "0.12em", color: "var(--c-text-4)" }}>
          Combinations
        </div>
        <div className="grid grid-cols-2 gap-4">
          {/* Brand name on background */}
          <div className="rounded-xl p-6 shadow-lg" style={{ backgroundColor: oklchToCss(roles.background), minHeight: 120 }}>
            <span className="font-mono uppercase mb-2 block" style={{ fontSize: 6, letterSpacing: "0.12em", color: "var(--c-text-4)" }}>Brand on Background</span>
            <span className="text-[28px] font-semibold tracking-tight truncate block" style={{ color: primaryBg }}>
              {displayText}
            </span>
          </div>
          {/* Highlight on primary */}
          <div className="rounded-xl p-6 shadow-lg" style={{ backgroundColor: primaryBg, minHeight: 120 }}>
            <span className="font-mono uppercase mb-2 block" style={{ fontSize: 6, letterSpacing: "0.12em", color: primaryFg, opacity: 0.5 }}>Highlight on Primary</span>
            <span className="text-[28px] font-semibold tracking-tight truncate block" style={{ color: oklchToCss(roles.highlight) }}>
              {displayText}
            </span>
          </div>
          {/* Secondary on background */}
          <div className="rounded-xl p-6 shadow-lg" style={{ backgroundColor: oklchToCss(roles.background), minHeight: 120 }}>
            <span className="font-mono uppercase mb-2 block" style={{ fontSize: 6, letterSpacing: "0.12em", color: "var(--c-text-4)" }}>Secondary on Background</span>
            <span className="text-[28px] font-semibold tracking-tight truncate block" style={{ color: oklchToCss(roles.secondary) }}>
              {displayText}
            </span>
          </div>
          {/* Text on background */}
          <div className="rounded-xl p-6 shadow-lg" style={{ backgroundColor: oklchToCss(roles.background), minHeight: 120 }}>
            <span className="font-mono uppercase mb-2 block" style={{ fontSize: 6, letterSpacing: "0.12em", color: "var(--c-text-4)" }}>Text on Background</span>
            <span className="text-[18px] tracking-tight leading-relaxed block" style={{ color: oklchToCss(roles.text) }}>
              The quick brown fox jumps over the lazy dog. Typography is the craft of endowing human language with a durable visual form.
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
