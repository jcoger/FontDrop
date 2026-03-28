import React, { useCallback } from "react";
import { List, RowComponentProps } from "react-window";
import { fontFamily } from "../lib/fontFace";
import type { FontInfo } from "../hooks/useFonts";
import type { Controls } from "../types/controls";

const FONT_COL_W = 168;
const STAR_COL_W = 40;

export type Cols = [string, string, string, string];
export type ColSizes = [number, number, number, number];

export const DEFAULT_COLUMNS: Cols = ["Moonlight Diner", "Pies & Good Times", "Open All Night", "Since 1963"];
export const DEFAULT_HEADERS: Cols = ["Title", "Descriptor", "Details", "Note"];
export const DEFAULT_COL_SIZES: ColSizes = [48, 32, 20, 16];

// Fixed column width proportions (sum = 100). These do NOT change per font.
const COL_FLEX = [40, 27, 18, 15] as const;

interface RowData {
  fonts: FontInfo[];
  columns: Cols;
  colSizes: ColSizes;
  setColumn: (i: 0 | 1 | 2 | 3, value: string) => void;
  controls: Controls;
  starred: Set<string>;
  onToggleStar: (id: string) => void;
  onExclude: (filePath: string) => void;
  onHover: (filePath: string | null) => void;
  onSelect?: (font: FontInfo, rect: DOMRect) => void;
  selectedFontPath?: string | null;
}

function rowHeight(_index: number, data: RowData): number {
  return Math.max(44, Math.max(...data.colSizes) + 28);
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

function TypeRow({
  index,
  style,
  fonts,
  columns,
  colSizes,
  setColumn,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  onSelect,
}: RowComponentProps<RowData>): React.ReactElement | null {
  const font = fonts[index];
  if (!font) return null;

  const { letterSpacing, fontWeight, bgColor, fgColor } = controls;
  const isStarred = starred.has(font.file_path);

  return (
    <div
      style={{ ...style, backgroundColor: bgColor }}
      className="group flex items-stretch border-b border-border-default/60 cursor-pointer"
      onMouseEnter={() => onHover(font.file_path)}
      onMouseLeave={() => onHover(null)}
      onClick={(e) => {
        // Only trigger quick view when clicking outside the inputs
        if ((e.target as HTMLElement).tagName !== "INPUT") {
          onSelect?.(font, e.currentTarget.getBoundingClientRect());
        }
      }}
    >
      {/* Font name column — X button appears on hover */}
      <div
        className="flex-shrink-0 flex items-center px-3 gap-1.5 border-r border-border-default/60 overflow-hidden"
        style={{ width: FONT_COL_W }}
      >
        <button
          className="opacity-0 group-hover:opacity-100 text-fg-3 hover:text-red-400
                     transition-all cursor-pointer flex-shrink-0"
          onClick={(e) => { e.stopPropagation(); onExclude(font.file_path); }}
          aria-label="Hide font"
        >
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
        <span className="text-[length:var(--text-body)] text-fg-3 font-mono leading-none truncate min-w-0">
          {font.font_family}
        </span>
      </div>

      {/* Four editable text columns — fixed proportional widths */}
      <div className="flex flex-1 min-w-0 divide-x divide-border-default/60 overflow-hidden">
        {([0, 1, 2, 3] as const).map((i) => (
          <div
            key={i}
            className="flex items-center overflow-hidden"
            style={{ flex: `${COL_FLEX[i]} 1 0`, minWidth: 0 }}
          >
            <input
              className="w-full min-w-0 px-4 bg-transparent outline-none
                         leading-none focus:bg-white/[0.025] transition-colors"
              style={{
                fontFamily: fontFamily(font.file_path),
                fontSize: colSizes[i],
                fontWeight,
                letterSpacing: `${letterSpacing}em`,
                color: fgColor,
              }}
              value={columns[i]}
              onChange={(e) => setColumn(i, e.target.value)}
              onClick={(e) => e.stopPropagation()}
              spellCheck={false}
            />
          </div>
        ))}
      </div>

      {/* Star column */}
      <div
        className="flex-shrink-0 flex items-center justify-center border-l border-border-default/60"
        style={{ width: STAR_COL_W }}
      >
        <button
          className={[
            "transition-all cursor-pointer",
            isStarred
              ? "opacity-100 text-star"
              : "opacity-0 group-hover:opacity-100 text-fg-3 hover:text-star",
          ].join(" ")}
          onClick={(e) => { e.stopPropagation(); onToggleStar(font.file_path); }}
          aria-label={isStarred ? "Remove from starred" : "Add to starred"}
        >
          <StarIcon filled={isStarred} />
        </button>
      </div>
    </div>
  );
}

interface Props {
  fonts: FontInfo[];
  controls: Controls;
  starred: Set<string>;
  onToggleStar: (id: string) => void;
  onExclude: (filePath: string) => void;
  onHover: (filePath: string | null) => void;
  onSelect?: (font: FontInfo, rect: DOMRect) => void;
  selectedFontPath?: string | null;
  // Controlled content state — owned by parent for export access
  headers: Cols;
  columns: Cols;
  colSizes: ColSizes;
  onHeadersChange: (h: Cols) => void;
  onColumnsChange: (c: Cols) => void;
  onColSizesChange: (s: ColSizes) => void;
  // DOM ref for PNG capture
  containerRef?: React.Ref<HTMLDivElement>;
}

export function TypeExplorer({
  fonts,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onHover,
  onSelect,
  selectedFontPath,
  headers,
  columns,
  colSizes,
  onHeadersChange,
  onColumnsChange,
  onColSizesChange,
  containerRef,
}: Props) {
  const setColumn = useCallback(
    (i: 0 | 1 | 2 | 3, value: string) => {
      const next = [...columns] as Cols;
      next[i] = value;
      onColumnsChange(next);
    },
    [columns, onColumnsChange]
  );

  const setHeader = useCallback(
    (i: 0 | 1 | 2 | 3, value: string) => {
      const next = [...headers] as Cols;
      next[i] = value;
      onHeadersChange(next);
    },
    [headers, onHeadersChange]
  );

  const adjustColSize = useCallback(
    (i: 0 | 1 | 2 | 3, delta: number) => {
      const next = [...colSizes] as ColSizes;
      next[i] = Math.max(10, Math.min(120, next[i] + delta));
      onColSizesChange(next);
    },
    [colSizes, onColSizesChange]
  );

  const rowProps: RowData = {
    fonts, columns, colSizes, setColumn, controls, starred,
    onToggleStar, onExclude, onHover, onSelect, selectedFontPath,
  };

  return (
    <div ref={containerRef} className="flex-1 min-h-0 flex flex-col overflow-hidden">
      {/* Sticky column header */}
      <div className="flex-shrink-0 flex items-stretch border-b border-border-strong h-9">
        <div
          className="flex-shrink-0 flex items-center px-4 border-r border-border-strong"
          style={{ width: FONT_COL_W }}
        >
          <span className="text-[length:var(--text-label)] text-fg-3 font-mono uppercase tracking-widest">
            font
          </span>
        </div>

        <div className="flex flex-1 min-w-0 divide-x divide-border-strong overflow-hidden">
          {([0, 1, 2, 3] as const).map((i) => (
            <div
              key={i}
              className="flex items-center px-3 gap-1 overflow-hidden"
              style={{ flex: `${COL_FLEX[i]} 1 0`, minWidth: 0 }}
            >
              <input
                className="flex-1 min-w-0 bg-transparent text-fg-4 text-[length:var(--text-label)]
                           font-mono uppercase tracking-widest outline-none
                           hover:text-fg-2 focus:text-fg transition-colors"
                value={headers[i]}
                onChange={(e) => setHeader(i, e.target.value)}
                spellCheck={false}
              />
              {/* Per-column size controls */}
              <div className="flex items-center gap-0.5 flex-shrink-0">
                <button
                  className="text-fg-4 hover:text-fg-2 cursor-pointer
                             w-4 h-4 flex items-center justify-center text-xs leading-none"
                  onClick={() => adjustColSize(i, -2)}
                >
                  −
                </button>
                <span className="text-[length:var(--text-badge)] text-fg-3 font-mono tabular-nums w-5 text-center">
                  {colSizes[i]}
                </span>
                <button
                  className="text-fg-4 hover:text-fg-2 cursor-pointer
                             w-4 h-4 flex items-center justify-center text-xs leading-none"
                  onClick={() => adjustColSize(i, 2)}
                >
                  +
                </button>
              </div>
            </div>
          ))}
        </div>

        {/* Star column header */}
        <div
          className="flex-shrink-0 flex items-center justify-center border-l border-border-strong"
          style={{ width: STAR_COL_W }}
        >
          <span className="text-[length:var(--text-label)] text-fg-4">★</span>
        </div>
      </div>

      {/* Virtualized font rows */}
      <div className="flex-1 min-h-0">
        <List
          rowCount={fonts.length}
          rowHeight={rowHeight}
          rowComponent={TypeRow}
          rowProps={rowProps}
          overscanCount={4}
        />
      </div>
    </div>
  );
}
