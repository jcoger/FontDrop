import React from "react";
import { List, RowComponentProps } from "react-window";
import { fontFamily } from "../lib/fontFace";
import { weightLabel } from "../lib/fontFamilies";
import type { FontFamily } from "../lib/fontFamilies";
import type { FontInfo } from "../hooks/useFonts";
import type { Controls } from "../types/controls";

type FamilyRow =
  | { type: "family"; family: FontFamily }
  | { type: "variant"; font: FontInfo; familyName: string };

interface ListData {
  rows: FamilyRow[];
  wordmark: string;
  logoSvg: string | null;
  logoScale: number;
  controls: Controls;
  starred: Set<string>;
  onToggleStar: (id: string) => void;
  onExclude: (filePath: string) => void;
  onHover: (filePath: string | null) => void;
  onSelect?: (font: FontInfo, rect: DOMRect) => void;
  selectedFontPath?: string | null;
  expandedFamilies: Set<string>;
  onToggleFamily: (name: string) => void;
}

function rowHeight(index: number, data: ListData): number {
  const row = data.rows[index];
  const fs = data.controls.fontSize;
  return row?.type === "variant"
    ? Math.max(52, fs + 30)
    : Math.max(64, fs + 44);
}

function ChevronIcon({ open }: { open: boolean }) {
  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ transform: open ? "rotate(90deg)" : "rotate(0deg)", transition: "transform var(--dur-fast) var(--ease-out)" }}
    >
      <polyline points="9 18 15 12 9 6" />
    </svg>
  );
}

function FamilyRowItem({
  family,
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
  isExpanded,
  onToggle,
}: {
  family: FontFamily;
  wordmark: string;
  logoSvg: string | null;
  logoScale: number;
  controls: Controls;
  starred: boolean;
  onToggleStar: () => void;
  onExclude: () => void;
  onHover: (filePath: string | null) => void;
  onSelect?: (font: FontInfo, rect: DOMRect) => void;
  isSelected?: boolean;
  isExpanded: boolean;
  onToggle: () => void;
}) {
  const { fontSize, letterSpacing, fontWeight, bgColor, fgColor } = controls;
  const rep = family.representative;

  if (isSelected) {
    return <div className="h-full border-b border-border-default/60" style={{ backgroundColor: bgColor, opacity: 0 }} />;
  }

  const logoH = Math.max(Math.round(fontSize * logoScale), 16);

  return (
    <div
      className="relative group flex items-center gap-3 px-4 h-full border-b border-border-default/60 cursor-pointer
                 hover:bg-white/[0.02] transition-colors"
      style={{ backgroundColor: bgColor }}
      onMouseEnter={() => onHover(rep.file_path)}
      onMouseLeave={() => onHover(null)}
      onClick={(e) => {
        if ((e.target as HTMLElement).closest("button")) return;
        onSelect?.(rep, e.currentTarget.getBoundingClientRect());
      }}
    >
      {/* X (exclude) button */}
      <button
        className="opacity-0 group-hover:opacity-100 text-fg-3 hover:text-red-400
                   transition-all cursor-pointer flex-shrink-0"
        onClick={(e) => { e.stopPropagation(); onExclude(); }}
        aria-label="Hide font family"
      >
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>

      {/* Logo (optional) */}
      {logoSvg && (
        <div
          className="flex-shrink-0"
          style={{ height: logoH, color: fgColor }}
          dangerouslySetInnerHTML={{ __html: logoSvg }}
        />
      )}

      {/* Preview wordmark */}
      <p
        className="flex-1 min-w-0 leading-none overflow-hidden"
        style={{
          fontFamily: fontFamily(rep.file_path),
          fontSize,
          fontWeight,
          letterSpacing: `${letterSpacing}em`,
          color: fgColor,
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
        }}
      >
        {wordmark}
      </p>

      {/* Family meta */}
      <div className="flex flex-col items-end gap-1 flex-shrink-0">
        <span className="text-[11px] font-mono" style={{ color: fgColor, opacity: 0.5 }}>
          {family.name}
        </span>
        <button
          className="text-[length:var(--text-label)] text-fg-3 hover:text-fg-2 cursor-pointer transition-colors font-mono"
          onClick={(e) => { e.stopPropagation(); onToggle(); }}
        >
          {family.fonts.length} variants
        </button>
      </div>

      {/* Expand chevron */}
      <button
        className="flex-shrink-0 text-fg-4 hover:text-fg-2 cursor-pointer transition-colors"
        onClick={(e) => { e.stopPropagation(); onToggle(); }}
        aria-label={isExpanded ? "Collapse variants" : "Expand variants"}
      >
        <ChevronIcon open={isExpanded} />
      </button>

      {/* Star button */}
      <button
        className={[
          "flex-shrink-0 transition-all cursor-pointer",
          starred
            ? "opacity-100 text-star"
            : "opacity-0 group-hover:opacity-100 text-fg-4 hover:text-star",
        ].join(" ")}
        onClick={(e) => { e.stopPropagation(); onToggleStar(); }}
        aria-label={starred ? "Remove from starred" : "Add to starred"}
      >
        <svg width="13" height="13" viewBox="0 0 24 24" fill={starred ? "currentColor" : "none"} stroke="currentColor" strokeWidth="1.75" strokeLinejoin="round">
          <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
        </svg>
      </button>
    </div>
  );
}

function VariantRowItem({
  font,
  wordmark,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  onSelect,
  isSelected,
}: {
  font: FontInfo;
  wordmark: string;
  logoSvg: string | null;
  logoScale: number;
  controls: Controls;
  starred: boolean;
  onToggleStar: () => void;
  onExclude: () => void;
  onHover: (filePath: string | null) => void;
  onSelect?: (font: FontInfo, rect: DOMRect) => void;
  isSelected?: boolean;
}) {
  const { fontSize, letterSpacing, bgColor, fgColor } = controls;

  if (isSelected) {
    return <div className="h-full border-b border-border-default/40" style={{ backgroundColor: bgColor, opacity: 0 }} />;
  }

  const label = [
    weightLabel(font.weight),
    font.classification.style === "italic" ? "Italic" : "",
    font.classification.width !== "normal"
      ? font.classification.width.charAt(0).toUpperCase() + font.classification.width.slice(1)
      : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <div
      className="group flex items-center gap-3 pl-10 pr-4 h-full border-b border-border-default/40 cursor-pointer
                 hover:bg-white/[0.02] transition-colors"
      style={{ backgroundColor: bgColor }}
      onMouseEnter={() => onHover(font.file_path)}
      onMouseLeave={() => onHover(null)}
      onClick={(e) => {
        if ((e.target as HTMLElement).closest("button")) return;
        onSelect?.(font, e.currentTarget.getBoundingClientRect());
      }}
    >
      {/* X button */}
      <button
        className="opacity-0 group-hover:opacity-100 text-fg-3 hover:text-red-400
                   transition-all cursor-pointer flex-shrink-0"
        onClick={(e) => { e.stopPropagation(); onExclude(); }}
        aria-label="Hide variant"
      >
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>

      <p
        className="flex-1 min-w-0 leading-none overflow-hidden"
        style={{
          fontFamily: fontFamily(font.file_path),
          fontSize,
          letterSpacing: `${letterSpacing}em`,
          color: fgColor,
          opacity: 0.85,
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
        }}
      >
        {wordmark}
      </p>

      <span className="text-[length:var(--text-label)] text-fg-3 font-mono flex-shrink-0">
        {label || "Regular"}
      </span>

      <button
        className={[
          "flex-shrink-0 transition-all cursor-pointer",
          starred
            ? "opacity-100 text-star"
            : "opacity-0 group-hover:opacity-100 text-fg-4 hover:text-star",
        ].join(" ")}
        onClick={(e) => { e.stopPropagation(); onToggleStar(); }}
        aria-label={starred ? "Remove from starred" : "Add to starred"}
      >
        <svg width="11" height="11" viewBox="0 0 24 24" fill={starred ? "currentColor" : "none"} stroke="currentColor" strokeWidth="1.75" strokeLinejoin="round">
          <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
        </svg>
      </button>
    </div>
  );
}

function Row({
  index,
  style,
  rows,
  wordmark,
  logoSvg,
  logoScale,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  onSelect,
  selectedFontPath,
  expandedFamilies,
  onToggleFamily,
}: RowComponentProps<ListData>): React.ReactElement | null {
  const row = rows[index];
  if (!row) return null;

  if (row.type === "family") {
    return (
      <div style={style}>
        <FamilyRowItem
          family={row.family}
          wordmark={wordmark}
          logoSvg={logoSvg}
          logoScale={logoScale}
          controls={controls}
          starred={starred.has(row.family.representative.file_path)}
          onToggleStar={() => onToggleStar(row.family.representative.file_path)}
          onExclude={() => onExclude(row.family.representative.file_path)}
          onHover={onHover}
          onSelect={onSelect}
          isSelected={selectedFontPath === row.family.representative.file_path}
          isExpanded={expandedFamilies.has(row.family.name)}
          onToggle={() => onToggleFamily(row.family.name)}
        />
      </div>
    );
  }

  return (
    <div style={style}>
      <VariantRowItem
        font={row.font}
        wordmark={wordmark}
        logoSvg={logoSvg}
        logoScale={logoScale}
        controls={controls}
        starred={starred.has(row.font.file_path)}
        onToggleStar={() => onToggleStar(row.font.file_path)}
        onExclude={() => onExclude(row.font.file_path)}
        onHover={onHover}
        onSelect={onSelect}
        isSelected={selectedFontPath === row.font.file_path}
      />
    </div>
  );
}

interface Props {
  families: FontFamily[];
  wordmark: string;
  logoSvg: string | null;
  logoScale: number;
  controls: Controls;
  starred: Set<string>;
  onToggleStar: (id: string) => void;
  onExclude: (filePath: string) => void;
  onHover: (filePath: string | null) => void;
  onSelect?: (font: FontInfo, rect: DOMRect) => void;
  selectedFontPath?: string | null;
  expandedFamilies: Set<string>;
  onToggleFamily: (name: string) => void;
}

export function FontFamilyList({
  families,
  wordmark,
  logoSvg,
  logoScale,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  onSelect,
  selectedFontPath,
  expandedFamilies,
  onToggleFamily,
}: Props) {
  const rows: FamilyRow[] = [];
  for (const family of families) {
    rows.push({ type: "family", family });
    if (expandedFamilies.has(family.name)) {
      for (const font of family.fonts) {
        rows.push({ type: "variant", font, familyName: family.name });
      }
    }
  }

  return (
    <div className="flex-1 min-h-0">
      <List
        rowCount={rows.length}
        rowHeight={rowHeight}
        rowComponent={Row}
        rowProps={{
          rows,
          wordmark,
          logoSvg,
          logoScale,
          controls,
          starred,
          onToggleStar,
          onExclude,
          onHover,
          onSelect,
          selectedFontPath,
          expandedFamilies,
          onToggleFamily,
        }}
        overscanCount={3}
      />
    </div>
  );
}
