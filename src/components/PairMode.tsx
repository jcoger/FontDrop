import { useState, useMemo, useCallback, useRef, useEffect } from "react";
import { Grid, CellComponentProps } from "react-window";
import { motion, AnimatePresence } from "framer-motion";
import { FontCard } from "./FontCard";
import { SkeletonBadge } from "./SkeletonBadge";
import { fontFamily } from "../lib/fontFace";
import { easeOut, dur, springModal } from "../lib/motion";
import { useFontPairs, type PairScore, type PairBucket } from "../hooks/useFontPairs";
import type { FontInfo } from "../types/font";
import type { FontDBRow, FontUpdate } from "../hooks/useFontDB";
import type { Controls } from "../types/controls";

// ── Colors + helpers ──────────────────────────────────────────────────────────

const PAIR_TYPE_COLORS: Record<string, { bg: string; text: string }> = {
  contrast:    { bg: "rgba(59,130,246,0.15)", text: "#60a5fa" },
  uniform:     { bg: "rgba(34,197,94,0.15)",  text: "#4ade80" },
  superfamily: { bg: "rgba(245,158,11,0.15)", text: "#fbbf24" },
  uncertain:   { bg: "rgba(163,163,163,0.15)", text: "#a3a3a3" },
};

// One name per pair type, on cards and in the detail view (matches the Rust buckets)
function shortTag(t: string): string {
  if (t === "contrast") return "Contrast";
  if (t === "uniform") return "Uniform";
  if (t === "superfamily") return "Designed together";
  return "Maybe";
}

const detailPairLabel = shortTag;

// ── Shared: font info column ──────────────────────────────────────────────────

function FontInfoColumn({
  font,
  label,
  onUpdate,
  onAfterChange,
  onToast,
}: {
  font: FontDBRow;
  label: string;
  onUpdate: (fontId: string, updates: FontUpdate) => Promise<void>;
  onAfterChange?: () => void;
  onToast?: (msg: string) => void;
}) {
  return (
    <div className="flex-1 min-w-0">
      <span className="text-[10px] text-fg-4 font-mono uppercase tracking-widest block mb-2">{label}</span>
      <h3
        className="text-2xl text-fg font-medium truncate mb-2"
        style={{ fontFamily: fontFamily(font.file_path) }}
      >
        {font.font_family}
      </h3>
      <div className="flex items-center gap-1.5 flex-wrap">
        <SkeletonBadge
          font={font}
          onUpdate={onUpdate}
          onAfterChange={onAfterChange}
          onToast={onToast}
          size="sm"
        />
        <span className="px-1.5 py-0.5 rounded-md bg-white/5 text-[10px] text-fg-3 font-medium">
          {font.flesh_contrast === "contrasting" ? "Contrasting" : "Linear"}
        </span>
        <span className="px-1.5 py-0.5 rounded-md bg-white/5 text-[10px] text-fg-3 font-medium">
          {font.flesh_serif === 1 ? "Serif" : "Sans"}
        </span>
      </div>
      {font.foundry && (
        <span className="text-[10px] text-fg-4 mt-1.5 block truncate">
          {font.designer && font.designer !== font.foundry
            ? `${font.foundry} · ${font.designer}`
            : font.foundry}
        </span>
      )}
    </div>
  );
}

// ── Expanded comparison view ──────────────────────────────────────────────────

function PairDetailView({
  primary,
  allPairs,
  buckets,
  fontById,
  wordmark,
  controls,
  starred,
  onToggleStar,
  onClose,
  initialIndex,
  onUpdate,
  onAfterChange,
  onToast,
}: {
  primary: FontDBRow;
  allPairs: PairScore[];
  buckets: PairBucket[];
  fontById: Map<string, FontDBRow>;
  wordmark: string;
  controls: Controls;
  starred: Set<string>;
  onToggleStar: (id: string) => void;
  onClose: () => void;
  initialIndex: number;
  onUpdate: (fontId: string, updates: FontUpdate) => Promise<void>;
  onAfterChange: () => void;
  onToast: (msg: string) => void;
}) {
  const [currentIdx, setCurrentIdx] = useState(initialIndex);
  const pair = allPairs[currentIdx];
  const candidate = pair ? fontById.get(pair.font_id) : undefined;

  // Find which bucket this pair belongs to
  const currentBucketLabel = useMemo(() => {
    if (!pair) return "";
    for (const b of buckets) {
      if (b.pairs.some((p) => p.font_id === pair.font_id)) return b.label;
    }
    return "";
  }, [pair, buckets]);

  const goNext = useCallback(() => {
    setCurrentIdx((i) => Math.min(i + 1, allPairs.length - 1));
  }, [allPairs.length]);

  const goPrev = useCallback(() => {
    setCurrentIdx((i) => Math.max(i - 1, 0));
  }, []);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") { e.stopPropagation(); onClose(); return; }
      if (e.key === "ArrowDown" || e.key === "ArrowRight") { e.preventDefault(); goNext(); }
      if (e.key === "ArrowUp" || e.key === "ArrowLeft") { e.preventDefault(); goPrev(); }
    }
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [onClose, goNext, goPrev]);

  if (!pair || !candidate) return null;

  const isStarred = starred.has(candidate.file_path);
  const display = wordmark || "Fontdrop";

  const displaySize = controls.fontSize;
  const headingSize = Math.round(controls.fontSize * 0.67);
  const bodySize = Math.round(controls.fontSize * 0.33);

  const metrics: { label: string; value: string; ok: boolean }[] = [];

  if (primary.skeleton !== "unknown" && candidate.skeleton !== "unknown") {
    const same = primary.skeleton === candidate.skeleton;
    metrics.push({
      label: "Skeleton",
      value: same ? `both ${primary.skeleton}` : `${primary.skeleton} vs ${candidate.skeleton}`,
      ok: same || (primary.flesh_contrast !== candidate.flesh_contrast || primary.flesh_serif !== candidate.flesh_serif),
    });
  }

  if (primary.x_height_ratio != null && candidate.x_height_ratio != null) {
    const diff = Math.abs(primary.x_height_ratio - candidate.x_height_ratio) / primary.x_height_ratio * 100;
    metrics.push({ label: "x-height", value: `${diff.toFixed(0)}% difference`, ok: diff <= 10 });
  }

  {
    const pLabel = primary.flesh_serif === 1 ? "serif" : "sans";
    const cLabel = candidate.flesh_serif === 1 ? "serif" : "sans";
    metrics.push({ label: "Flesh", value: pLabel === cLabel ? `both ${pLabel}` : `${pLabel} vs ${cLabel}`, ok: pLabel !== cLabel });
  }

  {
    const shared = primary.foundry && candidate.foundry && primary.foundry === candidate.foundry;
    metrics.push({ label: "Foundry", value: shared ? primary.foundry! : "different", ok: !!shared });
  }

  const typeColors = PAIR_TYPE_COLORS[pair.pair_type] ?? PAIR_TYPE_COLORS.uncertain;

  return (
    <>
      <motion.div
        className="absolute inset-0 bg-black/60 backdrop-blur-sm z-10"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        transition={{ duration: dur.normal, ease: easeOut }}
        onClick={onClose}
      />

      <motion.div
        className="absolute inset-0 z-20 overflow-y-auto bg-surface-0 rounded-xl"
        initial={{ opacity: 0, scale: 0.97, filter: "blur(8px)" }}
        animate={{ opacity: 1, scale: 1, filter: "blur(0px)" }}
        exit={{ opacity: 0, scale: 0.97, filter: "blur(8px)" }}
        transition={{
          ...springModal,
          opacity: { duration: dur.normal, ease: easeOut },
          filter: { duration: dur.exit, ease: easeOut },
          scale: { duration: dur.exit, ease: easeOut },
        }}
      >
        <div className="flex flex-col h-full">
          {/* Top: both fonts */}
          <div className="flex gap-8 px-8 py-6 border-b border-border-default">
            <FontInfoColumn font={primary} label="Primary" onUpdate={onUpdate} onAfterChange={onAfterChange} onToast={onToast} />
            <div className="w-px bg-border-default flex-shrink-0" />
            <FontInfoColumn font={candidate} label="Match" onUpdate={onUpdate} onAfterChange={onAfterChange} onToast={onToast} />
          </div>

          {/* Middle: multi-size preview */}
          <div className="flex-1 min-h-0 px-8 py-6 flex flex-col gap-6 overflow-y-auto">
            {[
              { label: "Display", size: displaySize },
              { label: "Heading", size: headingSize },
              { label: "Body", size: Math.max(bodySize, 12) },
            ].map(({ label, size }) => (
              <div key={label} className="flex items-baseline gap-4">
                <span className="text-xs text-fg-4 font-mono w-14 flex-shrink-0 text-right">{label}</span>
                <div className="flex-1 min-w-0 flex gap-6">
                  <span
                    className="flex-1 text-fg truncate"
                    style={{
                      fontFamily: fontFamily(primary.file_path),
                      fontSize: size,
                      fontWeight: controls.fontWeight,
                      letterSpacing: `${controls.letterSpacing}em`,
                    }}
                  >{display}</span>
                  <span
                    className="flex-1 text-fg truncate"
                    style={{
                      fontFamily: fontFamily(candidate.file_path),
                      fontSize: size,
                      fontWeight: controls.fontWeight,
                      letterSpacing: `${controls.letterSpacing}em`,
                    }}
                  >{display}</span>
                </div>
              </div>
            ))}

            {/* Reasoning callout */}
            <div className="bg-surface-1 rounded-lg p-5 mt-2">
              <div className="flex items-center gap-2 mb-3">
                <span className="text-xs text-fg-2 font-medium">Why this might work</span>
                <span
                  className="px-2 py-0.5 rounded-full text-[10px] font-medium uppercase tracking-wide"
                  style={{ backgroundColor: typeColors.bg, color: typeColors.text }}
                >{detailPairLabel(pair.pair_type)}</span>
              </div>
              <p className="text-xs text-fg-3 leading-relaxed mb-4">{pair.reason}</p>
              <div className="flex flex-col gap-1.5">
                {metrics.map((m) => (
                  <div key={m.label} className="flex items-center gap-2 text-xs">
                    <span className="text-fg-4 font-mono w-16">{m.label}:</span>
                    <span className="text-fg-3">{m.value}</span>
                    <span className={m.ok ? "text-green-400" : "text-fg-4"}>
                      {m.ok ? "\u2713" : ""}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Footer */}
          <div className="flex-shrink-0 flex items-center justify-between px-6 py-3 border-t border-border-default">
            <span className="text-[10px] text-fg-4 font-mono">{"\u2191\u2193 \u00B7 Esc"}</span>
            <div className="flex items-center gap-4">
              <button
                className="flex items-center gap-1 text-xs text-fg-3 font-mono hover:text-fg transition-colors cursor-pointer disabled:opacity-20 disabled:cursor-default"
                onClick={goPrev}
                disabled={currentIdx <= 0}
              >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><polyline points="15 18 9 12 15 6" /></svg>
                Prev
              </button>
              <span className="text-[10px] text-fg-4 font-mono tabular-nums">
                {currentIdx + 1} of {allPairs.length} in {currentBucketLabel}
              </span>
              <button
                className="flex items-center gap-1 text-xs text-fg-3 font-mono hover:text-fg transition-colors cursor-pointer disabled:opacity-20 disabled:cursor-default"
                onClick={goNext}
                disabled={currentIdx >= allPairs.length - 1}
              >
                Next
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><polyline points="9 18 15 12 9 6" /></svg>
              </button>
            </div>
            <button
              className={`flex items-center gap-1.5 text-xs font-mono transition-all cursor-pointer ${isStarred ? "opacity-100" : "opacity-40 hover:opacity-80"}`}
              style={{ color: isStarred ? "var(--c-star)" : undefined }}
              onClick={() => onToggleStar(candidate.file_path)}
            >
              <svg width="12" height="12" viewBox="0 0 24 24" fill={isStarred ? "currentColor" : "none"} stroke="currentColor" strokeWidth="1.75" strokeLinejoin="round">
                <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
              </svg>
              {isStarred ? "Starred" : "Star"}
            </button>
          </div>
        </div>
      </motion.div>
    </>
  );
}

// ── Left panel: compact font grid ─────────────────────────────────────────────

const LEFT_COL_COUNT = 2;
const LEFT_GAP = 8;

interface LeftCellData {
  fonts: FontInfo[];
  wordmark: string;
  logoSvg: string | null;
  logoScale: number;
  controls: Controls;
  starred: Set<string>;
  onToggleStar: (id: string) => void;
  onExclude: (filePath: string) => void;
  onHover: (filePath: string | null) => void;
  selectedFontPath: string | null;
  onSelect: (font: FontInfo) => void;
}

function LeftCell({
  columnIndex,
  rowIndex,
  style,
  fonts,
  wordmark,
  logoSvg,
  logoScale,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  selectedFontPath,
  onSelect,
}: CellComponentProps<LeftCellData>): React.ReactElement | null {
  const idx = rowIndex * LEFT_COL_COUNT + columnIndex;
  if (idx >= fonts.length) return null;
  const font = fonts[idx];
  const isSelected = selectedFontPath === font.file_path;

  return (
    <div
      style={{
        ...style,
        paddingRight: columnIndex === LEFT_COL_COUNT - 1 ? 0 : LEFT_GAP,
        paddingBottom: LEFT_GAP,
      }}
    >
      <div
        className={`h-full cursor-pointer transition-shadow rounded-lg ${
          isSelected ? "ring-2 ring-white shadow-lg" : "hover:ring-1 hover:ring-white/20"
        }`}
        onClick={() => onSelect(font)}
      >
        <FontCard
          font={font}
          wordmark={wordmark}
          logoSvg={logoSvg}
          logoScale={logoScale}
          controls={controls}
          starred={starred.has(font.file_path)}
          onToggleStar={() => onToggleStar(font.file_path)}
          onExclude={() => onExclude(font.file_path)}
          onHover={onHover}
        />
      </div>
    </div>
  );
}

function leftRowHeight(_rowIndex: number, data: LeftCellData): number {
  return Math.max(72, data.controls.fontSize + 56);
}

// ── Right panel: match card ───────────────────────────────────────────────────

function MatchCard({
  pair,
  font,
  wordmark,
  primaryFont,
  onClick,
  onUpdate,
  onAfterChange,
  onToast,
}: {
  pair: PairScore;
  font: FontDBRow | undefined;
  wordmark: string;
  primaryFont: FontInfo;
  onClick: () => void;
  onUpdate: (fontId: string, updates: FontUpdate) => Promise<void>;
  onAfterChange: () => void;
  onToast: (msg: string) => void;
}) {
  if (!font) return null;

  const typeColors = PAIR_TYPE_COLORS[pair.pair_type] ?? PAIR_TYPE_COLORS.uncertain;

  return (
    <div
      className="bg-surface-1 rounded-xl p-5 flex flex-col gap-3 cursor-pointer hover:ring-1 hover:ring-white/10 transition-shadow"
      onClick={onClick}
    >
      {/* Header row: name + badges */}
      <div className="flex items-center gap-2 flex-wrap">
        <span
          className="text-lg text-fg font-medium truncate"
          style={{ fontFamily: fontFamily(font.file_path) }}
        >
          {font.font_family}
        </span>
        <div onClick={(e) => e.stopPropagation()}>
          <SkeletonBadge font={font} onUpdate={onUpdate} onAfterChange={onAfterChange} onToast={onToast} size="sm" />
        </div>
        <span
          className="px-2 py-0.5 rounded-full text-[10px] font-medium tracking-wide"
          style={{ backgroundColor: typeColors.bg, color: typeColors.text }}
        >{shortTag(pair.pair_type)}</span>
      </div>

      {/* Reason */}
      <p className="text-xs text-fg-3 leading-relaxed">{pair.reason}</p>

      {/* Side-by-side preview */}
      <div className="flex gap-4 items-baseline pt-1">
        <div className="flex-1 min-w-0">
          <span className="text-[10px] text-fg-4 font-mono uppercase tracking-widest block mb-1">Primary</span>
          <span className="text-2xl text-fg truncate block" style={{ fontFamily: fontFamily(primaryFont.file_path) }}>{wordmark}</span>
        </div>
        <div className="w-px h-10 bg-border-default flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <span className="text-[10px] text-fg-4 font-mono uppercase tracking-widest block mb-1">Match</span>
          <span className="text-2xl text-fg truncate block" style={{ fontFamily: fontFamily(font.file_path) }}>{wordmark}</span>
        </div>
      </div>
    </div>
  );
}

// ── Primary font header ───────────────────────────────────────────────────────

function PrimaryHeader({
  font,
  onUpdate,
  onAfterChange,
  onToast,
}: {
  font: FontDBRow;
  onUpdate: (fontId: string, updates: FontUpdate) => Promise<void>;
  onAfterChange: () => void;
  onToast: (msg: string) => void;
}) {
  return (
    <div className="px-6 py-5 border-b border-border-default">
      <h2
        className="text-3xl text-fg font-medium mb-3 truncate"
        style={{ fontFamily: fontFamily(font.file_path) }}
      >
        {font.font_family}
      </h2>
      <div className="flex items-center gap-2 flex-wrap">
        <SkeletonBadge font={font} onUpdate={onUpdate} onAfterChange={onAfterChange} onToast={onToast} />
        <span className="px-2 py-0.5 rounded-md bg-white/5 text-[11px] text-fg-3 font-medium">
          {font.flesh_contrast === "contrasting" ? "Contrasting" : "Linear"}
        </span>
        <span className="px-2 py-0.5 rounded-md bg-white/5 text-[11px] text-fg-3 font-medium">
          {font.flesh_serif === 1 ? "Serif" : "Sans"}
        </span>
        {font.foundry && (
          <span className="text-[11px] text-fg-4 ml-1">
            {font.designer && font.designer !== font.foundry
              ? `${font.foundry} · ${font.designer}`
              : font.foundry}
          </span>
        )}
      </div>
    </div>
  );
}

// ── Main PairMode component ───────────────────────────────────────────────────

interface PairModeProps {
  /** Left panel: the browse list, with search and filters applied. */
  fonts: FontDBRow[];
  /** Every non-hidden font. Matches and the Primary resolve here, so browse filters never hide them. */
  libraryFonts: FontDBRow[];
  excludedIds: string[];
  /** Primary selection lives in App so it survives mode switches and Quick View can set it. */
  selectedId: string | null;
  onSelectPrimary: (fontId: string | null) => void;
  wordmark: string;
  logoSvg: string | null;
  logoScale: number;
  controls: Controls;
  starred: Set<string>;
  onToggleStar: (id: string) => void;
  onExclude: (filePath: string) => void;
  onHover: (filePath: string | null) => void;
  onUpdateClassification: (fontId: string, updates: FontUpdate) => Promise<void>;
  onToast: (msg: string) => void;
}

export function PairMode({
  fonts,
  libraryFonts,
  excludedIds,
  selectedId,
  onSelectPrimary,
  wordmark,
  logoSvg,
  logoScale,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  onUpdateClassification,
  onToast,
}: PairModeProps) {
  const [expandedIndex, setExpandedIndex] = useState<number | null>(null);

  const selectedFont = useMemo(
    () => libraryFonts.find((f) => f.font_id === selectedId) ?? null,
    [libraryFonts, selectedId],
  );

  const { buckets, allPairs, loading: pairsLoading, refresh: refreshPairs } = useFontPairs(selectedId, excludedIds);

  const fontById = useMemo(() => {
    const map = new Map<string, FontDBRow>();
    for (const f of libraryFonts) map.set(f.font_id, f);
    return map;
  }, [libraryFonts]);

  const handleSelectFromGrid = useCallback(
    (font: FontInfo) => {
      const dbFont = font as FontDBRow;
      onSelectPrimary(dbFont.font_id);
      setExpandedIndex(null);
    },
    [onSelectPrimary],
  );

  const handleAfterSkeletonChange = useCallback(() => {
    refreshPairs();
  }, [refreshPairs]);

  // Compute a flat index for a pair within allPairs
  const flatIndexOf = useCallback(
    (fontId: string) => allPairs.findIndex((p) => p.font_id === fontId),
    [allPairs],
  );

  const display = wordmark || "Fontdrop";
  const rowCount = Math.ceil(fonts.length / LEFT_COL_COUNT);
  const hasBuckets = buckets.length > 0;

  return (
    <div className="flex-1 min-h-0 flex">
      {/* Left panel */}
      <LeftPanel
        fonts={fonts}
        wordmark={display}
        logoSvg={logoSvg}
        logoScale={logoScale}
        controls={controls}
        starred={starred}
        onToggleStar={onToggleStar}
        onExclude={onExclude}
        onHover={onHover}
        selectedFontPath={selectedFont?.file_path ?? null}
        onSelect={handleSelectFromGrid}
        rowCount={rowCount}
      />

      {/* Right panel */}
      <div className="flex-1 min-w-0 relative" style={{ width: "60%" }}>
        <div className="absolute inset-0 overflow-y-auto">
          {!selectedFont && (
            <div className="h-full flex flex-col items-center justify-center gap-3 px-8">
              <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="text-fg-4">
                <line x1="19" y1="12" x2="5" y2="12" />
                <polyline points="12 19 5 12 12 5" />
              </svg>
              <span className="text-fg-4 text-sm text-center">Pick a font on the left to see what plays well with it</span>
            </div>
          )}

          {selectedFont && (
            <>
              <PrimaryHeader
                font={selectedFont}
                onUpdate={onUpdateClassification}
                onAfterChange={handleAfterSkeletonChange}
                onToast={onToast}
              />

              <div className="p-6 flex flex-col gap-6">
                {pairsLoading && (
                  <div className="py-12 text-center">
                    <span className="text-fg-3 text-sm animate-pulse">Scoring…</span>
                  </div>
                )}

                {!pairsLoading && !hasBuckets && (
                  <div className="py-12 text-center flex flex-col gap-2">
                    <span className="text-fg-3 text-sm">Nothing obvious here — try setting the skeleton manually</span>
                    <span className="text-fg-4 text-xs">Click the skeleton badge above to classify this font.</span>
                  </div>
                )}

                {!pairsLoading &&
                  buckets.map((bucket, bi) => (
                    <div key={bucket.label}>
                      {/* Section separator (not on first bucket) */}
                      {bi > 0 && <div className="h-px bg-border-default mb-6" />}

                      {/* Section header */}
                      <div className="mb-4">
                        <h3 className="text-sm text-fg font-medium">{bucket.label}</h3>
                        <p className="text-xs text-fg-4 mt-0.5">{bucket.description}</p>
                      </div>

                      {/* Cards */}
                      <div className="flex flex-col gap-3">
                        {bucket.pairs.map((pair) => (
                          <MatchCard
                            key={pair.font_id}
                            pair={pair}
                            font={fontById.get(pair.font_id)}
                            wordmark={display}
                            primaryFont={selectedFont}
                            onClick={() => setExpandedIndex(flatIndexOf(pair.font_id))}
                            onUpdate={onUpdateClassification}
                            onAfterChange={handleAfterSkeletonChange}
                            onToast={onToast}
                          />
                        ))}
                      </div>
                    </div>
                  ))}
              </div>
            </>
          )}
        </div>

        <AnimatePresence>
          {expandedIndex !== null && selectedFont && allPairs.length > 0 && (
            <PairDetailView
              primary={selectedFont}
              allPairs={allPairs}
              buckets={buckets}
              fontById={fontById}
              wordmark={display}
              controls={controls}
              starred={starred}
              onToggleStar={onToggleStar}
              onClose={() => setExpandedIndex(null)}
              initialIndex={expandedIndex}
              onUpdate={onUpdateClassification}
              onAfterChange={handleAfterSkeletonChange}
              onToast={onToast}
            />
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// ── Left panel wrapper ────────────────────────────────────────────────────────

function LeftPanel({
  fonts,
  wordmark,
  logoSvg,
  logoScale,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  selectedFontPath,
  onSelect,
  rowCount,
}: LeftCellData & { rowCount: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });

  useEffect(() => {
    if (!ref.current) return;
    const obs = new ResizeObserver((entries) => {
      for (const entry of entries) {
        setSize({ width: entry.contentRect.width, height: entry.contentRect.height });
      }
    });
    obs.observe(ref.current);
    return () => obs.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      className="flex-shrink-0 border-r border-border-default overflow-hidden px-2 pt-2"
      style={{ width: "40%" }}
    >
      {size.width > 0 && size.height > 0 && (
        <Grid
          columnCount={LEFT_COL_COUNT}
          rowCount={rowCount}
          columnWidth={`${100 / LEFT_COL_COUNT}%`}
          rowHeight={leftRowHeight}
          overscanCount={2}
          cellComponent={LeftCell}
          cellProps={{
            fonts, wordmark, logoSvg, logoScale, controls,
            starred, onToggleStar, onExclude, onHover,
            selectedFontPath, onSelect,
          }}
          style={{ overflowX: "hidden" }}
        />
      )}
    </div>
  );
}
