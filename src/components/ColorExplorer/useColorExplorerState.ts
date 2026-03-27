import { useState, useCallback, useEffect } from "react";
import { hexToOklch } from "../../utils/oklch";
import type { OklchColor } from "../../utils/oklch";
import { usePersisted } from "./usePersisted";
import { LS_KEYS, lsSet } from "./storage";
import type {
  MethodName,
  ChromaMode,
  RoleTheme,
  HueMode,
  Threshold,
  RoleName,
  RoleOverrides,
  ExtractedCluster,
} from "./types";
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

  // ── Temperature Corridor ─────────────────────────────────────────
  const [tcHCenter, setTcHCenter] = usePersisted(LS_KEYS.corridor.hCenter, 130);
  const [tempWidth, setTempWidth] = usePersisted(LS_KEYS.corridor.width, 70);
  const [tcChromaMin, setTcChromaMin] = usePersisted(LS_KEYS.corridor.chromaMin, 0.08);
  const [tcChromaMax, setTcChromaMax] = usePersisted(LS_KEYS.corridor.chromaMax, 0.18);
  const [lRange, setLRange] = usePersisted<[number, number]>(LS_KEYS.corridor.lRange, [0.3, 0.8]);
  const [tcCount, setTcCount] = usePersisted(LS_KEYS.corridor.count, 12);
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

  // ── Role Builder ─────────────────────────────────────────────────
  const [rbPrimary, setRbPrimary] = usePersisted<OklchColor>(LS_KEYS.roleBuilder.primary, { mode: "oklch", l: 0.45, c: 0.2, h: 264 });
  const [rbPrimaryHex, setRbPrimaryHex] = usePersisted(LS_KEYS.roleBuilder.primaryHex, "#4338ca");
  const [rbTheme, setRbTheme] = usePersisted<RoleTheme>(LS_KEYS.roleBuilder.theme, "light");
  const [rbAccentOffset, setRbAccentOffset] = usePersisted(LS_KEYS.roleBuilder.accentOffset, 150);
  const [rbAccentChromaMult, setRbAccentChromaMult] = usePersisted(LS_KEYS.roleBuilder.accentChromaMult, 0.8);
  const [rbOverrides, setRbOverrides] = useState<RoleOverrides>({ surface: null, onSurface: null, accent: null, error: null });
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

  // ── Extract ──────────────────────────────────────────────────────
  const [exImage, setExImage] = useState<HTMLImageElement | null>(null);
  const [exThumbnail, setExThumbnail] = useState<string | null>(null);
  const [exClusterCount, setExClusterCount] = usePersisted(LS_KEYS.extract.clusterCount, 5);
  const [exRemapEnabled, setExRemapEnabled] = usePersisted(LS_KEYS.extract.remap, false);
  const [exLightnessLock, setExLightnessLock] = usePersisted(LS_KEYS.extract.lightnessLock, false);
  const [exLockedL, setExLockedL] = usePersisted(LS_KEYS.extract.lockedL, 0.5);
  const [exRawClusters, setExRawClusters] = useState<ExtractedCluster[]>([]);

  function handleExImageLoad(img: HTMLImageElement, thumb: string) {
    setExImage(img);
    setExThumbnail(thumb);
  }
  function handleExImageClear() {
    setExImage(null);
    setExThumbnail(null);
    setExRawClusters([]);
  }
  useEffect(() => {
    if (!exImage) { setExRawClusters([]); return; }
    setExRawClusters(extractFromImage(exImage, exClusterCount));
  }, [exImage, exClusterCount]);

  // ── UI state ─────────────────────────────────────────────────────
  const [workingColorIndex, setWorkingColorIndex] = useState<number | null>(null);
  const [albersExpanded, setAlbersExpanded] = useState(() => {
    const s = localStorage.getItem(LS_KEYS.ui.albersExpanded);
    return s === null ? true : s === "true";
  });
  function toggleAlbers() {
    setAlbersExpanded((p) => {
      const n = !p;
      lsSet(LS_KEYS.ui.albersExpanded, String(n));
      return n;
    });
  }

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
    // Temperature Corridor
    tcHCenter, setTcHCenter,
    tempWidth, setTempWidth,
    tcChromaMin, tcChromaMax,
    handleTcChromaChange,
    lRange, setLRange,
    tcCount, setTcCount,
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
    // Extract
    exImage, exThumbnail, handleExImageLoad, handleExImageClear,
    exClusterCount, setExClusterCount,
    exRemapEnabled, setExRemapEnabled,
    exLightnessLock, setExLightnessLock,
    exLockedL, setExLockedL,
    exRawClusters,
    // UI
    workingColorIndex, setWorkingColorIndex,
    albersExpanded, toggleAlbers,
  };
}
