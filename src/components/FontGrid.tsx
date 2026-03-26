import React from "react";
import { Grid, CellComponentProps } from "react-window";
import { FontCard } from "./FontCard";
import type { FontInfo } from "../hooks/useFonts";
import type { Controls } from "../types/controls";

const GAP = 16;

function rowHeight(_rowIndex: number, data: CellData): number {
  return Math.max(88, data.controls.fontSize + 80);
}

interface CellData {
  fonts: FontInfo[];
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
  colCount: number;
}

function Cell({
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
  onSelect,
  selectedFontPath,
  colCount,
}: CellComponentProps<CellData>): React.ReactElement | null {
  const index = rowIndex * colCount + columnIndex;
  if (index >= fonts.length) return null;

  const font = fonts[index];
  const isLastCol = columnIndex === colCount - 1;

  return (
    <div
      style={{
        ...style,
        paddingRight: isLastCol ? 0 : GAP,
        paddingBottom: GAP,
      }}
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
        onSelect={onSelect}
        isSelected={selectedFontPath === font.file_path}
      />
    </div>
  );
}

interface Props {
  fonts: FontInfo[];
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
  colCount: number;
}

export function FontGrid({
  fonts,
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
  colCount,
}: Props) {
  const rowCount = Math.ceil(fonts.length / colCount);

  return (
    <div className="flex-1 min-h-0 px-4 pt-4">
      <Grid
        columnCount={colCount}
        rowCount={rowCount}
        columnWidth={`${100 / colCount}%`}
        rowHeight={rowHeight}
        overscanCount={2}
        cellComponent={Cell}
        cellProps={{
          fonts, wordmark, logoSvg, logoScale, controls,
          starred, onToggleStar, onExclude, onHover,
          onSelect, selectedFontPath, colCount,
        }}
        style={{ overflowX: "hidden" }}
      />
    </div>
  );
}
