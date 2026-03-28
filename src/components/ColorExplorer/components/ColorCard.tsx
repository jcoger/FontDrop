import { useState, useCallback, useMemo } from "react";
import { fontFamily } from "../../../lib/fontFace";
import type { FontInfo } from "../../../hooks/useFonts";
import type { OklchColor } from "../../../utils/oklch";
import { oklchToCss, contrastRatio } from "../../../utils/oklch";
import type { ContrastLevel } from "../types";

// ── Types ────────────────────────────────────────────────────────────

interface ColorCardProps {
  /** Font assigned to this card (null for logo cards) */
  font: FontInfo | null;
  bgColor: OklchColor;
  fgColor: string;
  fgOklch: OklchColor;
  contrastLevel: ContrastLevel;
  /** Stagger index for color transition delay */
  cardIndex?: number;

  // Visual states
  isWorking?: boolean;
  isPulsing?: boolean;
  isSpotlight?: boolean;
  dimmed?: boolean;

  // Brand / logo
  brandName?: string;
  logoSvg?: string | null;
  isLogoCard?: boolean;

  // Spotlight: pinned font + picker
  pinnedFont?: FontInfo | null;
  starredFonts?: FontInfo[];
  onPinFont?: (font: FontInfo | null) => void;

  // Flip (Macro Knob / Hue Lock)
  onFlip?: () => void;

  // Actions
  onSave?: () => "added" | "duplicate" | void;
  onUnsave?: () => void;
  isSaved?: boolean;
  onDoubleClick?: () => void;
}

// ── Shared styles ────────────────────────────────────────────────────

const OVERLAY_BG = "rgba(0,0,0,0.15)";
const OVERLAY_BORDER = "rgba(0,0,0,0.05)";
const MUTED_COLOR = "rgba(255,255,255,0.45)";

// ── Icons (static SVG fragments) ─────────────────────────────────────

function BookmarkIcon({ filled }: { filled: boolean }) {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill={filled ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
    </svg>
  );
}

function FlipIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M7 3v18" /><path d="M3 7l4-4 4 4" /><path d="M17 21V3" /><path d="M21 17l-4 4-4-4" />
    </svg>
  );
}

// ── Sub-components ───────────────────────────────────────────────────

function HoverBadge({ children, style }: { children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div
      className="px-1.5 py-0.5 rounded font-mono backdrop-blur-sm border"
      style={{
        fontSize: "var(--text-badge)",
        background: OVERLAY_BG,
        borderColor: OVERLAY_BORDER,
        color: MUTED_COLOR,
        ...style,
      }}
    >
      {children}
    </div>
  );
}

function HoverButton({ onClick, label, children }: { onClick: (e: React.MouseEvent) => void; label: string; children: React.ReactNode }) {
  return (
    <button
      className="w-6 h-6 rounded flex items-center justify-center backdrop-blur-sm border cursor-pointer transition-opacity"
      style={{ background: OVERLAY_BG, borderColor: OVERLAY_BORDER, color: MUTED_COLOR }}
      onClick={onClick}
      aria-label={label}
    >
      {children}
    </button>
  );
}

/** Font picker dropdown for spotlight cards */
function FontPicker({
  fonts,
  currentPath,
  fgColor,
  onPick,
  onClose,
}: {
  fonts: FontInfo[];
  currentPath: string | undefined;
  fgColor: string;
  onPick: (font: FontInfo) => void;
  onClose: () => void;
}) {
  if (fonts.length === 0) return null;

  return (
    <div className="absolute bottom-2 right-2 z-20">
      <button
        className="px-2 py-0.5 rounded font-mono backdrop-blur-sm border cursor-pointer"
        style={{ fontSize: "var(--text-badge)", background: "rgba(0,0,0,0.3)", borderColor: "rgba(0,0,0,0.1)", color: fgColor }}
        onClick={(e) => { e.stopPropagation(); onClose(); }}
      >
        <span className="mr-1">↻</span>Font
      </button>
      <div
        className="absolute bottom-full right-0 mb-1 w-48 max-h-40 overflow-y-auto rounded-lg border border-border-strong bg-surface-1 shadow-xl"
        style={{ scrollbarWidth: "thin" }}
        onClick={(e) => e.stopPropagation()}
      >
        {fonts.map((sf) => (
          <button
            key={sf.file_path}
            className="w-full text-left px-3 py-1.5 font-mono truncate cursor-pointer transition-colors hover:bg-white/5"
            style={{
              fontSize: "var(--text-body)",
              color: sf.file_path === currentPath ? "var(--c-text)" : "var(--c-text-2)",
              fontFamily: fontFamily(sf.file_path),
            }}
            onClick={() => onPick(sf)}
          >
            {sf.font_family}
          </button>
        ))}
      </div>
    </div>
  );
}

// ── Main component ───────────────────────────────────────────────────

export function ColorCard({
  font,
  bgColor,
  fgColor,
  fgOklch,
  contrastLevel,
  cardIndex = 0,
  isWorking,
  isPulsing,
  isSpotlight,
  dimmed,
  brandName,
  logoSvg,
  isLogoCard,
  pinnedFont,
  starredFonts,
  onPinFont,
  onFlip,
  onSave,
  onUnsave,
  isSaved,
  onDoubleClick,
}: ColorCardProps) {
  const [showFontPicker, setShowFontPicker] = useState(false);
  const [savePulse, setSavePulse] = useState(false);

  // ── Derived values ─────────────────────────────────────────────────

  const renderFont = pinnedFont || font;
  const displayText = brandName || (renderFont ? renderFont.font_family : "");
  const bgCss = oklchToCss(bgColor);
  const ratio = contrastRatio(bgColor, fgOklch);
  const canSave = !!(onSave || onUnsave);

  const contrastLabel = useMemo(() => {
    if (contrastLevel === "clash") return `${ratio.toFixed(1)} CLASH`;
    return `${ratio.toFixed(1)} ${contrastLevel === "accessible" ? "AA" : "DIS"}`;
  }, [ratio, contrastLevel]);

  // ── Shadows ────────────────────────────────────────────────────────

  const shadow = useMemo(() => {
    if (isSpotlight) return `0 0 0 2px ${bgCss}, 0 0 20px 8px ${bgCss}80`;
    if (isWorking) return "0 0 0 2px rgba(217,119,54,0.6), 0 0 12px rgba(217,119,54,0.2), 0 10px 15px -3px rgba(0,0,0,0.3)";
    return undefined;
  }, [isSpotlight, isWorking, bgCss]);

  // ── Handlers ───────────────────────────────────────────────────────

  const handleClick = useCallback((e: React.MouseEvent) => {
    // Single click = save/unsave
    if (!canSave) return;
    e.stopPropagation();
    if (isSaved) {
      onUnsave?.();
    } else {
      const result = onSave?.();
      if (result === "duplicate") {
        setSavePulse(true);
        setTimeout(() => setSavePulse(false), 200);
      }
    }
  }, [canSave, isSaved, onSave, onUnsave]);

  const handleDoubleClick = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    onDoubleClick?.();
  }, [onDoubleClick]);

  const handleFlip = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    onFlip?.();
  }, [onFlip]);

  const handleFontPick = useCallback((sf: FontInfo) => {
    onPinFont?.(sf);
    setShowFontPicker(false);
  }, [onPinFont]);

  // ── Scale ──────────────────────────────────────────────────────────

  const scale = isSpotlight || isPulsing ? 1.02 : 1;

  // ── Render ─────────────────────────────────────────────────────────

  return (
    <div
      className="@container group aspect-[4/3] rounded-xl flex flex-col justify-between relative cursor-pointer shadow-lg"
      style={{
        backgroundColor: bgCss,
        color: fgColor,
        boxShadow: shadow,
        opacity: dimmed ? 0.3 : 1,
        filter: dimmed ? "saturate(0.3)" : undefined,
        transform: `scale(${scale})`,
        zIndex: isSpotlight ? 10 : undefined,
        padding: "clamp(12px, 6%, 24px)",
        transition: `background-color 80ms ease ${cardIndex * 25}ms, color 80ms ease ${cardIndex * 25}ms, transform var(--dur-normal) var(--ease-hover), box-shadow var(--dur-normal) var(--ease-hover), opacity var(--dur-normal) var(--ease-hover), filter var(--dur-normal) var(--ease-hover)`,
      }}
      onClick={handleClick}
      onDoubleClick={handleDoubleClick}
    >
      {/* ── Hover overlay: contrast + flip ─────────────────────────── */}
      <div className="absolute inset-x-0 top-0 flex items-center justify-between opacity-0 group-hover:opacity-100 transition-opacity" style={{ padding: "inherit" }}>
        <HoverBadge>{contrastLabel}</HoverBadge>
        {onFlip && (
          <HoverButton onClick={handleFlip} label="Flip background and foreground">
            <FlipIcon />
          </HoverButton>
        )}
      </div>

      {/* ── Saved indicator ─────────────────────────────────────────── */}
      {isSaved && (
        <div className="absolute top-3 right-3">
          <div className="w-5 h-5 rounded flex items-center justify-center" style={{ color: fgColor, opacity: 0.7 }}>
            <BookmarkIcon filled />
          </div>
        </div>
      )}

      {/* ── Center content ─────────────────────────────────────────── */}
      <div className="flex-1 flex items-center justify-center overflow-hidden">
        {isLogoCard && logoSvg ? (
          <div className="flex flex-col items-center gap-2">
            <div
              className="flex items-center justify-center"
              style={{ color: fgColor, height: "clamp(32px, 8cqi, 64px)" }}
              dangerouslySetInnerHTML={{ __html: logoSvg }}
            />
            {displayText && (
              <span
                className="font-semibold tracking-tight leading-none text-center truncate max-w-full px-2"
                style={{ fontSize: "clamp(14px, 4.5cqi, 24px)" }}
              >
                {displayText}
              </span>
            )}
          </div>
        ) : (
          <span
            className="tracking-tight leading-none text-center truncate max-w-full px-2"
            style={{
              fontSize: "clamp(24px, 10cqi, 56px)",
              fontFamily: renderFont ? fontFamily(renderFont.file_path) : undefined,
            }}
          >
            {displayText}
          </span>
        )}
      </div>

      {/* ── Bottom: font info + save pulse ─────────────────────────── */}
      <div className="relative flex items-end justify-between gap-2">
        <div className="min-w-0">
          <div className="font-medium truncate" style={{ fontSize: "var(--text-ui)", opacity: 0.9 }}>
            {isLogoCard ? "Logo" : renderFont?.font_family ?? ""}
          </div>
          <div className="font-mono mt-0.5" style={{ fontSize: "var(--text-label)", opacity: 0.6 }}>
            {isLogoCard ? "Brand Mark" : renderFont ? `${renderFont.weight} · ${renderFont.classification.category}` : ""}
          </div>
        </div>

        {/* Pinned font dot */}
        {pinnedFont && !isLogoCard && (
          <button
            className="w-2.5 h-2.5 rounded-full bg-white/80 flex-shrink-0 cursor-pointer hover:bg-white transition-colors"
            style={{ boxShadow: "0 0 3px rgba(0,0,0,0.4)" }}
            onClick={(e) => { e.stopPropagation(); onPinFont?.(null); }}
            title="Unpin font"
          />
        )}
      </div>

      {/* ── Save pulse overlay ─────────────────────────────────────── */}
      {savePulse && (
        <div
          className="absolute inset-0 rounded-xl pointer-events-none"
          style={{
            boxShadow: `inset 0 0 0 2px ${fgColor}40`,
            animation: "pulse-border 200ms ease-out",
          }}
        />
      )}

      {/* ── Spotlight font picker ──────────────────────────────────── */}
      {isSpotlight && !isLogoCard && showFontPicker && starredFonts && (
        <FontPicker
          fonts={starredFonts}
          currentPath={renderFont?.file_path}
          fgColor={fgColor}
          onPick={handleFontPick}
          onClose={() => setShowFontPicker(false)}
        />
      )}

      {/* Font picker trigger (hover only, spotlight only) */}
      {isSpotlight && !isLogoCard && starredFonts && starredFonts.length > 0 && !showFontPicker && (
        <div className="absolute bottom-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity">
          <button
            className="px-2 py-0.5 rounded font-mono backdrop-blur-sm border cursor-pointer"
            style={{ fontSize: "var(--text-badge)", background: "rgba(0,0,0,0.3)", borderColor: "rgba(0,0,0,0.1)", color: fgColor }}
            onClick={(e) => { e.stopPropagation(); setShowFontPicker(true); }}
          >
            <span className="mr-1">↻</span>Font
          </button>
        </div>
      )}
    </div>
  );
}
