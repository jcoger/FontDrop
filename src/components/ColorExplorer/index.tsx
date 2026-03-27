import { useState, useMemo, useEffect, useCallback, useRef } from "react";
import type { FontInfo } from "../../hooks/useFonts";
import { oklchToCss, oklchToHex, contrastRatio, hexToOklch } from "../../utils/oklch";
import type { OklchColor } from "../../utils/oklch";

import { useColorExplorerState } from "./useColorExplorerState";
import type { RampColor, ContrastRampColor } from "./types";

// Generation functions
import { generateHueLock, sampleToneCurve } from "./methods/hueLock";
import { applyExtractTransforms, buildExtractRamp } from "./methods/extractColors";

// Method UI — sidebar params + re-exported generation functions
import { HLParams } from "./methods/HLParams";
import { TCParams, TCBottomControls, generateTemperatureCorridor } from "./methods/TemperatureCorridor";
import { CSParams, CSBottomControls, generateContrastSafe } from "./methods/ContrastSafe";
import { RBParams, RBBottomControls, deriveRoles, rolePairings } from "./methods/RoleBuilder";
import { EXParams, EXBottomControls } from "./methods/Extract";

// Shared components
import { ColorCard } from "./components/ColorCard";
import { AlbersRow } from "./components/AlbersRow";
import { MethodSidebar } from "./components/MethodSidebar";
import { BottomBar } from "./components/BottomBar";
import { MethodBar } from "./components/MethodBar";

// ── Constants ─────────────────────────────────────────────────────────

const CANVAS_COLOR = hexToOklch("#0A0A0A");

// ── Props ─────────────────────────────────────────────────────────────

interface ColorExplorerProps {
  fonts: FontInfo[];
  logoSvg?: string | null;
  brandName?: string;
  colCount?: number;
  exportRef?: React.MutableRefObject<(() => void) | null>;
  onSwitchToGrid?: () => void;
}

// ── Component ─────────────────────────────────────────────────────────

export function ColorExplorer({
  fonts,
  logoSvg,
  brandName = "",
  colCount = 4,
  exportRef,
  onSwitchToGrid,
}: ColorExplorerProps) {
  const s = useColorExplorerState();

  // ── Toast ───────────────────────────────────────────────────────
  const [toast, setToast] = useState<string | null>(null);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2000);
    return () => clearTimeout(t);
  }, [toast]);

  // ── Card pulse ──────────────────────────────────────────────────
  const [pulsingIdx, setPulsingIdx] = useState<number | null>(null);
  useEffect(() => {
    if (pulsingIdx === null) return;
    const t = setTimeout(() => setPulsingIdx(null), 150);
    return () => clearTimeout(t);
  }, [pulsingIdx]);

  // ── Starred fonts ────────────────────────────────────────────────
  const [starredPaths, setStarredPaths] = useState<Set<string>>(new Set());
  useEffect(() => {
    const p = new Set<string>();
    try {
      (JSON.parse(localStorage.getItem("fontdrop:grid:starred") || "[]") as string[]).forEach((x) => p.add(x));
      (JSON.parse(localStorage.getItem("fontdrop:explorer:starred") || "[]") as string[]).forEach((x) => p.add(x));
    } catch { /* */ }
    setStarredPaths(p);
  }, []);
  const starredFonts = useMemo(() => fonts.filter((f) => starredPaths.has(f.file_path)), [fonts, starredPaths]);
  const displayFonts = starredFonts.length > 0 ? starredFonts : fonts.slice(0, 12);
  const hasStarred = starredFonts.length > 0;

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
    if (s.activeMethod === "Extract")
      return buildExtractRamp(applyExtractTransforms(s.exRawClusters, s.exRemapEnabled, s.exLightnessLock, s.exLockedL));
    if (s.activeMethod === "Role Builder" && rbRoles)
      return rolePairings(rbRoles);
    if (s.activeMethod === "Temperature Corridor")
      return generateTemperatureCorridor({ hCenter: s.tcHCenter, tempWidth: s.tempWidth, chromaMin: s.tcChromaMin, chromaMax: s.tcChromaMax, lRange: s.lRange, count: s.tcCount });
    if (s.activeMethod === "Contrast Safe")
      return generateContrastSafe({ primary: s.csPrimary, lRange: s.csLRange, cRange: s.csCRange, hueMode: s.csHueMode, threshold: s.csThreshold, density: s.csDensity, fgLock: s.csFgLock });
    const lValues = sampleToneCurve(s.steps, s.curveMidY);
    return generateHueLock({ hue: s.hue, steps: s.steps, chromaMode: s.chromaMode, fixedChroma: s.fixedChroma, accentEnabled: s.accentEnabled, accentHue: s.accentHue, accentL: s.accentL, lValues });
  }, [s.activeMethod, s.hue, s.steps, s.chromaMode, s.fixedChroma, s.accentEnabled, s.accentHue, s.accentL, s.curveMidY, s.tcHCenter, s.tempWidth, s.tcChromaMin, s.tcChromaMax, s.lRange, s.tcCount, s.csPrimary, s.csLRange, s.csCRange, s.csHueMode, s.csThreshold, s.csDensity, s.csFgLock, rbRoles, s.exRawClusters, s.exRemapEnabled, s.exLightnessLock, s.exLockedL]);

  const sortedRamp = useMemo(
    () => s.activeMethod === "Role Builder" ? ramp : [...ramp].sort((a, b) => a.color.l - b.color.l),
    [ramp, s.activeMethod],
  );

  const effectiveWorkingIndex =
    s.workingColorIndex !== null && s.workingColorIndex < sortedRamp.length
      ? s.workingColorIndex
      : Math.floor(sortedRamp.length / 2);
  const workingColor: OklchColor = sortedRamp[effectiveWorkingIndex]?.color || { mode: "oklch", l: 0.5, c: 0.1, h: 270 };
  useEffect(() => { s.setWorkingColorIndex(null); }, [sortedRamp.length]);

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

  interface CardEntry { font: FontInfo | null; rampColor: RampColor; rampIdx: number; fgColor: string; dimmed: boolean; badgeColor: string | undefined; isLogoCard: boolean; }

  const cards = useMemo((): CardEntry[] => {
    if (sortedRamp.length === 0) return [];
    const isCs = s.activeMethod === "Contrast Safe";
    const isTc = s.activeMethod === "Temperature Corridor";
    const isRb = s.activeMethod === "Role Builder";
    function build(font: FontInfo | null, i: number, isLogo: boolean): CardEntry {
      const rampIdx = i % sortedRamp.length, rc = sortedRamp[rampIdx];
      if (isRb && rc.fgCss) return { font, rampColor: rc, rampIdx, fgColor: rc.fgCss, dimmed: false, badgeColor: undefined, isLogoCard: isLogo };
      if (isCs) {
        const csrc = rc as ContrastRampColor, testCss = oklchToCss(csrc.color);
        const bgC = s.csFgLock ? csrc.color : s.csPrimary, fgC = s.csFgLock ? primaryCss : testCss;
        const bc: Record<string, string> = { AAA: "#4ade80", AA: "#facc15", "AA-large": "#fb923c", FAIL: "rgba(239,68,68,0.45)" };
        return { font, rampColor: { ...rc, color: bgC }, rampIdx, fgColor: fgC, dimmed: !(csrc as ContrastRampColor).passes, badgeColor: bc[(csrc as ContrastRampColor).badge.split(" ")[0]] || fgC, isLogoCard: isLogo };
      }
      return { font, rampColor: rc, rampIdx, fgColor: isTc ? tcForeground(rc.color) : hlForeground(rc.color, sortedRamp), dimmed: false, badgeColor: undefined, isLogoCard: isLogo };
    }
    const r: CardEntry[] = [];
    if (logoSvg) r.push(build(null, 0, true));
    const off = logoSvg ? 1 : 0;
    for (let i = 0; i < displayFonts.length; i++) r.push(build(displayFonts[i], i + off, false));
    return r;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [displayFonts, sortedRamp, s.activeMethod, tcDarkest, tcLightest, s.csPrimary, primaryCss, s.csFgLock, logoSvg]);

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

  useEffect(() => {
    if (exportRef) exportRef.current = handleExport;
    return () => { if (exportRef) exportRef.current = null; };
  }, [exportRef, handleExport]);

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

  // ── Method crossfade ─────────────────────────────────────────────
  const prevMethodRef = useRef(s.activeMethod);
  const [gridOpacity, setGridOpacity] = useState(1);
  useEffect(() => {
    if (prevMethodRef.current !== s.activeMethod) {
      prevMethodRef.current = s.activeMethod;
      setGridOpacity(0);
      const t = requestAnimationFrame(() => setGridOpacity(1));
      return () => cancelAnimationFrame(t);
    }
  }, [s.activeMethod]);

  function handleCardClick(rampIdx: number) {
    s.setWorkingColorIndex(rampIdx);
    setPulsingIdx(rampIdx);
  }

  // ── Render ───────────────────────────────────────────────────────

  return (
    <div className="flex flex-col flex-1 min-h-0 min-w-0 overflow-hidden">
      <MethodBar
        activeMethod={s.activeMethod}
        onMethodChange={s.switchMethod}
        displayFontCount={displayFonts.length}
        hasStarred={hasStarred}
        albersExpanded={s.albersExpanded}
        onToggleAlbers={s.toggleAlbers}
      />

      <div className="flex flex-1 overflow-hidden">
        {/* Sidebar */}
        <MethodSidebar>
          {s.activeMethod === "Extract" ? (
            <EXParams thumbnail={s.exThumbnail} onImageLoad={s.handleExImageLoad} onImageClear={s.handleExImageClear}
              remapEnabled={s.exRemapEnabled} onRemapChange={s.setExRemapEnabled}
              lightnessLock={s.exLightnessLock} onLightnessLockChange={s.setExLightnessLock}
              lockedL={s.exLockedL} onLockedLChange={s.setExLockedL}
              clusters={s.exRawClusters} clusterCount={s.exClusterCount} onClusterCountChange={s.setExClusterCount}
              workingColorIndex={effectiveWorkingIndex} onSetWorkingColor={s.setWorkingColorIndex} />
          ) : s.activeMethod === "Role Builder" && rbRoles ? (
            <RBParams primaryHex={s.rbPrimaryHex} onPrimaryHexChange={s.handleRbPrimaryHex}
              theme={s.rbTheme} onThemeChange={s.setRbTheme} roles={rbRoles}
              overrides={s.rbOverrides} onOverrideChange={s.handleRbOverride} onOverrideReset={s.handleRbOverrideReset} />
          ) : s.activeMethod === "Contrast Safe" ? (
            <CSParams primaryHex={s.csPrimaryHex} onPrimaryHexChange={s.handleCsPrimaryHex}
              primary={s.csPrimary}
              threshold={s.csThreshold} onThresholdChange={s.setCsThreshold}
              hueMode={s.csHueMode} onHueModeChange={s.setCsHueMode}
              density={s.csDensity} onDensityChange={s.setCsDensity}
              fgLock={s.csFgLock} onFgLockChange={s.setCsFgLock}
              lRange={s.csLRange} onLRangeChange={s.setCsLRange}
              results={sortedRamp as ContrastRampColor[]}
              onSetWorkingColor={s.setWorkingColorIndex} />
          ) : s.activeMethod === "Temperature Corridor" ? (
            <TCParams hCenter={s.tcHCenter} onHCenterChange={s.setTcHCenter}
              chromaMin={s.tcChromaMin} onChromaChange={s.handleTcChromaChange}
              tempWidth={s.tempWidth} onTempWidthChange={s.setTempWidth}
              count={s.tcCount} onCountChange={s.setTcCount} />
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
            />
          )}
        </MethodSidebar>

        {/* Main panel */}
        <div className="flex-1 min-w-0 flex flex-col relative">
          <AlbersRow workingColor={workingColor} canvasColor={CANVAS_COLOR} expanded={s.albersExpanded} />

          {/* Card grid */}
          <div className="flex-1 min-w-0 overflow-y-auto overflow-x-hidden p-8 bg-[#0A0A0A]"
            style={{ opacity: gridOpacity, transition: "opacity var(--dur-fast) var(--ease-hover)" }}>
            {cards.length === 0 && !hasStarred ? (
              <div className="flex flex-col items-center justify-center h-full gap-3 text-center">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" className="text-neutral-600">
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
              <div className="grid gap-6 pb-12 min-w-0" style={{ gridTemplateColumns: colCount === 1 ? "1fr" : `repeat(${colCount}, minmax(0, 1fr))` }}>
                {cards.map((card) => (
                  <ColorCard
                    key={card.isLogoCard ? "__logo__" : card.font!.file_path}
                    font={card.font} bgColor={card.rampColor.color} fgColor={card.fgColor}
                    badge={card.rampColor.badge} badgeColor={card.badgeColor}
                    isWorking={card.rampIdx === effectiveWorkingIndex}
                    isPulsing={card.rampIdx === pulsingIdx}
                    dimmed={card.dimmed} brandName={brandName || undefined}
                    logoSvg={logoSvg} isLogoCard={card.isLogoCard}
                    onClick={() => handleCardClick(card.rampIdx)}
                  />
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Bottom bar */}
      <BottomBar label={s.activeMethod}>
        {s.activeMethod === "Extract" ? (
          <EXBottomControls clusterCount={s.exClusterCount} />
        ) : s.activeMethod === "Role Builder" ? (
          <RBBottomControls accentOffset={s.rbAccentOffset} onAccentOffsetChange={s.setRbAccentOffset}
            accentChromaMult={s.rbAccentChromaMult} onAccentChromaMultChange={s.setRbAccentChromaMult} />
        ) : s.activeMethod === "Contrast Safe" ? (
          <CSBottomControls lRange={s.csLRange} cRange={s.csCRange} />
        ) : s.activeMethod === "Temperature Corridor" ? (
          <TCBottomControls lRange={s.lRange} onLRangeChange={s.setLRange} />
        ) : (
          <div className="flex items-center gap-4 bg-black/40 px-5 py-2 rounded-full border border-neutral-800/80 shadow-inner">
            <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>H {s.hue}°</span>
            <div className="w-px h-3.5 bg-neutral-800/80" />
            <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>{s.steps} steps</span>
            <div className="w-px h-3.5 bg-neutral-800/80" />
            <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
              {s.chromaMode === "fixed" ? `C ${s.fixedChroma.toFixed(2)}` : "Max C"}
            </span>
          </div>
        )}
      </BottomBar>

      {/* Toast */}
      {toast && (
        <div className="fixed bottom-20 left-1/2 -translate-x-1/2 z-50 bg-neutral-800 text-white text-xs font-medium px-4 py-2 rounded-md shadow-lg pointer-events-none select-none animate-[fadeIn_150ms_ease]">
          {toast}
        </div>
      )}
    </div>
  );
}
