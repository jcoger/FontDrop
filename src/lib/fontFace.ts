import { convertFileSrc } from "@tauri-apps/api/core";
import type { FontInfo } from "../hooks/useFonts";

let styleEl: HTMLStyleElement | null = null;

// Maps file_path → injection index, rebuilt each time injectAllFontFaces is called.
// Using file_path as the stable key means fontFamily() returns the correct face
// even when fonts are filtered into a subset of the original array.
const faceMap = new Map<string, number>();

function getSheet(): CSSStyleSheet {
  if (!styleEl) {
    styleEl = document.createElement("style");
    styleEl.id = "fontdrop-faces";
    document.head.appendChild(styleEl);
  }
  return styleEl.sheet!;
}

/**
 * Inject all @font-face rules at once after fonts are loaded.
 * Call this on the FULL unfiltered fonts array so every font remains accessible
 * even when filters are active (needed for exclusion manager previews too).
 */
export function injectAllFontFaces(fonts: FontInfo[]): void {
  faceMap.clear();
  const sheet = getSheet();
  while (sheet.cssRules.length > 0) sheet.deleteRule(0);

  for (let i = 0; i < fonts.length; i++) {
    faceMap.set(fonts[i].file_path, i);
    const src = convertFileSrc(fonts[i].file_path);
    sheet.insertRule(
      `@font-face { font-family: 'fd-${i}'; src: url('${src}'); font-display: block; }`,
      sheet.cssRules.length
    );
  }
}

/** Returns the CSS font-family string for a font identified by its file_path. */
export function fontFamily(filePath: string): string {
  const i = faceMap.get(filePath);
  if (i === undefined) return "system-ui, sans-serif";
  return `'fd-${i}', system-ui, sans-serif`;
}
