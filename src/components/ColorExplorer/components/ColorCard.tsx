import { useState } from "react";
import { fontFamily } from "../../../lib/fontFace";
import type { FontInfo } from "../../../hooks/useFonts";
import type { OklchColor } from "../../../utils/oklch";
import { oklchToCss, contrastRatio } from "../../../utils/oklch";
import type { ContrastLevel } from "../types";

interface ColorCardProps {
  font: FontInfo | null;
  bgColor: OklchColor;
  fgColor: string;
  fgOklch: OklchColor;
  badge: string;
  badgeColor?: string;
  isWorking: boolean;
  isPulsing?: boolean;
  isSpotlight?: boolean;
  dimmed?: boolean;
  brandName?: string;
  logoSvg?: string | null;
  isLogoCard?: boolean;
  contrastLevel: ContrastLevel;
  /** Index for stagger delay on color transitions during drag */
  cardIndex?: number;
  /** Pinned font for spotlight card */
  pinnedFont?: FontInfo | null;
  /** Starred fonts for the font pin dropdown */
  starredFonts?: FontInfo[];
  onPinFont?: (font: FontInfo | null) => void;
  onClick: () => void;
  onDoubleClick?: () => void;
  /** Flip bg/fg on this card (Macro Knob only) */
  onFlip?: () => void;
  /** Neutral color for secondary text (font name, badges). When set, only the brand name uses fgColor. */
  metaColor?: string;
  /** Save/unsave this card to collection */
  isSaved?: boolean;
  onSave?: () => "added" | "duplicate" | void;
  onUnsave?: () => void;
}

export function ColorCard({
  font,
  bgColor,
  fgColor,
  fgOklch,
  badge,
  badgeColor,
  isWorking,
  isPulsing,
  isSpotlight,
  dimmed,
  brandName,
  logoSvg,
  isLogoCard,
  contrastLevel,
  cardIndex = 0,
  pinnedFont,
  starredFonts,
  onPinFont,
  onClick,
  onDoubleClick,
  onFlip,
  metaColor,
  isSaved,
  onSave,
  onUnsave,
}: ColorCardProps) {
  const [showFontPicker, setShowFontPicker] = useState(false);
  const [savePulse, setSavePulse] = useState(false);

  // The font to render: pinned font overrides cycling font
  const renderFont = pinnedFont || font;
  const displayText = brandName || (renderFont ? renderFont.font_family : "");
  const bgCss = oklchToCss(bgColor);

  // Contrast overlay badge — informational, not a verdict
  const ratio = contrastRatio(bgColor, fgOklch);
  const contrastBadge = (() => {
    if (contrastLevel === "clash") {
      return { text: `${ratio.toFixed(1)}  CLASH ⚡`, pass: true };
    }
    const levelLabel = contrastLevel === "accessible" ? "ACCESSIBLE" : "DISPLAY";
    return { text: `${ratio.toFixed(1)}  ${levelLabel}`, pass: true };
  })();

  // Spotlight glow: card's own color as the glow source
  const spotlightShadow = isSpotlight
    ? `0 0 0 2px ${bgCss}, 0 0 20px 8px ${bgCss}80`
    : undefined;

  // Combined shadow: spotlight wins over working
  const shadow = spotlightShadow
    || (isWorking ? "0 0 0 2px rgba(217,119,54,0.6), 0 0 12px rgba(217,119,54,0.2), 0 10px 15px -3px rgba(0,0,0,0.3)" : undefined);

  return (
    <div
      className="group aspect-[4/3] rounded-xl p-5 flex flex-col justify-between relative cursor-pointer shadow-lg"
      style={{
        backgroundColor: bgCss,
        color: fgColor,
        boxShadow: shadow,
        opacity: dimmed ? 0.3 : 1,
        filter: dimmed ? "saturate(0.3)" : undefined,
        transform: isSpotlight ? "scale(1.02)" : isPulsing ? "scale(1.02)" : "scale(1)",
        zIndex: isSpotlight ? 10 : undefined,
        transition: `background-color 80ms ease ${cardIndex * 25}ms, color 80ms ease ${cardIndex * 25}ms, transform var(--dur-normal) var(--ease-hover), box-shadow var(--dur-normal) var(--ease-hover), opacity var(--dur-normal) var(--ease-hover), filter var(--dur-normal) var(--ease-hover)`,
      }}
      onClick={onClick}
      onDoubleClick={(e) => { e.stopPropagation(); onDoubleClick?.(); }}
    >
      {/* Save button + Contrast badge — top-left */}
      <div className="absolute top-4 left-4 flex items-center gap-1.5">
        {(onSave || onUnsave) && (
          <button
            className={`w-6 h-6 rounded flex items-center justify-center backdrop-blur-sm border cursor-pointer transition-all ${isSaved ? "opacity-100" : "opacity-0 group-hover:opacity-100"}`}
            style={{
              background: isSaved ? "rgba(255,255,255,0.20)" : "rgba(0,0,0,0.20)",
              borderColor: isSaved ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.08)",
              color: isSaved ? "#ffffff" : (metaColor || "rgba(255,255,255,0.55)"),
              transform: savePulse ? "scale(1.2)" : "scale(1)",
            }}
            onClick={(e) => {
              e.stopPropagation();
              if (isSaved) {
                onUnsave?.();
              } else {
                const result = onSave?.();
                // Pulse if duplicate
                if (result === "duplicate" || isSaved) {
                  setSavePulse(true);
                  setTimeout(() => setSavePulse(false), 200);
                }
              }
            }}
            aria-label={isSaved ? "Remove from collection" : "Save to collection"}
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill={isSaved ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
            </svg>
          </button>
        )}
        <div
          className="px-2 py-0.5 rounded font-mono backdrop-blur-sm border"
          style={{
            fontSize: "var(--text-badge)",
            background: "rgba(0,0,0,0.15)",
            borderColor: "rgba(0,0,0,0.05)",
            color: metaColor || "rgba(255,255,255,0.55)",
          }}
        >
          {contrastBadge.text}
        </div>
      </div>

      {/* Method badge — top-right */}
      <div className="absolute top-4 right-4 flex items-center gap-1.5">
        {onFlip && (
          <button
            className="w-6 h-6 rounded flex items-center justify-center backdrop-blur-sm border cursor-pointer opacity-0 group-hover:opacity-100 transition-opacity"
            style={{
              background: "rgba(0,0,0,0.20)",
              borderColor: "rgba(0,0,0,0.08)",
              color: fgColor,
            }}
            onClick={(e) => { e.stopPropagation(); onFlip(); }}
            aria-label="Flip background and foreground"
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M7 3v18" /><path d="M3 7l4-4 4 4" /><path d="M17 21V3" /><path d="M21 17l-4 4-4-4" />
            </svg>
          </button>
        )}
        <div
          className="px-2 py-0.5 rounded font-mono backdrop-blur-sm border uppercase"
          style={{
            fontSize: "var(--text-badge)",
            letterSpacing: "var(--track-caps)",
            background: "rgba(0,0,0,0.15)",
            borderColor: "rgba(0,0,0,0.05)",
            color: badgeColor || metaColor || fgColor,
          }}
        >
          {badge}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 flex items-center justify-center overflow-hidden">
        {isLogoCard && logoSvg ? (
          <div className="flex flex-col items-center gap-2">
            <div
              className="h-12 flex items-center justify-center"
              style={{ color: fgColor }}
              dangerouslySetInnerHTML={{ __html: logoSvg }}
            />
            {displayText && (
              <span className="text-[18px] font-semibold tracking-tight leading-none text-center truncate max-w-full px-2">
                {displayText}
              </span>
            )}
          </div>
        ) : (
          <span
            className="text-[42px] tracking-tight leading-none text-center truncate max-w-full px-2"
            style={renderFont ? { fontFamily: fontFamily(renderFont.file_path) } : undefined}
          >
            {displayText}
          </span>
        )}
      </div>

      {/* Font info — uses metaColor for secondary readability */}
      <div className="relative">
        <div className="font-medium truncate" style={{ fontSize: "var(--text-ui)", color: metaColor || undefined, opacity: metaColor ? 1 : 0.9 }}>
          {isLogoCard ? "Logo" : renderFont ? renderFont.font_family : ""}
        </div>
        <div className="font-mono mt-0.5" style={{ fontSize: "var(--text-label)", color: metaColor || undefined, opacity: metaColor ? 0.7 : 0.6 }}>
          {isLogoCard ? "Brand Mark" : renderFont ? `${renderFont.weight} · ${renderFont.classification.category}` : ""}
        </div>

        {/* Pinned font indicator dot — bottom-right */}
        {pinnedFont && !isLogoCard && (
          <button
            className="absolute -bottom-1 -right-1 w-2.5 h-2.5 rounded-full bg-white/80 cursor-pointer hover:bg-white transition-colors"
            style={{ boxShadow: "0 0 3px rgba(0,0,0,0.4)" }}
            onClick={(e) => { e.stopPropagation(); onPinFont?.(null); }}
            title="Unpin font"
          />
        )}
      </div>

      {/* Font pin hover pill — spotlight only */}
      {isSpotlight && !isLogoCard && starredFonts && starredFonts.length > 0 && (
        <div className="absolute -bottom-3 left-1/2 -translate-x-1/2 opacity-0 group-hover:opacity-100 transition-opacity z-20"
          style={{ pointerEvents: "none" }}>
          {/* We use a wrapper that captures hover from the card's group class */}
        </div>
      )}

      {/* Font pin pill — visible on hover for spotlighted card */}
      {isSpotlight && !isLogoCard && (
        <div className="absolute bottom-2 right-2 opacity-0 hover:opacity-100 transition-opacity" style={{ opacity: showFontPicker ? 1 : undefined }}>
          <button
            className="px-2 py-0.5 rounded font-mono backdrop-blur-sm border cursor-pointer"
            style={{
              fontSize: "var(--text-badge)",
              background: "rgba(0,0,0,0.3)",
              borderColor: "rgba(0,0,0,0.1)",
              color: fgColor,
            }}
            onClick={(e) => { e.stopPropagation(); setShowFontPicker(!showFontPicker); }}
          >
            <span className="mr-1">↻</span>Font
          </button>

          {/* Font picker dropdown */}
          {showFontPicker && starredFonts && starredFonts.length > 0 && (
            <div
              className="absolute bottom-full right-0 mb-1 w-48 max-h-40 overflow-y-auto rounded-lg border border-neutral-700 bg-neutral-900 shadow-xl z-30"
              style={{ scrollbarWidth: "thin" }}
              onClick={(e) => e.stopPropagation()}
            >
              {starredFonts.map((sf) => (
                <button
                  key={sf.file_path}
                  className="w-full text-left px-3 py-1.5 font-mono truncate cursor-pointer transition-colors hover:bg-white/5"
                  style={{
                    fontSize: "var(--text-body)",
                    color: sf.file_path === renderFont?.file_path ? "var(--c-text)" : "var(--c-text-2)",
                    fontFamily: fontFamily(sf.file_path),
                  }}
                  onClick={() => { onPinFont?.(sf); setShowFontPicker(false); }}
                >
                  {sf.font_family}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
