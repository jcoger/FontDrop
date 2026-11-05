// Shared font-shape types. The runtime font source is useFontDB (SQLite);
// FontDBRow extends FontInfo.

export interface Classification {
  category: "sans-serif" | "serif" | "script" | "decorative" | "monospace";
  style: "normal" | "italic";
  width: "condensed" | "normal" | "extended";
}

export interface FontInfo {
  file_name: string;
  file_path: string;
  font_family: string;
  weight: number;
  source: "system" | "library" | "user";
  classification: Classification;
}
