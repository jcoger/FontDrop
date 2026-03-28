import { useState, useEffect, useMemo, useRef, useCallback, useId } from "react";
import { Agentation } from "agentation";
import "./App.css";
import { motion } from "framer-motion";
import { springSnap, easeOut, dur } from "./lib/motion";
import { Menu } from "bloom-menu";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useFonts, type FontInfo } from "./hooks/useFonts";
import { useStarred } from "./hooks/useStarred";
import { useExclusions } from "./hooks/useExclusions";
import { injectAllFontFaces } from "./lib/fontFace";
import { groupIntoFamilies } from "./lib/fontFamilies";
import { FontGrid } from "./components/FontGrid";
import { FontFamilyList } from "./components/FontFamilyList";
import { LogoDrop } from "./components/LogoDrop";
import {
  TypeExplorer,
  DEFAULT_HEADERS,
  DEFAULT_COLUMNS,
  DEFAULT_COL_SIZES,
  type Cols,
  type ColSizes,
} from "./components/TypeExplorer";
import { ControlsBar } from "./components/ControlsBar";
import { Toast } from "./components/Toast";
import { ShortcutOverlay } from "./components/ShortcutOverlay";
import { QuickView } from "./components/QuickView";
import { ColorExplorer } from "./components/ColorExplorer";
import { DEFAULT_CONTROLS, type Controls } from "./types/controls";

const appWindow = getCurrentWindow();

type Mode = "grid" | "explorer" | "color";
type SourceFilter = "all" | "user" | "system";

const CATEGORIES = ["sans-serif", "serif", "script", "decorative", "monospace", "other"] as const;
type Category = (typeof CATEGORIES)[number];

const CATEGORY_LABELS: Record<Category, string> = {
  "sans-serif": "Sans-Serif",
  "serif": "Serif",
  "script": "Script",
  "decorative": "Decorative",
  "monospace": "Mono",
  "other": "IDK",
};

// ── Animated segmented control ─────────────────────────────────────────────
// Motion pill lives ONLY inside the active option. Hover changes text color only.

function SegmentedControl<T extends string | number>({
  options,
  value,
  onChange,
  getLabel,
  disabled,
}: {
  options: readonly T[];
  value: T;
  onChange: (v: T) => void;
  getLabel?: (v: T) => string;
  disabled?: boolean;
}) {
  const id = useId();

  return (
    <div className="flex items-center flex-shrink-0" style={disabled ? { opacity: 0.3, pointerEvents: "none" } : undefined}>
      {options.map((opt) => (
        <button
          key={String(opt)}
          className="relative px-2.5 py-1.5 text-xs font-medium cursor-pointer whitespace-nowrap"
          style={{ color: opt === value ? "var(--c-text)" : "var(--c-text-3)", transition: "color var(--dur-fast) var(--ease-out)" }}
          onMouseEnter={(e) => {
            if (opt !== value) (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text)";
          }}
          onMouseLeave={(e) => {
            if (opt !== value) (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text-3)";
          }}
          onClick={() => onChange(opt)}
        >
          {opt === value && (
            <motion.div
              layoutId={`seg-${id}`}
              initial={false}
              className="absolute inset-0 bg-surface-active rounded-md"
              transition={springSnap}
            />
          )}
          <span className="relative">{getLabel ? getLabel(opt) : String(opt)}</span>
        </button>
      ))}
    </div>
  );
}

// ── Star filter toggle (animated) ─────────────────────────────────────────

function StarFilterToggle({
  count,
  showStarred,
  onChange,
}: {
  count: number;
  showStarred: boolean;
  onChange: (v: boolean) => void;
}) {
  const id = useId();

  return (
    <div className="flex items-center flex-shrink-0">
      {([false, true] as const).map((opt) => (
        <button
          key={String(opt)}
          className="relative px-2.5 py-1.5 text-xs font-medium cursor-pointer whitespace-nowrap"
          style={{ color: showStarred === opt ? (opt ? "var(--c-star)" : "var(--c-text)") : "var(--c-text-3)", transition: "color var(--dur-fast) var(--ease-out)" }}
          onMouseEnter={(e) => {
            if (showStarred !== opt) (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text)";
          }}
          onMouseLeave={(e) => {
            if (showStarred !== opt) (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text-3)";
          }}
          onClick={() => onChange(opt)}
        >
          {showStarred === opt && (
            <motion.div
              layoutId={`star-${id}`}
              initial={false}
              className="absolute inset-0 bg-surface-active rounded-md"
              transition={springSnap}
            />
          )}
          <span className="relative flex items-center gap-1.5">
            {opt ? (
              <>
                <svg width="10" height="10" viewBox="0 0 24 24" fill={showStarred ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinejoin="round">
                  <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
                </svg>
                {count > 0 ? `Starred (${count})` : "Starred"}
              </>
            ) : "All"}
          </span>
        </button>
      ))}
    </div>
  );
}

// ── Exclusion manager ──────────────────────────────────────────────────────

function ExclusionManagerContent({
  userFonts,
  builtinFonts,
  onUnhideUser,
  onUnhideBuiltin,
  onResetAll,
}: {
  userFonts: FontInfo[];
  builtinFonts: FontInfo[];
  onUnhideUser: (fp: string) => void;
  onUnhideBuiltin: (name: string) => void;
  onResetAll: () => void;
}) {
  const hasAny = userFonts.length > 0 || builtinFonts.length > 0;

  if (!hasAny) {
    return (
      <div className="px-3 py-4 text-xs text-fg-3 text-center">
        No hidden fonts
      </div>
    );
  }

  return (
    <div className="flex flex-col max-h-72 overflow-y-auto">
      {userFonts.length > 0 && (
        <div>
          <div className="px-3 pt-2.5 pb-1 text-[length:var(--text-label)] text-fg-3 font-mono uppercase tracking-widest sticky top-0 bg-surface-1">
            Your exclusions
          </div>
          {userFonts.map((f) => (
            <div key={f.file_path} className="flex items-center justify-between px-3 py-1.5 hover:bg-white/5">
              <span className="text-xs text-fg-2 truncate mr-2">{f.font_family}</span>
              <button
                className="text-[length:var(--text-label)] text-fg-3 hover:text-fg-2 cursor-pointer flex-shrink-0 transition-colors"
                onClick={() => onUnhideUser(f.file_path)}
              >
                Unhide
              </button>
            </div>
          ))}
        </div>
      )}
      {builtinFonts.length > 0 && (
        <div>
          <div className="px-3 pt-2.5 pb-1 text-[length:var(--text-label)] text-fg-3 font-mono uppercase tracking-widest sticky top-0 bg-surface-1">
            Built-in exclusions
          </div>
          {builtinFonts.map((f) => (
            <div key={f.font_family} className="flex items-center justify-between px-3 py-1.5 hover:bg-white/5">
              <span className="text-xs text-fg-2 truncate mr-2">{f.font_family}</span>
              <button
                className="text-[length:var(--text-label)] text-fg-3 hover:text-fg-2 cursor-pointer flex-shrink-0 transition-colors"
                onClick={() => onUnhideBuiltin(f.font_family)}
              >
                Unhide
              </button>
            </div>
          ))}
        </div>
      )}
      <div className="px-3 py-2 border-t border-border-default mt-1">
        <button
          className="w-full text-[length:var(--text-body)] text-fg-3 hover:text-red-400 cursor-pointer transition-colors text-left"
          onClick={onResetAll}
        >
          Reset all exclusions
        </button>
      </div>
    </div>
  );
}

// ── Main App ──────────────────────────────────────────────────────────────

export default function App() {
  const { fonts, loading, error } = useFonts();
  const [mode, setMode] = useState<Mode>("grid");
  const [wordmark, setWordmark] = useState("Fontdrop");
  const [logoSvg, setLogoSvg] = useState<string | null>(null);

  // Brand Colors tab state (lifted so top bar can render controls)
  const [ceBrandName, setCeBrandName] = useState(
    () => localStorage.getItem("fontdrop-brand-name") || "",
  );
  const [ceColCount, setCeColCount] = useState(4);
  const ceExportRef = useRef<(() => void) | null>(null);

  function handleCeBrandNameChange(v: string) {
    const clamped = v.slice(0, 30);
    setCeBrandName(clamped);
    localStorage.setItem("fontdrop-brand-name", clamped);
  }
  const [logoScale, setLogoScale] = useState(1.0);
  const [controls, setControls] = useState<Controls>(DEFAULT_CONTROLS);

  // Grid settings
  const [colCount, setColCount] = useState(4);
  const [familiesMode, setFamiliesMode] = useState(true);
  const [expandedFamilies, setExpandedFamilies] = useState<Set<string>>(new Set());

  // Filters
  const [search, setSearch] = useState("");
  const [sourceFilter, setSourceFilter] = useState<SourceFilter>("user");
  const [categoryFilter, setCategoryFilter] = useState<Category | null>(null);
  const [styleFilters, setStyleFilters] = useState<Set<string>>(new Set());

  // Quick View
  const [quickViewState, setQuickViewState] = useState<{
    font: FontInfo;
    rect: DOMRect;
  } | null>(null);

  // Exclusions
  const exclusions = useExclusions(fonts);

  // Toast + shortcut overlay
  const [toast, setToast] = useState<string | null>(null);
  const [showShortcuts, setShowShortcuts] = useState(false);

  // Hovered font (for S shortcut)
  const hoveredFilePath = useRef<string | null>(null);
  const setHoveredFont = useCallback((fp: string | null) => {
    hoveredFilePath.current = fp;
  }, []);

  // Search input ref (for F shortcut)
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Explorer content — lifted here so export can read them
  const [explorerHeaders, setExplorerHeaders] = useState<Cols>(DEFAULT_HEADERS);
  const [explorerColumns, setExplorerColumns] = useState<Cols>(DEFAULT_COLUMNS);
  const [explorerColSizes, setExplorerColSizes] = useState<ColSizes>(DEFAULT_COL_SIZES);
  const explorerContainerRef = useRef<HTMLDivElement>(null);
  const gridContainerRef = useRef<HTMLDivElement>(null);

  // Independent starred state per mode
  const gridStarred = useStarred("fontdrop:grid:starred");
  const explorerStarred = useStarred("fontdrop:explorer:starred");

  // Inject ALL font faces
  useEffect(() => {
    if (fonts.length > 0) injectAllFontFaces(fonts);
  }, [fonts]);

  // First-launch toast
  useEffect(() => {
    const count = exclusions.firstLaunchCount;
    if (count !== null) {
      setToast(`Hidden ${count} system fonts. Manage in Excluded.`);
      exclusions.clearFirstLaunch();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [exclusions.firstLaunchCount]);

  // Keyboard shortcuts
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      const inInput =
        e.target instanceof HTMLInputElement ||
        e.target instanceof HTMLTextAreaElement;

      if (e.key === "Escape") {
        if (quickViewState) { setQuickViewState(null); return; }
        if (showShortcuts) { setShowShortcuts(false); return; }
        setSearch("");
        return;
      }
      if (e.key === "?") {
        if (!inInput) { setShowShortcuts((prev) => !prev); return; }
      }
      if (inInput) return;
      if (e.key === "Tab") {
        e.preventDefault();
        setMode((m) => {
          if (m === "grid") return "explorer";
          if (m === "explorer") return "color";
          return "grid";
        });
        return;
      }
      if (e.key === "f" || e.key === "F") {
        e.preventDefault();
        searchInputRef.current?.focus();
        return;
      }
      if (e.key === "s" || e.key === "S") {
        const fp = hoveredFilePath.current;
        if (!fp) return;
        if (mode === "grid") gridStarred.toggle(fp);
        else explorerStarred.toggle(fp);
        return;
      }
      if (e.metaKey && !e.shiftKey && (e.key === "e" || e.key === "E")) {
        e.preventDefault();
        handleSavePng();
        return;
      }
      if (e.metaKey && e.shiftKey && (e.key === "c" || e.key === "C")) {
        e.preventDefault();
        handleCopyFigmaPrompt();
        return;
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode, showShortcuts, quickViewState]);

  function patchControls(patch: Partial<Controls>) {
    setControls((prev) => ({ ...prev, ...patch }));
  }

  function toggleStyleFilter(filter: string) {
    setStyleFilters((prev) => {
      const next = new Set(prev);
      if (next.has(filter)) next.delete(filter);
      else next.add(filter);
      return next;
    });
  }

  function toggleExpandedFamily(name: string) {
    setExpandedFamilies((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  }

  // Quick View helpers
  const handleSelectFont = useCallback((font: FontInfo, rect: DOMRect) => {
    setQuickViewState({ font, rect });
  }, []);

  const handleQuickViewNavigate = useCallback((font: FontInfo) => {
    setQuickViewState((prev) => prev ? { font, rect: prev.rect } : null);
  }, []);

  // ── Filter pipeline ──────────────────────────────────────────────────────

  const baseFonts = useMemo(
    () => fonts.filter((f) => !exclusions.isExcluded(f)),
    [fonts, exclusions.isExcluded]
  );

  const sourceFiltered = useMemo(() => {
    if (sourceFilter === "all") return baseFonts;
    if (sourceFilter === "user") return baseFonts.filter((f) => f.source === "user");
    return baseFonts.filter((f) => f.source === "system" || f.source === "library");
  }, [baseFonts, sourceFilter]);

  const searchLower = search.trim().toLowerCase();
  const searchedFonts = useMemo(() => {
    if (!searchLower) return sourceFiltered;
    return sourceFiltered.filter((f) =>
      f.font_family.toLowerCase().includes(searchLower)
    );
  }, [sourceFiltered, searchLower]);

  // Logo Grid filters
  const gridFonts = useMemo(() => {
    let result = gridStarred.showStarred
      ? searchedFonts.filter((f) => gridStarred.starred.has(f.file_path))
      : searchedFonts;
    if (categoryFilter) result = result.filter((f) => f.classification.category === categoryFilter);
    if (styleFilters.has("italic")) result = result.filter((f) => f.classification.style === "italic");
    if (styleFilters.has("condensed")) result = result.filter((f) => f.classification.width === "condensed");
    if (styleFilters.has("extended")) result = result.filter((f) => f.classification.width === "extended");
    return result;
  }, [searchedFonts, gridStarred.showStarred, gridStarred.starred, categoryFilter, styleFilters]);

  // Type Explorer filter — same category/style filters as grid
  const explorerFonts = useMemo(() => {
    let result = explorerStarred.showStarred
      ? searchedFonts.filter((f) => explorerStarred.starred.has(f.file_path))
      : searchedFonts;
    if (categoryFilter) result = result.filter((f) => f.classification.category === categoryFilter);
    if (styleFilters.has("italic")) result = result.filter((f) => f.classification.style === "italic");
    if (styleFilters.has("condensed")) result = result.filter((f) => f.classification.width === "condensed");
    if (styleFilters.has("extended")) result = result.filter((f) => f.classification.width === "extended");
    return result;
  }, [searchedFonts, explorerStarred.showStarred, explorerStarred.starred, categoryFilter, styleFilters]);

  // Category counts from searchedFonts (pre-category-filter)
  const categoryCounts = useMemo(
    () =>
      searchedFonts.reduce(
        (acc, f) => {
          const cat = f.classification.category;
          acc[cat] = (acc[cat] || 0) + 1;
          return acc;
        },
        {} as Record<string, number>
      ),
    [searchedFonts]
  );

  // Family grouping — filter out single-variant families (orphan rows)
  const gridFamilies = useMemo(
    () => groupIntoFamilies(gridFonts, 700).filter((fam) => fam.fonts.length >= 2),
    [gridFonts]
  );

  const hasGridFilters =
    gridStarred.showStarred || categoryFilter !== null || styleFilters.size > 0;

  // ── Export handlers ──────────────────────────────────────────────────────

  const handleSavePng = useCallback(async () => {
    const el = mode === "explorer" ? explorerContainerRef.current : gridContainerRef.current;
    if (!el) return;
    try {
      const { toPng } = await import("html-to-image");
      const date = new Date().toISOString().slice(0, 10);
      const name = mode === "explorer" ? "TypeExplorer" : "LogoGrid";
      const dataUrl = await toPng(el, { pixelRatio: 2 });
      const link = document.createElement("a");
      link.download = `FontDrop-${name}-${date}.png`;
      link.href = dataUrl;
      link.click();
      setToast("Saved");
    } catch {
      setToast("Export failed");
    }
  }, [mode]);

  const handleCopyFigmaPrompt = useCallback(() => {
    const fontNames = explorerFonts.map((f) => f.font_family).join(", ");
    const colDefs = explorerHeaders.map((h, i) => `${h}: ${explorerColumns[i]}`).join(" | ");
    const sizeDefs = explorerHeaders.map((h, i) => `${h}: ${explorerColSizes[i]}px`).join(" | ");
    const track =
      controls.letterSpacing === 0
        ? "0em"
        : `${controls.letterSpacing > 0 ? "+" : ""}${controls.letterSpacing.toFixed(3)}em`;

    const prompt = `Generate a type exploration frame.
Fonts: ${fontNames}
Content columns: ${colDefs}
Style: ${controls.bgColor} background, ${controls.fgColor} text, left-aligned rows
Column sizes: ${sizeDefs}
Letter spacing: ${track}`;

    navigator.clipboard.writeText(prompt);
    setToast("Copied to clipboard");
  }, [explorerFonts, explorerHeaders, explorerColumns, explorerColSizes, controls]);

  // ── Quick View font list (context-aware) ──────────────────────────────────

  const quickViewFonts = mode === "explorer" ? explorerFonts : gridFonts;

  // Chrome: traffic-light zone (28) + Row1 content (56) + Row2 (40)
  const quickViewTopOffset = 28 + 56 + 40;

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div className="h-screen bg-surface-0 flex flex-col select-none">

      {/* ── Row 1: Title + Mode tabs + Search/SVG/Wordmark + View controls + Export ── */}
      {/* Programmatic drag via appWindow.startDragging() on non-interactive areas */}
      <div
        className="flex-shrink-0 border-b border-border-default bg-surface-1"
        onMouseDown={(e) => { if (e.button === 0 && e.target === e.currentTarget) { e.preventDefault(); appWindow.startDragging(); } }}
      >
        {/* Traffic light zone — 28px for macOS overlay title bar */}
        <div
          className="h-7"
          onMouseDown={(e) => { if (e.button === 0) { e.preventDefault(); appWindow.startDragging(); } }}
        />

        {/* Content row — CSS Grid keeps search pinned in center regardless of mode-specific controls */}
        <div
          className="grid items-center px-4 h-14"
          style={{ gridTemplateColumns: "auto minmax(0,1fr) auto" } as React.CSSProperties}
          onMouseDown={(e) => { if (e.button === 0 && e.target === e.currentTarget) { e.preventDefault(); appWindow.startDragging(); } }}
        >
          {/* Left: FontDrop title + mode tabs */}
          <div
            className="flex items-center gap-3 flex-shrink-0"
            onMouseDown={(e) => { if (e.button === 0 && e.target === e.currentTarget) { e.preventDefault(); appWindow.startDragging(); } }}
          >
            <span
              className="text-[length:var(--text-title)] font-mono font-bold text-fg"
              onMouseDown={(e) => { if (e.button === 0) { e.preventDefault(); appWindow.startDragging(); } }}
            >FontDrop</span>
            <div
              className="w-px h-4 bg-border-default flex-shrink-0"
              onMouseDown={(e) => { if (e.button === 0) { e.preventDefault(); appWindow.startDragging(); } }}
            />
            <SegmentedControl
              options={["grid", "explorer", "color"] as const}
              value={mode}
              onChange={setMode}
              getLabel={(m) =>
                m === "grid"
                  ? "Logo Grid"
                  : m === "explorer"
                    ? "Type Explorer"
                    : "Brand Colors"
              }
            />
          </div>

          {/* Center: Search + SVG drop + Wordmark/Brand name */}
          {mode === "color" ? (
            <div
              className="flex items-center justify-center gap-2 px-6 min-w-0 overflow-hidden"
              onMouseDown={(e) => { if (e.button === 0 && e.target === e.currentTarget) { e.preventDefault(); appWindow.startDragging(); } }}
            >
              <LogoDrop
                svg={logoSvg}
                onLoad={setLogoSvg}
                onClear={() => setLogoSvg(null)}
                onScaleChange={setLogoScale}
                logoScale={logoScale}
              />
              <input
                className="flex-shrink-0 w-40 bg-surface-4 text-fg text-sm rounded-md px-3 h-9 outline-none
                           placeholder:text-fg-3 focus:ring-1 focus:ring-border-default select-text"
                value={ceBrandName}
                onChange={(e) => handleCeBrandNameChange(e.target.value)}
                placeholder="Brand name…"
                maxLength={30}
                spellCheck={false}
              />
            </div>
          ) : (
            <div
              className="flex items-center justify-center gap-2 px-6 min-w-0 overflow-hidden"
              onMouseDown={(e) => { if (e.button === 0 && e.target === e.currentTarget) { e.preventDefault(); appWindow.startDragging(); } }}
            >
              <div className="relative flex-shrink-0 w-44">
                <svg className="absolute left-2.5 top-1/2 -translate-y-1/2 text-fg-3 pointer-events-none"
                  width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
                </svg>
                <input
                  ref={searchInputRef}
                  className="w-full bg-surface-4 text-fg text-xs rounded-md pl-8 pr-3 h-9 outline-none
                             placeholder:text-fg-3 focus:ring-1 focus:ring-border-strong"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Search fonts…"
                  spellCheck={false}
                />
              </div>
              {mode === "grid" && (
                <>
                  <LogoDrop
                    svg={logoSvg}
                    onLoad={setLogoSvg}
                    onClear={() => setLogoSvg(null)}
                    onScaleChange={setLogoScale}
                    logoScale={logoScale}
                  />
                  <input
                    className="flex-shrink-0 w-40 bg-surface-4 text-fg text-sm rounded-md px-3 h-9 outline-none
                               placeholder:text-fg-3 focus:ring-1 focus:ring-border-default select-text"
                    value={wordmark}
                    onChange={(e) => setWordmark(e.target.value)}
                    placeholder="Type a word…"
                    spellCheck={false}
                  />
                </>
              )}
            </div>
          )}

          {/* Right: Col count + Export */}
          {mode === "color" ? (
          <div
            className="flex items-center gap-2 flex-shrink-0"
            onMouseDown={(e) => { if (e.button === 0 && e.target === e.currentTarget) { e.preventDefault(); appWindow.startDragging(); } }}
          >
            <SegmentedControl
              options={[1, 2, 4] as const}
              value={ceColCount}
              onChange={setCeColCount}
            />
            <div
              className="w-px h-4 bg-border-default flex-shrink-0"
              onMouseDown={(e) => { if (e.button === 0) { e.preventDefault(); appWindow.startDragging(); } }}
            />
            <Menu.Root direction="bottom" anchor="end">
              <Menu.Container
                buttonSize={{ width: 78, height: 30 }}
                menuWidth={172}
                menuRadius={10}
                buttonRadius={6}
                className="bg-surface-1 ring-1 ring-border-strong shadow-2xl"
              >
                <Menu.Trigger>
                  <div className="flex items-center justify-center gap-1.5 w-full h-full px-2.5">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-fg-2">
                      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                      <polyline points="7 10 12 15 17 10" />
                      <line x1="12" y1="15" x2="12" y2="3" />
                    </svg>
                    <span className="text-[length:var(--text-body)] text-fg-2 font-medium leading-none">Export</span>
                  </div>
                </Menu.Trigger>
                <Menu.Content className="p-1.5 flex flex-col gap-0.5">
                  <Menu.Item
                    onSelect={() => ceExportRef.current?.()}
                    className="flex items-center gap-2.5 px-2.5 py-2 text-xs text-fg hover:bg-white/10 rounded-md cursor-pointer transition-colors"
                  >
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" className="flex-shrink-0 text-fg-2">
                      <rect x="9" y="9" width="13" height="13" rx="2" />
                      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                    </svg>
                    Copy Palette
                  </Menu.Item>
                </Menu.Content>
              </Menu.Container>
            </Menu.Root>
          </div>
          ) : (
          <div
            className="flex items-center gap-2 flex-shrink-0"
            onMouseDown={(e) => { if (e.button === 0 && e.target === e.currentTarget) { e.preventDefault(); appWindow.startDragging(); } }}
          >
            {!loading && !error && (
              <>
                {mode === "grid" && (
                  <>
                    <SegmentedControl
                      options={[1, 2, 4] as const}
                      value={colCount}
                      onChange={setColCount}
                      disabled={familiesMode}
                    />
                    <SegmentedControl
                      options={["Families", "Individual"] as const}
                      value={familiesMode ? "Families" : "Individual"}
                      onChange={(v) => setFamiliesMode(v === "Families")}
                    />
                    <div
                      className="w-px h-4 bg-border-default flex-shrink-0"
                      onMouseDown={(e) => { if (e.button === 0) { e.preventDefault(); appWindow.startDragging(); } }}
                    />
                  </>
                )}
                <Menu.Root direction="bottom" anchor="end">
                  <Menu.Container
                    buttonSize={{ width: 78, height: 30 }}
                    menuWidth={172}
                    menuRadius={10}
                    buttonRadius={6}
                    className="bg-surface-1 ring-1 ring-border-strong shadow-2xl"
                  >
                    <Menu.Trigger>
                      <div className="flex items-center justify-center gap-1.5 w-full h-full px-2.5">
                        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-fg-2">
                          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                          <polyline points="7 10 12 15 17 10" />
                          <line x1="12" y1="15" x2="12" y2="3" />
                        </svg>
                        <span className="text-[length:var(--text-body)] text-fg-2 font-medium leading-none">Export</span>
                      </div>
                    </Menu.Trigger>
                    <Menu.Content className="p-1.5 flex flex-col gap-0.5">
                      <Menu.Item
                        onSelect={handleSavePng}
                        className="flex items-center gap-2.5 px-2.5 py-2 text-xs text-fg hover:bg-white/10 rounded-md cursor-pointer transition-colors"
                      >
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" className="flex-shrink-0 text-fg-2">
                          <rect x="3" y="3" width="18" height="18" rx="2" />
                          <circle cx="8.5" cy="8.5" r="1.5" />
                          <polyline points="21 15 16 10 5 21" />
                        </svg>
                        Save PNG
                      </Menu.Item>
                      {mode === "explorer" && (
                        <Menu.Item
                          onSelect={handleCopyFigmaPrompt}
                          className="flex items-center gap-2.5 px-2.5 py-2 text-xs text-fg hover:bg-white/10 rounded-md cursor-pointer transition-colors"
                        >
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" className="flex-shrink-0 text-fg-2">
                            <rect x="9" y="9" width="13" height="13" rx="2" />
                            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                          </svg>
                          Copy Figma Prompt
                        </Menu.Item>
                      )}
                    </Menu.Content>
                  </Menu.Container>
                </Menu.Root>
              </>
            )}
          </div>
          )}
        </div>
      </div>

      {/* ── Row 2: Unified filters (hidden in color mode) ── */}
      {mode !== "color" && <div className="flex-shrink-0 flex items-center gap-1.5 px-4 h-10 border-b border-border-default bg-surface-1 overflow-x-auto">
        {/* Left: source filter + category pills + style filters (always shown) */}
        {!loading && !error && (
          <>
            <SegmentedControl
              options={["all", "user", "system"] as const}
              value={sourceFilter}
              onChange={setSourceFilter}
              getLabel={(v) => v.charAt(0).toUpperCase() + v.slice(1)}
            />
            <div className="w-px h-4 bg-border-default mx-0.5 flex-shrink-0" />
            <CategoryFilterBar
              categories={CATEGORIES}
              value={categoryFilter}
              onChange={setCategoryFilter}
              counts={categoryCounts}
            />
            <div className="w-px h-4 bg-border-default mx-0.5 flex-shrink-0" />
            {(["italic", "condensed", "extended"] as const).map((filter) => {
              const isActive = styleFilters.has(filter);
              return (
                <button
                  key={filter}
                  className="relative px-2.5 py-1 text-[length:var(--text-body)] font-medium cursor-pointer capitalize flex-shrink-0 whitespace-nowrap"
                  style={{ color: isActive ? "var(--c-text)" : "var(--c-text-3)", transition: "color var(--dur-fast) var(--ease-out)" }}
                  onMouseEnter={(e) => {
                    if (!isActive) (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text)";
                  }}
                  onMouseLeave={(e) => {
                    (e.currentTarget as HTMLButtonElement).style.color = isActive ? "var(--c-text)" : "var(--c-text-3)";
                  }}
                  onClick={() => toggleStyleFilter(filter)}
                >
                  {isActive && (
                    <motion.div
                      className="absolute inset-0 bg-surface-active rounded-md"
                      layoutId={`style-${filter}`}
                      initial={false}
                      transition={springSnap}
                    />
                  )}
                  <span className="relative">{filter}</span>
                </button>
              );
            })}
          </>
        )}

        {/* Spacer */}
        <div className="flex-1 min-w-0" />

        {/* Right: starred + excluded + count */}
        {!loading && !error && (
          <div className="flex items-center gap-1.5 flex-shrink-0">
            <StarFilterToggle
              count={mode === "grid" ? gridStarred.starred.size : explorerStarred.starred.size}
              showStarred={mode === "grid" ? gridStarred.showStarred : explorerStarred.showStarred}
              onChange={mode === "grid" ? gridStarred.setShowStarred : explorerStarred.setShowStarred}
            />
            <Menu.Root direction="bottom" anchor="end">
              <Menu.Container
                buttonSize={{ width: 108, height: 28 }}
                menuWidth={260}
                menuRadius={10}
                buttonRadius={6}
                className="bg-surface-1 ring-1 ring-border-strong shadow-2xl"
              >
                <Menu.Trigger>
                  <div className="flex items-center justify-center gap-1.5 w-full h-full px-2.5">
                    <span className="text-[length:var(--text-body)] text-fg-4 font-medium leading-none">
                      Excluded{exclusions.excludedCount > 0 ? ` (${exclusions.excludedCount})` : ""}
                    </span>
                  </div>
                </Menu.Trigger>
                <Menu.Content>
                  <ExclusionManagerContent
                    userFonts={exclusions.userExcludedFonts}
                    builtinFonts={exclusions.builtinExcludedFonts}
                    onUnhideUser={exclusions.unhideUser}
                    onUnhideBuiltin={exclusions.unhideBuiltin}
                    onResetAll={exclusions.resetAll}
                  />
                </Menu.Content>
              </Menu.Container>
            </Menu.Root>
            <span className="text-fg-3 text-xs font-mono tabular-nums whitespace-nowrap flex-shrink-0 text-right" style={{ minWidth: "6.5rem" }}>
              {mode === "grid"
                ? familiesMode
                  ? `${gridFamilies.length.toLocaleString()} families`
                  : `${gridFonts.length.toLocaleString()} fonts`
                : `${explorerFonts.length.toLocaleString()} fonts`}
            </span>
          </div>
        )}

        {loading && <span className="text-fg-3 text-xs font-mono flex-shrink-0">scanning…</span>}
        {error && <span className="text-red-500 text-xs font-mono flex-shrink-0">error</span>}
      </div>}

      {/* ── Content area ── */}
      {mode === "color" ? (
        <ColorExplorer
          fonts={baseFonts}
          logoSvg={logoSvg}
          brandName={ceBrandName}
          colCount={ceColCount}
          exportRef={ceExportRef}
          onSwitchToGrid={() => setMode("grid")}
        />
      ) : (
      <motion.div
        ref={gridContainerRef}
        className="flex-1 min-h-0 flex flex-col"
        style={{ backgroundColor: controls.bgColor }}
        animate={{
          opacity: quickViewState ? 0 : 1,
        }}
        transition={{ duration: dur.normal, ease: easeOut }}
      >

        {/* Loading / error / empty */}
        {loading && (
          <div className="flex-1 flex items-center justify-center">
            <span className="text-fg-3 text-sm animate-pulse">Scanning fonts…</span>
          </div>
        )}
        {error && (
          <div className="flex-1 flex items-center justify-center">
            <span className="text-red-500 text-sm">{error}</span>
          </div>
        )}
        {!loading && !error && mode === "grid" && (hasGridFilters || searchLower) && gridFonts.length === 0 && (
          <div className="flex-1 flex flex-col items-center justify-center gap-2">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" className="text-fg-3">
              <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
            </svg>
            <span className="text-fg-3 text-sm">
              {gridStarred.showStarred
                ? "No starred fonts — hover to star"
                : searchLower
                ? `No fonts match "${search}"`
                : "No fonts match the current filters"}
            </span>
          </div>
        )}
        {!loading && !error && mode === "explorer" && explorerStarred.showStarred && explorerFonts.length === 0 && (
          <div className="flex-1 flex flex-col items-center justify-center gap-2">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" className="text-fg-3">
              <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
            </svg>
            <span className="text-fg-3 text-sm">No starred fonts — hover a row to star it</span>
          </div>
        )}

        {/* Views */}
        {!loading && !error && mode === "grid" && (
          <>
            {familiesMode && gridFamilies.length > 0 && (
              <FontFamilyList
                families={gridFamilies}
                wordmark={wordmark || "Fontdrop"}
                logoSvg={logoSvg}
                logoScale={logoScale}
                controls={controls}
                starred={gridStarred.starred}
                onToggleStar={gridStarred.toggle}
                onExclude={exclusions.excludeFont}
                onHover={setHoveredFont}
                onSelect={handleSelectFont}
                selectedFontPath={quickViewState?.font.file_path ?? null}
                expandedFamilies={expandedFamilies}
                onToggleFamily={toggleExpandedFamily}
              />
            )}
            {!familiesMode && gridFonts.length > 0 && (
              <FontGrid
                fonts={gridFonts}
                wordmark={wordmark || "Fontdrop"}
                logoSvg={logoSvg}
                logoScale={logoScale}
                controls={controls}
                starred={gridStarred.starred}
                onToggleStar={gridStarred.toggle}
                onExclude={exclusions.excludeFont}
                onHover={setHoveredFont}
                onSelect={handleSelectFont}
                selectedFontPath={quickViewState?.font.file_path ?? null}
                colCount={colCount}
              />
            )}
            {familiesMode && gridFamilies.length === 0 && gridFonts.length > 0 && (
              <div className="flex-1 flex items-center justify-center">
                <span className="text-fg-3 text-sm">No families with multiple variants. Switch to Individual view.</span>
              </div>
            )}
          </>
        )}
        {!loading && !error && mode === "explorer" && explorerFonts.length > 0 && (
          <TypeExplorer
            fonts={explorerFonts}
            controls={controls}
            starred={explorerStarred.starred}
            onToggleStar={explorerStarred.toggle}
            onExclude={exclusions.excludeFont}
            onHover={setHoveredFont}
            onSelect={handleSelectFont}
            selectedFontPath={quickViewState?.font.file_path ?? null}
            headers={explorerHeaders}
            columns={explorerColumns}
            colSizes={explorerColSizes}
            onHeadersChange={setExplorerHeaders}
            onColumnsChange={setExplorerColumns}
            onColSizesChange={setExplorerColSizes}
            containerRef={explorerContainerRef}
          />
        )}
      </motion.div>
      )}

      {/* ── Controls bar (hidden in color mode) ── */}
      {!loading && !error && mode !== "color" && (
        <ControlsBar
          controls={controls}
          onChange={patchControls}
          onShowShortcuts={() => setShowShortcuts(true)}
        />
      )}

      {/* ── Quick View ── */}
      <QuickView
        font={quickViewState?.font ?? null}
        sourceRect={quickViewState?.rect ?? null}
        allFonts={quickViewFonts}
        wordmark={wordmark || "Fontdrop"}
        logoSvg={logoSvg}
        logoScale={logoScale}
        controls={controls}
        starred={mode === "grid" ? gridStarred.starred : explorerStarred.starred}
        onToggleStar={mode === "grid" ? gridStarred.toggle : explorerStarred.toggle}
        onExclude={exclusions.excludeFont}
        onClose={() => setQuickViewState(null)}
        onNavigate={handleQuickViewNavigate}
        topOffset={quickViewTopOffset}
      />

      {/* ── Shortcut overlay ── */}
      {showShortcuts && <ShortcutOverlay onClose={() => setShowShortcuts(false)} />}

      {/* ── Toast ── */}
      {toast && <Toast message={toast} onDismiss={() => setToast(null)} />}
      {import.meta.env.DEV && <Agentation />}
    </div>
  );
}

// ── Category filter bar with animation ────────────────────────────────────

function CategoryFilterBar({
  categories,
  value,
  onChange,
  counts,
}: {
  categories: readonly Category[];
  value: Category | null;
  onChange: (cat: Category | null) => void;
  counts: Record<string, number>;
}) {
  const id = useId();

  return (
    <>
      {(["all", ...categories] as const).map((cat) => {
        const isAll = cat === "all";
        const isActive = isAll ? value === null : value === cat;

        return (
          <button
            key={cat}
            className="relative px-2.5 py-1 text-[length:var(--text-body)] font-medium cursor-pointer flex-shrink-0 whitespace-nowrap"
            style={{ color: isActive ? "var(--c-text)" : "var(--c-text-3)", transition: "color var(--dur-fast) var(--ease-out)" }}
            onMouseEnter={(e) => {
              if (!isActive) (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text)";
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLButtonElement).style.color = isActive ? "var(--c-text)" : "var(--c-text-3)";
            }}
            onClick={() => onChange(isAll ? null : (cat as Category))}
          >
            {isActive && (
              <motion.div
                className="absolute inset-0 bg-surface-active rounded-md"
                layoutId={`cat-${id}`}
                initial={false}
                transition={springSnap}
              />
            )}
            <span className="relative">
              {isAll ? "All" : CATEGORY_LABELS[cat as Category]}
              {!isAll && counts[cat] ? (
                <span className="ml-1 text-fg-4 font-mono normal-case opacity-70">
                  {counts[cat].toLocaleString()}
                </span>
              ) : null}
            </span>
          </button>
        );
      })}
    </>
  );
}
