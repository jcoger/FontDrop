import { memo } from "react";
import { fontFamily } from "../lib/fontFace";
import type { FontInfo } from "../hooks/useFonts";
import type { Controls } from "../types/controls";

interface Props {
  font: FontInfo;
  wordmark: string;
  logoSvg: string | null;
  logoScale: number;
  controls: Controls;
  starred: boolean;
  onToggleStar: () => void;
  onExclude: () => void;
  onHover?: (filePath: string | null) => void;
  onSelect?: (font: FontInfo, rect: DOMRect) => void;
  isSelected?: boolean;
}

function StarIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      width="13"
      height="13"
      viewBox="0 0 24 24"
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinejoin="round"
    >
      <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
    </svg>
  );
}

function XIcon() {
  return (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  );
}

export const FontCard = memo(function FontCard({
  font,
  wordmark,
  logoSvg,
  logoScale,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  onSelect,
  isSelected,
}: Props) {
  const { fontSize, letterSpacing, fontWeight, bgColor, fgColor } = controls;

  // When selected for quick view, render invisible placeholder to preserve layout space
  if (isSelected) {
    return <div className="w-full h-full rounded-lg" style={{ backgroundColor: bgColor, opacity: 0 }} />;
  }

  const logoH = Math.max(Math.round(fontSize * logoScale), 16);

  return (
    <div
      className="relative group rounded-lg p-4 h-full flex flex-col gap-2 overflow-hidden cursor-pointer
                 outline outline-1 outline-transparent hover:outline-neutral-700 transition-all"
      style={{ backgroundColor: bgColor }}
      onMouseEnter={() => onHover?.(font.file_path)}
      onMouseLeave={() => onHover?.(null)}
      onClick={(e) => {
        onSelect?.(font, e.currentTarget.getBoundingClientRect());
      }}
    >
      {/* X (exclude) button — top-left, hover-only */}
      <button
        className="absolute top-2 left-2 z-10 opacity-0 group-hover:opacity-100
                   text-neutral-600 hover:text-red-400 transition-all cursor-pointer"
        onClick={(e) => {
          e.stopPropagation();
          onExclude();
        }}
        aria-label="Hide font"
      >
        <XIcon />
      </button>

      {/* Star button — top-right, always visible when starred */}
      <button
        className={[
          "absolute top-2 right-2 z-10 transition-all cursor-pointer",
          starred
            ? "opacity-100 text-yellow-400"
            : "opacity-0 group-hover:opacity-100 text-neutral-500 hover:text-yellow-400",
        ].join(" ")}
        onClick={(e) => {
          e.stopPropagation();
          onToggleStar();
        }}
        aria-label={starred ? "Remove from starred" : "Add to starred"}
      >
        <StarIcon filled={starred} />
      </button>

      {/* Logo + wordmark */}
      <div className="flex-1 flex items-center gap-3 overflow-hidden min-w-0 min-h-0">
        {logoSvg && (
          <div
            className="flex-shrink-0"
            style={{ height: logoH, color: fgColor }}
            dangerouslySetInnerHTML={{ __html: logoSvg }}
          />
        )}
        <p
          className="leading-none min-w-0"
          style={{
            fontFamily: fontFamily(font.file_path),
            fontSize,
            fontWeight,
            letterSpacing: `${letterSpacing}em`,
            color: fgColor,
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
          }}
        >
          {wordmark}
        </p>
      </div>

      {/* Family name */}
      <p
        className="flex-shrink-0 text-xs font-mono truncate"
        style={{ color: fgColor, opacity: 0.4 }}
      >
        {font.font_family}
      </p>
    </div>
  );
});
