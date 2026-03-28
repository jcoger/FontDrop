import type { OklchColor } from "../../utils/oklch";
import { oklchToHex } from "../../utils/oklch";

/** Trigger a file download in the browser. */
export function downloadFile(filename: string, content: string, mimeType = "application/json"): void {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/** Format an OklchColor as "oklch(L, C, H)" string. */
export function oklchStr(c: OklchColor): string {
  return `oklch(${c.l.toFixed(2)}, ${c.c.toFixed(3)}, ${Math.round(c.h)})`;
}

/** Today's date as YYYY-MM-DD. */
export function todayStr(): string {
  return new Date().toISOString().slice(0, 10);
}

// ── System export: CSS ───────────────────────────────────────────────

interface RoleExport {
  key: string;
  name: string;
  bg: OklchColor;
  fg?: OklchColor;
  fontName?: string;
  fontWeight?: string;
}

export function exportSystemCSS(roles: RoleExport[]): string {
  const lines: string[] = [];
  lines.push("/* FontDrop Design System */");
  lines.push(`:root {`);
  for (const r of roles) {
    lines.push(`  --color-${r.key}: ${oklchToHex(r.bg)}; /* ${oklchStr(r.bg)} */`);
    if (r.fg) lines.push(`  --color-${r.key}-fg: ${oklchToHex(r.fg)}; /* ${oklchStr(r.fg)} */`);
    if (r.fontName) lines.push(`  --font-${r.key}: "${r.fontName}";`);
  }
  lines.push("}");
  return lines.join("\n");
}

// ── System export: JSON ──────────────────────────────────────────────

export function exportSystemJSON(roles: RoleExport[]): string {
  const obj: Record<string, unknown> = {};
  for (const r of roles) {
    const entry: Record<string, unknown> = {
      bg: { hex: oklchToHex(r.bg), oklch: oklchStr(r.bg) },
    };
    if (r.fg) entry.fg = { hex: oklchToHex(r.fg), oklch: oklchStr(r.fg) };
    if (r.fontName) entry.font = { name: r.fontName, weight: r.fontWeight || "400" };
    obj[r.key] = entry;
  }
  return JSON.stringify({ roles: obj, generated: new Date().toISOString(), tool: "FontDrop" }, null, 2);
}

// ── Collection export: JSON ──────────────────────────────────────────

export function exportCollectionJSON(items: { bg: OklchColor; fg: OklchColor; fontName: string; fontWeight: string; fontCategory: string; sourceMode: string; savedAt: string }[]): string {
  const arr = items.map((item) => ({
    bg: { hex: oklchToHex(item.bg), oklch: oklchStr(item.bg) },
    fg: { hex: oklchToHex(item.fg), oklch: oklchStr(item.fg) },
    font: { name: item.fontName, weight: item.fontWeight, category: item.fontCategory },
    sourceMode: item.sourceMode,
    savedAt: item.savedAt,
  }));
  return JSON.stringify({ cards: arr, count: arr.length, exported: new Date().toISOString(), tool: "FontDrop" }, null, 2);
}
