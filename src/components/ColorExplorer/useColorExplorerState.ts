import { useState, useCallback, useEffect, useRef } from "react";
import { hexToOklch } from "../../utils/oklch";
import type { OklchColor } from "../../utils/oklch";
import { usePersisted } from "./usePersisted";
import { LS_KEYS, lsGet, lsSet } from "./storage";
import type {
  MethodName,
  ChromaMode,
  ContrastLevel,
  ColorVariety,
  RoleTheme,
  HueMode,
  Threshold,
  RoleName,
  RoleOverrides,
  ExtractedCluster,
} from "./types";
import type { WPTagName } from "./methods/wpLogic";
import type { RelModeId } from "./methods/mkLogic";
import type { HLFgPreset } from "./methods/hueLogic";
import { extractFromImage } from "./methods/extractColors";

// ── Hook ──────────────────────────────────────────────────────────────

export function useColorExplorerState() {
  // ── Active method ────────────────────────────────────────────────
  const [activeMethod, setActiveMethod] = usePersisted<MethodName>(LS_KEYS.method, "Hue Lock");
  function switchMethod(m: MethodName) { setActiveMethod(m); }

  // ── Hue Lock ─────────────────────────────────────────────────────
  const [hue, setHue] = usePersisted(LS_KEYS.hueLock.hue, 270);
  const [steps, setSteps] = usePersisted(LS_KEYS.hueLock.steps, 7);
  const [chromaMode, setChromaMode] = usePersisted<ChromaMode>(LS_KEYS.hueLock.chromaMode, "max");
  const [fixedChroma, setFixedChroma] = usePersisted(LS_KEYS.hueLock.fixedChroma, 0.15);
  const [accentEnabled, setAccentEnabled] = usePersisted(LS_KEYS.hueLock.accentEnabled, false);
  const [accentHue, setAccentHue] = usePersisted(LS_KEYS.hueLock.accentHue, 60);
  const [accentL, setAccentL] = usePersisted(LS_KEYS.hueLock.accentL, 0.6);
  const [curveMidY, setCurveMidY] = usePersisted(LS_KEYS.hueLock.curveMidY, 0.54);
  const [hlFgPreset, setHlFgPreset] = usePersisted<HLFgPreset>(LS_KEYS.hueLock.fgPreset, "neutral");
  const [hlFgLOverride, setHlFgLOverride] = usePersisted<number | null>(LS_KEYS.hueLock.fgLOverride, null);
  const [hlFgCOverride, setHlFgCOverride] = usePersisted<number | null>(LS_KEYS.hueLock.fgCOverride, null);
  const [hlVariety, setHlVariety] = usePersisted<ColorVariety>(LS_KEYS.hueLock.variety, "auto");

  // ── Temperature Corridor ─────────────────────────────────────────
  const [tcHCenter, setTcHCenter] = usePersisted(LS_KEYS.corridor.hCenter, 130);
  const [tempWidth, setTempWidth] = usePersisted(LS_KEYS.corridor.width, 70);
  const [tcChromaMin, setTcChromaMin] = usePersisted(LS_KEYS.corridor.chromaMin, 0.08);
  const [tcChromaMax, setTcChromaMax] = usePersisted(LS_KEYS.corridor.chromaMax, 0.18);
  const [tcChromaFloor, setTcChromaFloor] = usePersisted(LS_KEYS.corridor.chromaFloor, 0.2);
  const [tcChromaCeiling, setTcChromaCeiling] = usePersisted(LS_KEYS.corridor.chromaCeiling, 0.7);
  const [tcHueWidth, setTcHueWidth] = usePersisted(LS_KEYS.corridor.hueWidth, 42);
  const [lRange, setLRange] = usePersisted<[number, number]>(LS_KEYS.corridor.lRange, [0.3, 0.82]);
  const [tcCount, setTcCount] = usePersisted(LS_KEYS.corridor.count, 12);
  const [tcVariety, setTcVariety] = usePersisted<ColorVariety>(LS_KEYS.corridor.variety, "auto");
  const [tcLMidBias, setTcLMidBias] = usePersisted(LS_KEYS.corridor.lMidBias, 0.5);
  // Node 2
  const [tcHCenter2, setTcHCenter2] = usePersisted(LS_KEYS.corridor.hCenter2, 210);
  const [tcChromaMin2] = usePersisted(LS_KEYS.corridor.chromaMin2, 0.08);
  const [tcChromaMax2] = usePersisted(LS_KEYS.corridor.chromaMax2, 0.22);
  const [tcChromaFloor2, setTcChromaFloor2] = usePersisted(LS_KEYS.corridor.chromaFloor2, 0.2);
  const [tcChromaCeiling2, setTcChromaCeiling2] = usePersisted(LS_KEYS.corridor.chromaCeiling2, 0.7);
  const [tempWidth2, setTempWidth2] = usePersisted(LS_KEYS.corridor.width2, 50);
  const [tcAccentWeight, setTcAccentWeight] = usePersisted(LS_KEYS.corridor.accentWeight, 0.35);
  const [tcHueOffset, setTcHueOffset] = usePersisted(LS_KEYS.corridor.hueOffset, 180);
  const [tcAccentChromaOffset, setTcAccentChromaOffset] = usePersisted(LS_KEYS.corridor.accentChromaOffset, 0);
  const handleTcChromaChange = useCallback((min: number, max: number) => {
    setTcChromaMin(min);
    setTcChromaMax(max);
  }, []);

  // ── Contrast Safe ────────────────────────────────────────────────
  const [csPrimary, setCsPrimary] = usePersisted<OklchColor>(LS_KEYS.contrastSafe.primary, { mode: "oklch", l: 0.45, c: 0.2, h: 264 });
  const [csPrimaryHex, setCsPrimaryHex] = usePersisted(LS_KEYS.contrastSafe.primaryHex, "#4338ca");
  const [csLRange, setCsLRange] = usePersisted<[number, number]>(LS_KEYS.contrastSafe.lRange, [0.1, 0.9]);
  const [csCRange, setCsCRange] = usePersisted<[number, number]>(LS_KEYS.contrastSafe.cRange, [0.05, 0.3]);
  const [csHueMode, setCsHueMode] = usePersisted<HueMode>(LS_KEYS.contrastSafe.hueMode, "full");
  const [csThreshold, setCsThreshold] = usePersisted<Threshold>(LS_KEYS.contrastSafe.threshold, "AA");
  const [csDensity, setCsDensity] = usePersisted(LS_KEYS.contrastSafe.density, 16);
  const [csFgLock, setCsFgLock] = usePersisted(LS_KEYS.contrastSafe.fgLock, false);
  function handleCsPrimaryHex(hex: string) {
    setCsPrimaryHex(hex);
    setCsPrimary(hexToOklch(hex));
  }

  // ── Brand Kit (was Role Builder) ─────────────────────────────────
  // Migrate old localStorage keys on first load
  useEffect(() => {
    const oldKeys = [
      ["fontdrop-ce-rb-primary", LS_KEYS.roleBuilder.primary],
      ["fontdrop-ce-rb-primaryHex", LS_KEYS.roleBuilder.primaryHex],
      ["fontdrop-ce-rb-theme", LS_KEYS.roleBuilder.theme],
      ["fontdrop-ce-rb-accentOffset", LS_KEYS.roleBuilder.accentOffset],
      ["fontdrop-ce-rb-accentChromaMult", LS_KEYS.roleBuilder.accentChromaMult],
    ];
    for (const [oldKey, newKey] of oldKeys) {
      if (localStorage.getItem(oldKey) !== null && localStorage.getItem(newKey) === null) {
        localStorage.setItem(newKey, localStorage.getItem(oldKey)!);
      }
    }
  }, []);
  const [rbPrimary, setRbPrimary] = usePersisted<OklchColor>(LS_KEYS.roleBuilder.primary, { mode: "oklch", l: 0.45, c: 0.2, h: 264 });
  const [rbPrimaryHex, setRbPrimaryHex] = usePersisted(LS_KEYS.roleBuilder.primaryHex, "#4338ca");
  const [rbTheme, setRbTheme] = usePersisted<RoleTheme>(LS_KEYS.roleBuilder.theme, "light");
  const [rbAccentOffset, setRbAccentOffset] = usePersisted(LS_KEYS.roleBuilder.accentOffset, 150);
  const [rbAccentChromaMult, setRbAccentChromaMult] = usePersisted(LS_KEYS.roleBuilder.accentChromaMult, 0.8);
  const [rbOverrides, setRbOverrides] = useState<RoleOverrides>({ background: null, text: null, secondary: null, highlight: null });
  function handleRbPrimaryHex(hex: string) {
    setRbPrimaryHex(hex);
    setRbPrimary(hexToOklch(hex));
  }
  function handleRbOverride(role: RoleName, color: OklchColor) {
    if (role !== "primary") setRbOverrides((p) => ({ ...p, [role]: color }));
  }
  function handleRbOverrideReset(role: RoleName) {
    if (role !== "primary") setRbOverrides((p) => ({ ...p, [role]: null }));
  }

  // ── Macro Knob ──────────────────────────────────────────────────
  const [mkKnob, setMkKnob] = usePersisted(LS_KEYS.macroKnob.knob, 155);
  const [mkHue, setMkHue] = usePersisted(LS_KEYS.macroKnob.hue, 25);
  const [mkChaos, setMkChaos] = usePersisted(LS_KEYS.macroKnob.chaos, false);
  const [mkSpread, setMkSpread] = usePersisted(LS_KEYS.macroKnob.spread, 0);
  const [mkVariMode, setMkVariMode] = usePersisted<"smooth" | "wild">(LS_KEYS.macroKnob.variMode, "smooth");
  const [mkRelMode, setMkRelMode] = usePersisted<RelModeId>(LS_KEYS.macroKnob.relMode, "complement");

  // ── Word Picker ─────────────────────────────────────────────────
  const [wpTags, setWpTags] = usePersisted<WPTagName[]>(LS_KEYS.wordPicker.tags, []);
  const [wpDrift, setWpDrift] = usePersisted(LS_KEYS.wordPicker.drift, 50);
  const [wpCount, setWpCount] = usePersisted(LS_KEYS.wordPicker.count, 12);
  const [wpVariety, setWpVariety] = usePersisted<ColorVariety>(LS_KEYS.wordPicker.variety, "auto");
  const [wpAccent, setWpAccent] = usePersisted(LS_KEYS.wordPicker.accent, true);

  // ── Extract ──────────────────────────────────────────────────────
  const [exImage, setExImage] = useState<HTMLImageElement | null>(null);
  const [exThumbnail, setExThumbnail] = useState<string | null>(null);
  const exPrevBlobUrl = useRef<string | null>(null);
  const [exClusterCount, setExClusterCount] = usePersisted(LS_KEYS.extract.clusterCount, 5);
  const [exRemapEnabled, setExRemapEnabled] = usePersisted(LS_KEYS.extract.remap, false);
  const [exLightnessLock, setExLightnessLock] = usePersisted(LS_KEYS.extract.lightnessLock, false);
  const [exLockedL, setExLockedL] = usePersisted(LS_KEYS.extract.lockedL, 0.5);
  const [exRawClusters, setExRawClusters] = useState<ExtractedCluster[]>([]);

  function handleExImageLoad(img: HTMLImageElement, thumb: string) {
    // Revoke previous blob URL to prevent memory leak
    if (exPrevBlobUrl.current) { try { URL.revokeObjectURL(exPrevBlobUrl.current); } catch {} }
    exPrevBlobUrl.current = thumb.startsWith("blob:") ? thumb : null;
    setExImage(img);
    setExThumbnail(thumb);
  }
  function handleExImageClear() {
    if (exPrevBlobUrl.current) { try { URL.revokeObjectURL(exPrevBlobUrl.current); } catch {} }
    exPrevBlobUrl.current = null;
    setExImage(null);
    setExThumbnail(null);
    setExRawClusters([]);
    lsSet(LS_KEYS.extract.cachedClusters, null);
    lsSet(LS_KEYS.extract.cachedThumb, null);
  }

  // Run extraction + persist cache
  useEffect(() => {
    if (!exImage) { setExRawClusters([]); return; }
    const clusters = extractFromImage(exImage, exClusterCount);
    setExRawClusters(clusters);
    // Persist for session restore
    lsSet(LS_KEYS.extract.cachedClusters, clusters);
    if (exThumbnail) lsSet(LS_KEYS.extract.cachedThumb, exThumbnail);
  }, [exImage, exClusterCount]);

  // Session restore: check for cached clusters on mount
  const exInitialized = useRef(false);
  useEffect(() => {
    if (exInitialized.current) return;
    exInitialized.current = true;

    // Try restoring from cache
    const cached = lsGet<ExtractedCluster[] | null>(LS_KEYS.extract.cachedClusters, null);
    const cachedThumb = lsGet<string | null>(LS_KEYS.extract.cachedThumb, null);
    if (cached && cached.length > 0) {
      setExRawClusters(cached);
      if (cachedThumb) setExThumbnail(cachedThumb);
      return;
    }

    // No cache: generate a default gradient image and run extraction
    const canvas = document.createElement("canvas");
    canvas.width = 200; canvas.height = 200;
    const ctx = canvas.getContext("2d")!;
    // Warm earth + cool sky gradient
    const grad = ctx.createLinearGradient(0, 0, 200, 200);
    grad.addColorStop(0, "#4a6478");    // cool sky blue
    grad.addColorStop(0.3, "#c79a3a");  // golden
    grad.addColorStop(0.6, "#c05a45");  // terracotta
    grad.addColorStop(0.85, "#5c656d"); // stone gray
    grad.addColorStop(1, "#8a4a33");    // dark earth
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 200, 200);
    // Add noise texture
    for (let i = 0; i < 3000; i++) {
      const x = Math.random() * 200, y = Math.random() * 200;
      ctx.fillStyle = `rgba(${Math.random() > 0.5 ? 255 : 0},${Math.random() > 0.5 ? 255 : 0},${Math.random() > 0.5 ? 255 : 0},0.03)`;
      ctx.fillRect(x, y, 1, 1);
    }
    const dataUrl = canvas.toDataURL("image/png");
    const img = new Image();
    img.onload = () => {
      setExImage(img);
      setExThumbnail(dataUrl);
    };
    img.src = dataUrl;
  }, []);

  // ── UI state ─────────────────────────────────────────────────────
  const [workingColorIndex, setWorkingColorIndex] = useState<number | null>(null);
  // Global contrast level
  const [contrastLevel, setContrastLevel] = usePersisted<ContrastLevel>(LS_KEYS.ui.contrastLevel, "display");

  // Albers flyout panel
  const [albersOpen, setAlbersOpen] = usePersisted<boolean>(LS_KEYS.ui.albersOpen, false);
  function toggleAlbers() { setAlbersOpen((p) => !p); }
  function closeAlbers() { setAlbersOpen(false); }

  return {
    // Method
    activeMethod, switchMethod,
    // Hue Lock
    hue, setHue,
    steps, setSteps,
    chromaMode, setChromaMode,
    fixedChroma, setFixedChroma,
    accentEnabled, setAccentEnabled,
    accentHue, setAccentHue,
    accentL, setAccentL,
    curveMidY, setCurveMidY,
    hlFgPreset, setHlFgPreset,
    hlFgLOverride, setHlFgLOverride,
    hlFgCOverride, setHlFgCOverride,
    hlVariety, setHlVariety,
    // Temperature Corridor
    tcHCenter, setTcHCenter,
    tempWidth, setTempWidth,
    tcChromaMin, tcChromaMax,
    handleTcChromaChange,
    tcChromaFloor, setTcChromaFloor,
    tcChromaCeiling, setTcChromaCeiling,
    tcHueWidth, setTcHueWidth,
    lRange, setLRange,
    tcCount, setTcCount,
    tcVariety, setTcVariety,
    tcLMidBias, setTcLMidBias,
    tcHCenter2, setTcHCenter2,
    tcChromaMin2, tcChromaMax2,
    tcChromaFloor2, setTcChromaFloor2,
    tcChromaCeiling2, setTcChromaCeiling2,
    tempWidth2, setTempWidth2,
    tcAccentWeight, setTcAccentWeight,
    tcHueOffset, setTcHueOffset,
    tcAccentChromaOffset, setTcAccentChromaOffset,
    // Contrast Safe
    csPrimary, csPrimaryHex, handleCsPrimaryHex,
    csLRange, setCsLRange,
    csCRange, setCsCRange,
    csHueMode, setCsHueMode,
    csThreshold, setCsThreshold,
    csDensity, setCsDensity,
    csFgLock, setCsFgLock,
    // Role Builder
    rbPrimary, rbPrimaryHex, handleRbPrimaryHex,
    rbTheme, setRbTheme,
    rbAccentOffset, setRbAccentOffset,
    rbAccentChromaMult, setRbAccentChromaMult,
    rbOverrides, handleRbOverride, handleRbOverrideReset,
    // Macro Knob
    mkKnob, setMkKnob,
    mkHue, setMkHue,
    mkChaos, setMkChaos,
    mkSpread, setMkSpread,
    mkVariMode, setMkVariMode,
    mkRelMode, setMkRelMode,
    // Word Picker
    wpTags, setWpTags,
    wpDrift, setWpDrift,
    wpCount, setWpCount,
    wpVariety, setWpVariety,
    wpAccent, setWpAccent,
    // Extract
    exImage, exThumbnail, handleExImageLoad, handleExImageClear,
    exClusterCount, setExClusterCount,
    exRemapEnabled, setExRemapEnabled,
    exLightnessLock, setExLightnessLock,
    exLockedL, setExLockedL,
    exRawClusters,
    // UI
    workingColorIndex, setWorkingColorIndex,
    albersOpen, toggleAlbers, closeAlbers,
    contrastLevel, setContrastLevel,
  };
}
