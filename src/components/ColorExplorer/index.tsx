import { useState, useMemo, useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { dur, easeOut } from "../../lib/motion";
import type { FontInfo } from "../../hooks/useFonts";
import { oklchToCss, oklchToHex, contrastRatio, hexToOklch } from "../../utils/oklch";
import type { OklchColor } from "../../utils/oklch";

import { useColorExplorerState } from "./useColorExplorerState";
import { useCollection } from "./useCollection";
import type { RampColor, ContrastRampColor, ColorVariety } from "./types";

// Generation functions
import { sampleToneCurve } from "./methods/hueLock";
import { applyExtractTransforms, buildExtractRamp } from "./methods/extractColors";

// Method UI — sidebar params + re-exported generation functions
import { HLParams, HLBottomControls, generateHueMode, hlFlipCard, hlContrastRange } from "./methods/HLParams";
import type { HLRampColor } from "./methods/HLParams";
import { TCParams, TCBottomControls, generateDualCorridor } from "./methods/TemperatureCorridor";
import { generateContrastSafe } from "./methods/ContrastSafe";
import { RBBottomControls, deriveRoles, rolePairings, proposeRoles } from "./methods/RoleBuilder";
import { EXParams, EXBottomControls } from "./methods/Extract";
import { WPParams, WPBottomControls, generateWordPicker } from "./methods/WordPicker";
import type { WPRampColor } from "./methods/WordPicker";
import { MKParams, MKBottomControls, generateMacroKnob, flipCard } from "./methods/MacroKnob";
import type { MKRampColor } from "./methods/MacroKnob";

// Shared components
import { ColorCard } from "./components/ColorCard";
import { AlbersPanel } from "./components/AlbersPanel";
import { MethodSidebar } from "./components/MethodSidebar";
import { BottomBar } from "./components/BottomBar";
import { MethodBar } from "./components/MethodBar";
import { HudBar } from "./components/HudBar";
import { BuildSystemPanel } from "./components/BuildSystemPanel";
import { PaletteHistoryStrip } from "./components/PaletteHistoryStrip";
import type { HistoryEntry } from "./components/PaletteHistoryStrip";
import { HubPanel } from "./components/HubPanel";
import { exportSystemCSS, exportSystemJSON, downloadFile, todayStr } from "./exportUtils";

// ── Constants ─────────────────────────────────────────────────────────

const CANVAS_COLOR = hexToOklch("#0A0A0A");

// ── Props ─────────────────────────────────────────────────────────────

interface ColorExplorerProps {
  fonts: FontInfo[];
  starred: Set<string>;
  logoSvg?: string | null;
  brandName?: string;
  exportRef?: React.MutableRefObject<(() => void) | null>;
  onSwitchToGrid?: () => void;
}

// ── Component ─────────────────────────────────────────────────────────

export function ColorExplorer({
  fonts,
  starred: starredPaths,
  logoSvg,
  brandName = "",
  exportRef,
  onSwitchToGrid,
}: ColorExplorerProps) {
  const s = useColorExplorerState();
  const collection = useCollection();

  // ── Toast ───────────────────────────────────────────────────────
  const [toast, setToast] = useState<string | null>(null);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2000);
    return () => clearTimeout(t);
  }, [toast]);

  // ── Build System mode ───────────────────────────────────────────
  const [buildSystemOpen, setBuildSystemOpen] = useState(false);
  const [heroCard, setHeroCard] = useState<{ bg: OklchColor; fg: OklchColor; fontName: string; fontWeight: string; fontPath?: string } | undefined>();

  function openBuildSystem() {
    // Find the card the user selected (spotlight or working color)
    const spotCard = spotlightColorKey !== null
      ? cards.find((c) => colorKey(c.rampColor.color, c.fgOklch) === spotlightColorKey)
      : null;
    const selectedCard = spotCard || cards.find((c) => c.rampIdx === effectiveWorkingIndex);

    if (selectedCard) {
      const bg = selectedCard.rampColor.color;
      const fg = selectedCard.fgOklch;
      const font = selectedCard.font;

      // Capture the exact card for the hero display
      setHeroCard({
        bg,
        fg,
        fontName: font?.font_family || "",
        fontWeight: String(font?.weight || ""),
        fontPath: font?.file_path,
      });

      // Set primary color from the selected card
      s.handleRbPrimaryHex(oklchToHex(bg));

      // Auto-save to collection (returns existing ID if duplicate)
      const { id: itemId } = collection.addItem({
        bg,
        fg,
        fontName: font?.font_family || "",
        fontWeight: String(font?.weight || ""),
        fontCategory: font?.classification?.category || "",
        sourceMode: s.activeMethod,
      });

      // Assign as PRIMARY, propose remaining roles from collection
      if (itemId) {
        setTimeout(() => {
          s.setRoleAssignments(() => {
            const assignments = proposeRoles(collection.items);
            assignments.primary = itemId;
            return assignments;
          });
        }, 0);
      }
    }

    setBuildSystemOpen(true);
  }

  function closeBuildSystem() {
    setBuildSystemOpen(false);
    setHeroCard(undefined);
  }

  // ── Hub mode ──────────────────────────────────────────────────
  const [hubOpen, setHubOpen] = useState(false);

  function openHub() { setHubOpen(true); setBuildSystemOpen(false); }
  function closeHub() { setHubOpen(false); }

  function handleSendToBuildSystem(item: import("./useCollection").CollectionItem) {
    closeHub();
    setHeroCard({
      bg: item.bg,
      fg: item.fg,
      fontName: item.fontName,
      fontWeight: item.fontWeight,
      fontPath: undefined,
    });
    s.handleRbPrimaryHex(oklchToHex(item.bg));
    const assignments = proposeRoles(collection.items);
    assignments.primary = item.id;
    s.setRoleAssignments(assignments);
    setBuildSystemOpen(true);
  }

  // Resolve role assignments against collection → build overrides
  const resolvedOverrides = useMemo((): import("./types").RoleOverrides => {
    const base = { ...s.rbOverrides };
    const roles: (keyof import("./types").RoleOverrides)[] = ["background", "text", "secondary", "highlight"];
    for (const role of roles) {
      const itemId = s.roleAssignments[role];
      if (itemId) {
        const item = collection.items.find((i) => i.id === itemId);
        if (item) base[role] = item.bg;
        else { /* item deleted — clear assignment */ }
      }
    }
    // Also handle primary from assignment
    const primaryId = s.roleAssignments.primary;
    if (primaryId) {
      const item = collection.items.find((i) => i.id === primaryId);
      if (item) s.handleRbPrimaryHex(oklchToHex(item.bg));
    }
    return base;
  }, [s.rbOverrides, s.roleAssignments, collection.items]);

  // Brand Kit roles — derived when panel is open
  const bsRoles = useMemo(() => {
    if (!buildSystemOpen) return null;
    return deriveRoles({
      primary: s.rbPrimary,
      theme: s.rbTheme,
      accentOffset: s.rbAccentOffset,
      accentChromaMult: s.rbAccentChromaMult,
      overrides: resolvedOverrides,
    });
  }, [buildSystemOpen, s.rbPrimary, s.rbTheme, s.rbAccentOffset, s.rbAccentChromaMult, resolvedOverrides]);

  // Export System — CSS file download
  const handleExportSystemCSS = useCallback(() => {
    if (!bsRoles) return;
    const roleExports = [
      { key: "primary", name: "Primary", bg: bsRoles.primary },
      { key: "secondary", name: "Secondary", bg: bsRoles.secondary },
      { key: "background", name: "Background", bg: bsRoles.background },
      { key: "text", name: "Text", bg: bsRoles.text },
      { key: "highlight", name: "Highlight", bg: bsRoles.highlight },
    ];
    downloadFile(`fontdrop-brand-kit-${todayStr()}.css`, exportSystemCSS(roleExports), "text/css");
    setToast("CSS downloaded");
  }, [bsRoles]);

  // Export Brand Kit — JSON file download
  const handleExportSystemJSON = useCallback(() => {
    if (!bsRoles) return;
    const roleExports = [
      { key: "primary", name: "Primary", bg: bsRoles.primary },
      { key: "secondary", name: "Secondary", bg: bsRoles.secondary },
      { key: "background", name: "Background", bg: bsRoles.background },
      { key: "text", name: "Text", bg: bsRoles.text },
      { key: "highlight", name: "Highlight", bg: bsRoles.highlight },
    ];
    downloadFile(`fontdrop-brand-kit-${todayStr()}.json`, exportSystemJSON(roleExports));
    setToast("JSON downloaded");
  }, [bsRoles]);

  // Clipboard export (used by the export ref)
  const handleExportSystem = useCallback(() => {
    if (!bsRoles) return;
    const roles = [
      { name: "Primary", key: "primary", hex: bsRoles.primaryHex, color: bsRoles.primary },
      { name: "Secondary", key: "secondary", hex: bsRoles.secondaryHex, color: bsRoles.secondary },
      { name: "Background", key: "background", hex: bsRoles.backgroundHex, color: bsRoles.background },
      { name: "Text", key: "text", hex: bsRoles.textHex, color: bsRoles.text },
      { name: "Highlight", key: "highlight", hex: bsRoles.highlightHex, color: bsRoles.highlight },
    ];
    const lines: string[] = [];
    lines.push(`Brand Kit — ${bsRoles.primaryHex}`);
    lines.push("FontDrop Brand Kit\n");
    lines.push("Roles:");
    roles.forEach((r) => {
      const { l, c, h } = r.color;
      lines.push(`  ${r.name}: ${r.hex}  oklch(${l.toFixed(2)}, ${c.toFixed(3)}, ${Math.round(h)})`);
    });
    lines.push("\nCSS Custom Properties:");
    lines.push(":root {");
    roles.forEach((r) => lines.push(`  --color-${r.key}: ${r.hex};`));
    lines.push("}");
    navigator.clipboard.writeText(lines.join("\n"));
    setToast("Copied to clipboard");
  }, [bsRoles]);

  // Export Brand Kit — Copy Prompt for AI tools
  const handleExportPrompt = useCallback(() => {
    if (!bsRoles) return;
    const roleNames: { key: import("./types").RoleName; name: string }[] = [
      { key: "primary", name: "Primary" },
      { key: "secondary", name: "Secondary" },
      { key: "background", name: "Background" },
      { key: "text", name: "Text" },
      { key: "highlight", name: "Highlight" },
    ];
    const lines: string[] = [];
    lines.push(`Brand Kit for ${brandName || "Untitled"}\n`);
    for (const r of roleNames) {
      const bg = bsRoles[r.key];
      const item = collection.items.find((i) => i.id === s.roleAssignments[r.key]);
      const bgHex = oklchToHex(bg);
      const bgOklch = `oklch(${bg.l.toFixed(2)}, ${bg.c.toFixed(3)}, ${Math.round(bg.h)})`;
      let line = `${r.name}: bg ${bgHex} (${bgOklch})`;
      if (item) {
        const fgHex = oklchToHex(item.fg);
        line += ` + fg ${fgHex}`;
        if (item.fontName) line += ` · Font: ${item.fontName} ${item.fontWeight}`;
      }
      lines.push(line);
    }
    lines.push(`\nGenerated by FontDrop · Display-P3 gamut`);
    navigator.clipboard.writeText(lines.join("\n"));
    setToast("Prompt copied");
  }, [bsRoles, collection.items, s.roleAssignments, brandName]);

  // ── Card pulse ──────────────────────────────────────────────────
  const [pulsingIdx, setPulsingIdx] = useState<number | null>(null);
  useEffect(() => {
    if (pulsingIdx === null) return;
    const t = setTimeout(() => setPulsingIdx(null), 150);
    return () => clearTimeout(t);
  }, [pulsingIdx]);

  // ── Spotlight (color-identity based) ────────────────────────────
  function colorKey(bg: OklchColor, fg: OklchColor): string {
    return `${bg.l.toFixed(2)}.${bg.c.toFixed(2)}.${Math.round(bg.h)}|${fg.l.toFixed(2)}.${fg.c.toFixed(2)}.${Math.round(fg.h)}`;
  }

  const [spotlightColorKey, setSpotlightColorKey] = useState<string | null>(() =>
    localStorage.getItem("fontdrop-spotlight-key"),
  );
  const [spotlightFontPath, setSpotlightFontPath] = useState<string | null>(() =>
    localStorage.getItem("fontdrop-spotlight-font"),
  );
  useEffect(() => {
    if (spotlightColorKey) localStorage.setItem("fontdrop-spotlight-key", spotlightColorKey);
    else localStorage.removeItem("fontdrop-spotlight-key");
  }, [spotlightColorKey]);
  useEffect(() => {
    if (spotlightFontPath) localStorage.setItem("fontdrop-spotlight-font", spotlightFontPath);
    else localStorage.removeItem("fontdrop-spotlight-font");
  }, [spotlightFontPath]);
  // Clear spotlight on mode switch
  useEffect(() => { setSpotlightColorKey(null); }, [s.activeMethod]);

  function handlePinFont(font: FontInfo | null) {
    setSpotlightFontPath(font ? font.file_path : null);
  }

  // ── Starred fonts (passed from App as live prop) ────────────────
  const starredFonts = useMemo(() => fonts.filter((f) => starredPaths.has(f.file_path)), [fonts, starredPaths]);
  const displayFonts = starredFonts.length > 0 ? starredFonts : fonts.slice(0, 12);
  const hasStarred = starredFonts.length > 0;

  // ── Active font count: ground truth for card grid size ─────────
  // Cards = displayFonts.length + (logoSvg ? 1 : 0).
  // Color generation should match this to avoid silent waste or modulo repeats.
  const activeFontCount = displayFonts.length + (logoSvg ? 1 : 0);

  /** Resolve a ColorVariety setting to an actual generation count. */
  function resolveVariety(variety: ColorVariety): number {
    switch (variety) {
      case "tight": return Math.max(4, Math.ceil(activeFontCount / 2));
      case "auto":  return activeFontCount;
      case "wide":  return Math.min(24, activeFontCount * 2);
    }
  }

  // ── Role Builder derived roles ───────────────────────────────────
  const rbRoles = useMemo(() => {
    if (s.activeMethod !== "Role Builder") return null;
    return deriveRoles({
      primary: s.rbPrimary,
      theme: s.rbTheme,
      accentOffset: s.rbAccentOffset,
      accentChromaMult: s.rbAccentChromaMult,
      overrides: s.rbOverrides,
    });
  }, [s.activeMethod, s.rbPrimary, s.rbTheme, s.rbAccentOffset, s.rbAccentChromaMult, s.rbOverrides]);

  // ── Ramp generation ──────────────────────────────────────────────
  const ramp = useMemo((): RampColor[] => {
    if (s.activeMethod === "Macro Knob")
      return generateMacroKnob(s.mkKnob, s.mkHue, activeFontCount, s.mkSpread, s.mkVariMode, s.mkRelMode, s.contrastLevel);
    if (s.activeMethod === "Word Picker")
      return generateWordPicker(s.wpTags as [] | [any] | [any, any], s.wpDrift, resolveVariety(s.wpVariety), s.wpAccent, s.contrastLevel);
    if (s.activeMethod === "Extract")
      return buildExtractRamp(applyExtractTransforms(s.exRawClusters, s.exRemapEnabled, s.exLightnessLock, s.exLockedL));
    if (s.activeMethod === "Role Builder" && rbRoles)
      return rolePairings(rbRoles);
    if (s.activeMethod === "Temperature Corridor") {
      const tcGenCount = resolveVariety(s.tcVariety);
      const accentCeil = Math.max(0, Math.min(1, s.tcChromaCeiling2 + s.tcAccentChromaOffset / 100));
      const h2 = ((s.tcHCenter + s.tcHueOffset) % 360 + 360) % 360;
      return generateDualCorridor({
        node1: { hCenter: s.tcHCenter, tempWidth: s.tcHueWidth, chromaMin: s.tcChromaFloor, chromaMax: s.tcChromaCeiling, lRange: s.lRange, count: tcGenCount, useRelativeChroma: true, lMidBias: s.tcLMidBias },
        node2: { hCenter: h2, tempWidth: s.tcHueWidth, chromaMin: s.tcChromaFloor, chromaMax: accentCeil, lRange: s.lRange, count: tcGenCount, useRelativeChroma: true, lMidBias: s.tcLMidBias },
        accentWeight: s.tcAccentWeight,
      });
    }
    if (s.activeMethod === "Contrast Safe")
      return generateContrastSafe({ primary: s.csPrimary, lRange: s.csLRange, cRange: s.csCRange, hueMode: s.csHueMode, threshold: s.csThreshold, density: s.csDensity, fgLock: s.csFgLock });
    const hlCount = resolveVariety(s.hlVariety);
    const lValues = sampleToneCurve(hlCount, s.curveMidY);
    return generateHueMode({ hue: s.hue, steps: hlCount, chromaMode: s.chromaMode, fixedChroma: s.fixedChroma, lValues, fgPreset: s.hlFgPreset, fgLOverride: s.hlFgLOverride, fgCOverride: s.hlFgCOverride, contrastLevel: s.contrastLevel, isClash: s.contrastLevel === "clash" });
  }, [s.activeMethod, s.hue, s.steps, s.chromaMode, s.fixedChroma, s.accentEnabled, s.accentHue, s.accentL, s.curveMidY, s.hlFgPreset, s.hlFgLOverride, s.hlFgCOverride, s.hlVariety, s.tcHCenter, s.tcHueWidth, s.tcChromaFloor, s.tcChromaCeiling, s.lRange, s.tcCount, s.tcLMidBias, s.tcHueOffset, s.tcChromaCeiling2, s.tcAccentWeight, s.tcAccentChromaOffset, s.csPrimary, s.csLRange, s.csCRange, s.csHueMode, s.csThreshold, s.csDensity, s.csFgLock, rbRoles, s.exRawClusters, s.exRemapEnabled, s.exLightnessLock, s.exLockedL, s.wpTags, s.wpDrift, s.wpCount, s.wpVariety, s.wpAccent, s.mkKnob, s.mkHue, s.mkSpread, s.mkVariMode, s.mkRelMode, s.contrastLevel, s.tcVariety, activeFontCount]);

  const sortedRamp = useMemo(
    () => s.activeMethod === "Role Builder" ? ramp : [...ramp].sort((a, b) => a.color.l - b.color.l),
    [ramp, s.activeMethod],
  );

  // ── Card flip state (Macro Knob only, not persisted) ────────────
  const [flippedCards, setFlippedCards] = useState<Set<number>>(new Set());
  // Only reset flips when switching methods, not on every knob turn
  useEffect(() => { setFlippedCards(new Set()); }, [s.activeMethod]);

  function handleFlip(cardIndex: number) {
    setFlippedCards((prev) => {
      const next = new Set(prev);
      if (next.has(cardIndex)) next.delete(cardIndex);
      else next.add(cardIndex);
      return next;
    });
  }

  const effectiveWorkingIndex =
    s.workingColorIndex !== null && s.workingColorIndex < sortedRamp.length
      ? s.workingColorIndex
      : Math.floor(sortedRamp.length / 2);
  const workingColor: OklchColor = sortedRamp[effectiveWorkingIndex]?.color || { mode: "oklch", l: 0.5, c: 0.1, h: 270 };
  useEffect(() => { s.setWorkingColorIndex(null); }, [sortedRamp.length]);

  // Spotlight is color-key based — no position boundary check needed

  // Resolve pinned font
  const pinnedFont = useMemo(() => {
    if (!spotlightFontPath) return null;
    return fonts.find((f) => f.file_path === spotlightFontPath) || null;
  }, [spotlightFontPath, fonts]);

  // ── Foreground logic ─────────────────────────────────────────────
  function hlForeground(bg: OklchColor, palette: RampColor[]): string {
    let best = 0, css = "#ffffff";
    for (const rc of palette) { const r = contrastRatio(bg, rc.color); if (r > best) { best = r; css = oklchToCss(rc.color); } }
    return css;
  }
  const tcDarkest = useMemo(() => sortedRamp.length ? oklchToCss(sortedRamp[0].color) : "#000000", [sortedRamp]);
  const tcLightest = useMemo(() => sortedRamp.length ? oklchToCss(sortedRamp[sortedRamp.length - 1].color) : "#ffffff", [sortedRamp]);
  function tcForeground(bg: OklchColor) { return bg.l > 0.5 ? tcDarkest : tcLightest; }

  // ── Cards ────────────────────────────────────────────────────────
  const primaryCss = useMemo(() => oklchToCss(s.csPrimary), [s.csPrimary]);

  interface CardEntry { font: FontInfo | null; rampColor: RampColor; rampIdx: number; fgColor: string; fgOklch: OklchColor; dimmed: boolean; badgeColor: string | undefined; isLogoCard: boolean; }

  const cards = useMemo((): CardEntry[] => {
    if (sortedRamp.length === 0) return [];
    const isCs = s.activeMethod === "Contrast Safe";
    const isTc = s.activeMethod === "Temperature Corridor" || s.activeMethod === "Word Picker" || s.activeMethod === "Macro Knob";
    const isRb = s.activeMethod === "Role Builder";

    // Find the OklchColor that produced a given CSS string from the ramp
    function fgOklchFor(css: string, palette: RampColor[]): OklchColor {
      for (const rc of palette) { if (oklchToCss(rc.color) === css) return rc.color; }
      return { mode: "oklch", l: css === tcDarkest ? 0 : 1, c: 0, h: 0 };
    }

    function build(font: FontInfo | null, i: number, isLogo: boolean): CardEntry {
      const rampIdx = i % sortedRamp.length, rc = sortedRamp[rampIdx];
      if (isRb && rc.fgCss) {
        const fgO = fgOklchFor(rc.fgCss, sortedRamp);
        return { font, rampColor: rc, rampIdx, fgColor: rc.fgCss, fgOklch: fgO, dimmed: false, badgeColor: undefined, isLogoCard: isLogo };
      }
      if (isCs) {
        const csrc = rc as ContrastRampColor, testCss = oklchToCss(csrc.color);
        const bgC = s.csFgLock ? csrc.color : s.csPrimary;
        const fgC = s.csFgLock ? primaryCss : testCss;
        const fgO = s.csFgLock ? s.csPrimary : csrc.color;
        const bc: Record<string, string> = { AAA: "var(--c-success)", AA: "var(--c-warning)", "AA-large": "var(--c-caution)", FAIL: "var(--c-error)" };
        return { font, rampColor: { ...rc, color: bgC }, rampIdx, fgColor: fgC, fgOklch: fgO, dimmed: !(csrc as ContrastRampColor).passes, badgeColor: bc[(csrc as ContrastRampColor).badge.split(" ")[0]] || fgC, isLogoCard: isLogo };
      }
      if (isTc) {
        // Macro Knob: use mkFg from generation
        if (s.activeMethod === "Macro Knob") {
          const mkRc = rc as MKRampColor;
          if (mkRc.mkFg) {
            const fgCss = oklchToCss(mkRc.mkFg);
            return { font, rampColor: rc, rampIdx, fgColor: fgCss, fgOklch: mkRc.mkFg, dimmed: false, badgeColor: undefined, isLogoCard: isLogo };
          }
        }
        // Word Picker: use wpFg from generation
        if (s.activeMethod === "Word Picker") {
          const wpRc = rc as WPRampColor;
          if (wpRc.wpFg) {
            const fgCss = oklchToCss(wpRc.wpFg);
            return { font, rampColor: rc, rampIdx, fgColor: fgCss, fgOklch: wpRc.wpFg, dimmed: false, badgeColor: undefined, isLogoCard: isLogo };
          }
        }
        const fgCss = tcForeground(rc.color);
        const fgO = fgCss === tcDarkest && sortedRamp.length ? sortedRamp[0].color : sortedRamp.length ? sortedRamp[sortedRamp.length - 1].color : rc.color;
        return { font, rampColor: rc, rampIdx, fgColor: fgCss, fgOklch: fgO, dimmed: false, badgeColor: undefined, isLogoCard: isLogo };
      }
      // Hue Lock: use hlFg from generation
      if (s.activeMethod === "Hue Lock") {
        const hlRc = rc as HLRampColor;
        if (hlRc.hlFg) {
          const fgCss = oklchToCss(hlRc.hlFg);
          return { font, rampColor: rc, rampIdx, fgColor: fgCss, fgOklch: hlRc.hlFg, dimmed: false, badgeColor: undefined, isLogoCard: isLogo };
        }
      }
      // Extract default: hlForeground picks highest-contrast ramp color
      const fgCss = hlForeground(rc.color, sortedRamp);
      const fgO = fgOklchFor(fgCss, sortedRamp);
      return { font, rampColor: rc, rampIdx, fgColor: fgCss, fgOklch: fgO, dimmed: false, badgeColor: undefined, isLogoCard: isLogo };
    }
    const r: CardEntry[] = [];
    if (logoSvg) r.push(build(null, 0, true));
    const off = logoSvg ? 1 : 0;
    for (let i = 0; i < displayFonts.length; i++) r.push(build(displayFonts[i], i + off, false));
    return r;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [displayFonts, sortedRamp, s.activeMethod, tcDarkest, tcLightest, s.csPrimary, primaryCss, s.csFgLock, logoSvg, s.contrastLevel]);

  // ── Export Palette ───────────────────────────────────────────────
  const handleExport = useCallback(() => {
    const seen = new Set<string>();
    const unique = sortedRamp.filter((rc) => { const h = oklchToHex(rc.color); if (seen.has(h)) return false; seen.add(h); return true; });
    if (unique.length === 0) { setToast("No colors to export"); return; }
    const lines: string[] = [];
    lines.push(`Brand Color Palette — ${s.activeMethod}`);
    lines.push("Generated with FontDrop Color Explorer\n");
    lines.push("Colors:");
    unique.forEach((rc, i) => {
      const hex = oklchToHex(rc.color);
      const { l, c, h } = rc.color;
      lines.push(`  ${i + 1}. ${hex}  oklch(${l.toFixed(2)}, ${c.toFixed(3)}, ${Math.round(h)})  ${rc.badge}`);
    });
    lines.push("\nCSS Custom Properties:");
    lines.push(":root {");
    unique.forEach((rc, i) => lines.push(`  --color-${i + 1}: ${oklchToHex(rc.color)};`));
    lines.push("}");
    lines.push("\nTailwind Config:");
    lines.push("colors: {");
    lines.push("  brand: {");
    unique.forEach((rc, i) => lines.push(`    ${i + 1}: '${oklchToHex(rc.color)}',`));
    lines.push("  },");
    lines.push("}");
    navigator.clipboard.writeText(lines.join("\n"));
    setToast("Palette copied to clipboard");
  }, [sortedRamp, s.activeMethod]);

  // Export ref switches between palette export and system export
  const activeExport = buildSystemOpen ? handleExportSystem : handleExport;
  useEffect(() => {
    if (exportRef) exportRef.current = activeExport;
    return () => { if (exportRef) exportRef.current = null; };
  }, [exportRef, activeExport]);

  // ── Arrow-key hue nudge ──────────────────────────────────────────
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (s.activeMethod === "Hue Lock" && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
        e.preventDefault();
        const delta = (e.key === "ArrowRight" ? 1 : -1) * (e.shiftKey ? 10 : 1);
        s.setHue((h) => ((h + delta) % 360 + 360) % 360);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [s.activeMethod]);

  // Method crossfade handled by AnimatePresence on the card grid

  function handleCardClick(rampIdx: number) {
    s.setWorkingColorIndex(rampIdx);
    setPulsingIdx(rampIdx);
  }

  // ── Working card info for HUD (spotlight preferred) ─────────────
  const workingCard = useMemo(() => {
    if (cards.length === 0) return null;
    // Prefer spotlight card (by color key) for the HUD readout
    const spotCard = spotlightColorKey !== null
      ? cards.find((c) => colorKey(c.rampColor.color, c.fgOklch) === spotlightColorKey)
      : null;
    const card = spotCard || cards.find((c) => c.rampIdx === effectiveWorkingIndex);
    if (!card) return null;
    const renderFont = (spotCard && pinnedFont) ? pinnedFont : card.font;
    return {
      badge: card.rampColor.badge,
      fontName: card.isLogoCard ? "Logo" : renderFont?.font_family || "",
      bgColor: card.rampColor.color,
      fgColor: card.fgColor,
    };
  }, [cards, effectiveWorkingIndex, spotlightColorKey, pinnedFont]);

  // ── History: params snapshot + restore ──────────────────────────
  const currentParams = useMemo((): Record<string, unknown> => {
    switch (s.activeMethod) {
      case "Hue Lock": return { hue: s.hue, steps: s.steps, curveMidY: s.curveMidY, chromaMode: s.chromaMode, fixedChroma: s.fixedChroma, hlFgPreset: s.hlFgPreset, hlVariety: s.hlVariety };
      case "Macro Knob": return { mkKnob: s.mkKnob, mkHue: s.mkHue, mkRelMode: s.mkRelMode, mkSpread: s.mkSpread, mkVariMode: s.mkVariMode };
      case "Word Picker": return { wpTags: s.wpTags, wpDrift: s.wpDrift, wpVariety: s.wpVariety, wpAccent: s.wpAccent };
      case "Temperature Corridor": return { tcHCenter: s.tcHCenter, tcHueWidth: s.tcHueWidth, tcChromaFloor: s.tcChromaFloor, tcChromaCeiling: s.tcChromaCeiling, lRange: s.lRange, tcCount: s.tcCount, tcVariety: s.tcVariety, tcLMidBias: s.tcLMidBias, tcHueOffset: s.tcHueOffset, tcAccentWeight: s.tcAccentWeight };
      default: return {};
    }
  }, [s.activeMethod, s.hue, s.steps, s.curveMidY, s.chromaMode, s.fixedChroma, s.hlFgPreset, s.hlVariety, s.mkKnob, s.mkHue, s.mkRelMode, s.mkSpread, s.mkVariMode, s.wpTags, s.wpDrift, s.wpVariety, s.wpAccent, s.tcHCenter, s.tcHueWidth, s.tcChromaFloor, s.tcChromaCeiling, s.lRange, s.tcCount, s.tcVariety, s.tcLMidBias, s.tcHueOffset, s.tcAccentWeight]);

  const restoreMap: Record<string, (v: any) => void> = useMemo(() => ({
    hue: s.setHue, steps: s.setSteps, curveMidY: s.setCurveMidY, chromaMode: s.setChromaMode, fixedChroma: s.setFixedChroma, hlFgPreset: s.setHlFgPreset, hlVariety: s.setHlVariety,
    mkKnob: s.setMkKnob, mkHue: s.setMkHue, mkRelMode: s.setMkRelMode, mkSpread: s.setMkSpread, mkVariMode: s.setMkVariMode,
    wpTags: s.setWpTags, wpDrift: s.setWpDrift, wpVariety: s.setWpVariety, wpAccent: s.setWpAccent,
    tcHCenter: s.setTcHCenter, tcHueWidth: s.setTcHueWidth, tcChromaFloor: s.setTcChromaFloor, tcChromaCeiling: s.setTcChromaCeiling, lRange: s.setLRange, tcCount: s.setTcCount, tcVariety: s.setTcVariety, tcLMidBias: s.setTcLMidBias, tcHueOffset: s.setTcHueOffset, tcAccentWeight: s.setTcAccentWeight,
  }), []);

  function handleHistoryRestore(entry: HistoryEntry) {
    s.switchMethod(entry.method);
    if (entry.params) {
      for (const [key, value] of Object.entries(entry.params)) {
        const setter = restoreMap[key];
        if (setter) setter(value);
      }
    }
  }

  // ── Render ───────────────────────────────────────────────────────

  return (
    <div className="flex flex-col flex-1 min-h-0 min-w-0 overflow-hidden">
      <HudBar
        workingCard={workingCard}
        cardPairs={cards.map((c) => ({ bg: c.rampColor.color, fg: c.fgOklch }))}
        contrastLevel={s.contrastLevel}
        onContrastLevelChange={s.setContrastLevel}
        activeMethod={s.activeMethod}
        buildSystemOpen={buildSystemOpen}
        onBuildSystem={openBuildSystem}
        onBackToExplore={closeBuildSystem}
        collectionCount={collection.count}
        onCollectionClick={openHub}
      />
      {!buildSystemOpen && (
        <MethodBar
          activeMethod={s.activeMethod}
          onMethodChange={s.switchMethod}
          albersOpen={s.albersOpen}
          onToggleAlbers={s.toggleAlbers}
        />
      )}

      <div className="flex flex-1 overflow-hidden" style={{ opacity: buildSystemOpen || hubOpen ? 0 : 1, transition: `opacity var(--dur-normal) var(--ease-out)`, display: buildSystemOpen || hubOpen ? "none" : undefined }}>
        {/* Sidebar */}
        <MethodSidebar>
          {s.activeMethod === "Macro Knob" ? (
            <MKParams
              knob={s.mkKnob}
              onKnobChange={s.setMkKnob}
              hue={s.mkHue}
              onHueChange={s.setMkHue}
              spread={s.mkSpread}
              onSpreadChange={s.setMkSpread}
              variMode={s.mkVariMode}
              onVariModeChange={s.setMkVariMode}
              activeFontCount={activeFontCount}
              relMode={s.mkRelMode}
              onRelModeChange={s.setMkRelMode}
              contrastLevel={s.contrastLevel}
            />
          ) : s.activeMethod === "Word Picker" ? (
            <WPParams
              activeTags={s.wpTags}
              onTagsChange={s.setWpTags}
              drift={s.wpDrift}
              onDriftChange={s.setWpDrift}
              count={s.wpCount}
              onCountChange={s.setWpCount}
              variety={s.wpVariety}
              onVarietyChange={s.setWpVariety}
              activeFontCount={activeFontCount}
              accent={s.wpAccent}
              onAccentChange={s.setWpAccent}
            />
          ) : s.activeMethod === "Extract" ? (
            <EXParams thumbnail={s.exThumbnail} onImageLoad={s.handleExImageLoad} onImageClear={s.handleExImageClear}
              remapEnabled={s.exRemapEnabled} onRemapChange={s.setExRemapEnabled}
              lightnessLock={s.exLightnessLock} onLightnessLockChange={s.setExLightnessLock}
              lockedL={s.exLockedL} onLockedLChange={s.setExLockedL}
              clusters={s.exRawClusters} clusterCount={s.exClusterCount} onClusterCountChange={s.setExClusterCount}
              workingColorIndex={effectiveWorkingIndex} onSetWorkingColor={s.setWorkingColorIndex} />
          ) : s.activeMethod === "Temperature Corridor" ? (
            <TCParams hCenter={s.tcHCenter} onHCenterChange={s.setTcHCenter}
              chromaFloor={s.tcChromaFloor} onChromaFloorChange={s.setTcChromaFloor}
              chromaCeiling={s.tcChromaCeiling} onChromaCeilingChange={s.setTcChromaCeiling}
              tempWidth={s.tempWidth} onTempWidthChange={s.setTempWidth}
              hueWidth={s.tcHueWidth} onHueWidthChange={s.setTcHueWidth}
              chromaCeiling2={s.tcChromaCeiling2} onChromaCeiling2Change={s.setTcChromaCeiling2}
              tempWidth2={s.tempWidth2} onTempWidth2Change={s.setTempWidth2}
              hueOffset={s.tcHueOffset} onHueOffsetChange={s.setTcHueOffset}
              accentChromaOffset={s.tcAccentChromaOffset} onAccentChromaOffsetChange={s.setTcAccentChromaOffset}
              count={s.tcCount} onCountChange={s.setTcCount}
              variety={s.tcVariety} onVarietyChange={s.setTcVariety} activeFontCount={activeFontCount}
              lRange={s.lRange} onLRangeChange={s.setLRange}
              lMidBias={s.tcLMidBias} onLMidBiasChange={s.setTcLMidBias}
              accentWeight={s.tcAccentWeight} onAccentWeightChange={s.setTcAccentWeight} />
          ) : (
            <HLParams
              hue={s.hue} onHueChange={s.setHue}
              steps={s.steps} onStepsChange={s.setSteps}
              curveMidY={s.curveMidY} onCurveMidYChange={s.setCurveMidY}
              chromaMode={s.chromaMode} onChromaModeChange={s.setChromaMode}
              fixedChroma={s.fixedChroma} onFixedChromaChange={s.setFixedChroma}
              accentEnabled={s.accentEnabled} onAccentEnabledChange={s.setAccentEnabled}
              accentHue={s.accentHue} onAccentHueChange={s.setAccentHue}
              accentL={s.accentL} onAccentLChange={s.setAccentL}
              fgPreset={s.hlFgPreset} onFgPresetChange={s.setHlFgPreset}
              fgLOverride={s.hlFgLOverride} onFgLOverrideChange={s.setHlFgLOverride}
              fgCOverride={s.hlFgCOverride} onFgCOverrideChange={s.setHlFgCOverride}
              variety={s.hlVariety} onVarietyChange={s.setHlVariety}
              activeFontCount={activeFontCount}
              contrastLevel={s.contrastLevel}
            />
          )}
        </MethodSidebar>

        {/* Main panel */}
        <div className="flex-1 min-w-0 flex flex-col relative">
          {/* Albers flyout panel */}
          <AlbersPanel open={s.albersOpen} onClose={s.closeAlbers} workingColor={workingColor} canvasColor={CANVAS_COLOR} />

          {/* Card grid */}
          <div className="flex-1 min-w-0 overflow-y-auto overflow-x-hidden p-8 bg-surface-0"
>
            {cards.length === 0 && !hasStarred ? (
              <div className="flex flex-col items-center justify-center h-full gap-3 text-center">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" className="text-fg-3">
                  <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
                </svg>
                <span className="max-w-xs" style={{ fontSize: "var(--text-ui)", color: "var(--c-text-3)" }}>
                  Star some fonts in Logo Grid or Type Explorer to see them here
                </span>
                {onSwitchToGrid && (
                  <button className="font-mono cursor-pointer mt-1" style={{ fontSize: "var(--text-body)", color: "var(--c-accent)", transition: "color var(--dur-fast) var(--ease-hover)" }}
                    onClick={onSwitchToGrid}>
                    Switch to Logo Grid →
                  </button>
                )}
              </div>
            ) : (
              <AnimatePresence mode="wait">
                <motion.div
                  key={s.activeMethod}
                  className="grid gap-6 pb-12 min-w-0"
                  style={{ gridTemplateColumns: "repeat(auto-fill, minmax(min(100%, 280px), 1fr))" }}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: dur.fast, ease: easeOut }}
                >
                  {(() => { let spotClaimed = false; return cards.map((card, cardIndex) => { // eslint-disable-line
                    const isSpot = !spotClaimed && spotlightColorKey !== null && colorKey(card.rampColor.color, card.fgOklch) === spotlightColorKey;
                    if (isSpot) spotClaimed = true;
                    // Apply flip for Macro Knob and Hue Lock
                    const isMK = s.activeMethod === "Macro Knob";
                    const isHL = s.activeMethod === "Hue Lock";
                    const canFlip = isMK || isHL;
                    const isFlipped = canFlip && flippedCards.has(cardIndex);
                    let renderBg = card.rampColor.color;
                    let renderFgColor = card.fgColor;
                    let renderFgOklch = card.fgOklch;
                    if (isFlipped) {
                      const flipped = isHL
                        ? hlFlipCard(card.rampColor.color, card.fgOklch, s.contrastLevel)
                        : flipCard(card.rampColor.color, card.fgOklch, s.contrastLevel);
                      renderBg = flipped.bg;
                      renderFgColor = oklchToCss(flipped.fg);
                      renderFgOklch = flipped.fg;
                    }
                    return (
                      <motion.div
                        key={card.isLogoCard ? "__logo__" : card.font!.file_path}
                        initial={{ opacity: 0, scale: 0.97 }}
                        animate={{ opacity: 1, scale: 1 }}
                        transition={{ duration: dur.fast, ease: easeOut, delay: cardIndex * 0.02 }}
                      >
                        <ColorCard
                          font={card.font}
                          bgColor={renderBg}
                          fgColor={renderFgColor}
                          fgOklch={renderFgOklch}
                          contrastLevel={s.contrastLevel}
                          cardIndex={cardIndex}
                          isWorking={card.rampIdx === effectiveWorkingIndex}
                          isPulsing={card.rampIdx === pulsingIdx}
                          isSpotlight={isSpot}
                          dimmed={card.dimmed}
                          brandName={brandName || undefined}
                          logoSvg={logoSvg}
                          isLogoCard={card.isLogoCard}
                          pinnedFont={isSpot ? pinnedFont : undefined}
                          starredFonts={isSpot ? starredFonts : undefined}
                          onPinFont={isSpot ? handlePinFont : undefined}
                          onClick={() => handleCardClick(card.rampIdx)}
                          onFlip={canFlip ? () => handleFlip(cardIndex) : undefined}
                          isSaved={collection.isSaved(renderBg, renderFgOklch)}
                          onSave={() => {
                            const renderFont = card.font;
                            const { status } = collection.addItem({
                              bg: renderBg,
                              fg: renderFgOklch,
                              fontName: renderFont?.font_family || "",
                              fontWeight: String(renderFont?.weight || ""),
                              fontCategory: renderFont?.classification?.category || "",
                              sourceMode: s.activeMethod,
                            });
                            return status;
                          }}
                          onUnsave={() => collection.removeByColorKey(renderBg, renderFgOklch)}
                        />
                      </motion.div>
                    );
                  }); })()}
                </motion.div>
              </AnimatePresence>
            )}
          </div>
        </div>
      </div>

      {/* Build System panel */}
      {buildSystemOpen && bsRoles && (
        <BuildSystemPanel
          roles={bsRoles}
          overrides={s.rbOverrides}
          onOverrideChange={s.handleRbOverride}
          onOverrideReset={s.handleRbOverrideReset}
          theme={s.rbTheme}
          onThemeChange={s.setRbTheme}
          previewFont={pinnedFont || starredFonts[0] || null}
          brandName={brandName}
          collectionItems={collection.items}
          roleAssignments={s.roleAssignments}
          onRoleAssign={(role, itemId) => s.setRoleAssignments((prev) => ({ ...prev, [role]: itemId }))}
          onRoleUnassign={(role) => s.setRoleAssignments((prev) => ({ ...prev, [role]: null }))}
          onExportCSS={handleExportSystemCSS}
          onExportJSON={handleExportSystemJSON}
          onExportPrompt={handleExportPrompt}
          heroCard={heroCard}
        />
      )}

      {/* Hub panel */}
      {hubOpen && (
        <HubPanel
          items={collection.items}
          brandName={brandName}
          onRemove={collection.removeById}
          onRestore={collection.restoreItem}
          onClearAll={collection.clear}
          onSendToBuildSystem={handleSendToBuildSystem}
          onClose={closeHub}
        />
      )}

      {/* Palette history strip */}
      {!buildSystemOpen && !hubOpen && (
        <PaletteHistoryStrip
          currentColors={sortedRamp.slice(0, 5).map((rc) => rc.color)}
          currentMethod={s.activeMethod}
          currentParams={currentParams}
          onRestore={handleHistoryRestore}
        />
      )}

      {/* Bottom bar */}
      <BottomBar label={hubOpen ? "Collection" : buildSystemOpen ? "Brand Kit" : s.activeMethod}>
        {buildSystemOpen ? (
          <RBBottomControls accentOffset={s.rbAccentOffset} onAccentOffsetChange={s.setRbAccentOffset}
            accentChromaMult={s.rbAccentChromaMult} onAccentChromaMultChange={s.setRbAccentChromaMult} />
        ) : s.activeMethod === "Macro Knob" ? (
          <MKBottomControls knob={s.mkKnob} hue={s.mkHue} spread={s.mkSpread} contrastLevel={s.contrastLevel} colorCount={activeFontCount} />
        ) : s.activeMethod === "Word Picker" ? (
          <WPBottomControls activeTags={s.wpTags} drift={s.wpDrift} count={s.wpCount} />
        ) : s.activeMethod === "Extract" ? (
          <EXBottomControls clusterCount={s.exClusterCount} />
        ) : s.activeMethod === "Temperature Corridor" ? (
          <TCBottomControls lRange={s.lRange} accentWeight={s.tcAccentWeight} count={s.tcCount} hueOffset={s.tcHueOffset} />
        ) : s.activeMethod === "Hue Lock" ? (
          <HLBottomControls hue={s.hue} shadeCount={sortedRamp.length} contrastRange={hlContrastRange(sortedRamp as HLRampColor[])} contrastLevel={s.contrastLevel} />
        ) : (
          <div className="flex items-center gap-4 bg-black/40 px-5 py-2 rounded-full border border-border-default shadow-inner">
            <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>—</span>
          </div>
        )}
      </BottomBar>

      {/* Toast */}
      {toast && (
        <div className="fixed bottom-20 left-1/2 -translate-x-1/2 z-50 bg-surface-4 text-fg text-xs font-medium px-4 py-2 rounded-md shadow-lg pointer-events-none select-none animate-[fadeIn_150ms_ease]">
          {toast}
        </div>
      )}
    </div>
  );
}
