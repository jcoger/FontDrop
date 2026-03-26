import type { FontInfo } from "../hooks/useFonts";

export interface FontFamily {
  name: string;
  /** All variants, sorted by weight descending */
  fonts: FontInfo[];
  /** The variant whose weight is closest to previewWeight */
  representative: FontInfo;
}

/** Weight label options shown in the toolbar, mapped to numeric weights */
export const PREVIEW_WEIGHT_OPTIONS = [
  { label: "Thin", value: 100 },
  { label: "Light", value: 300 },
  { label: "Regular", value: 400 },
  { label: "Medium", value: 500 },
  { label: "Bold", value: 700 },
  { label: "Heavy", value: 900 },
] as const;

export type PreviewWeightValue = (typeof PREVIEW_WEIGHT_OPTIONS)[number]["value"];

/**
 * Groups a flat list of FontInfo into families, sorted by weight descending.
 * Picks the representative variant closest to `previewWeight`.
 */
export function groupIntoFamilies(
  fonts: FontInfo[],
  previewWeight: number
): FontFamily[] {
  // Group by font_family
  const map = new Map<string, FontInfo[]>();
  for (const font of fonts) {
    const arr = map.get(font.font_family) ?? [];
    arr.push(font);
    map.set(font.font_family, arr);
  }

  const families: FontFamily[] = [];
  map.forEach((variants, name) => {
    // Sort by weight descending
    const sorted = [...variants].sort((a, b) => b.weight - a.weight);

    // Pick representative: closest weight to previewWeight
    let best = sorted[0];
    let bestDiff = Math.abs(best.weight - previewWeight);
    for (const v of sorted) {
      const diff = Math.abs(v.weight - previewWeight);
      if (diff < bestDiff) {
        bestDiff = diff;
        best = v;
      }
    }

    families.push({ name, fonts: sorted, representative: best });
  });

  // Sort families alphabetically
  families.sort((a, b) => a.name.localeCompare(b.name));

  return families;
}

/** Returns a human-readable weight label for a numeric weight value */
export function weightLabel(weight: number): string {
  if (weight <= 150) return "Thin";
  if (weight <= 250) return "Extra Light";
  if (weight <= 350) return "Light";
  if (weight <= 450) return "Regular";
  if (weight <= 550) return "Medium";
  if (weight <= 650) return "Semi Bold";
  if (weight <= 750) return "Bold";
  if (weight <= 850) return "Extra Bold";
  return "Black";
}
