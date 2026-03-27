import { converter } from "culori";
import { hueDifference, circularMean, oklchToCss } from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import type { RampColor, ExtractedCluster } from "../types";

export type { ExtractedCluster };

const toOklch = converter("oklch");

// ── K-means helpers ───────────────────────────────────────────────────

function oklchDist(a: OklchColor, b: OklchColor): number {
  const dL = a.l - b.l;
  const dC = (a.c - b.c) / 0.4;
  const dH = hueDifference(a.h, b.h) / 360;
  return Math.sqrt(dL * dL + dC * dC + dH * dH);
}

function kmeansInit(pixels: OklchColor[], k: number): OklchColor[] {
  const centroids: OklchColor[] = [];
  centroids.push(pixels[Math.floor(Math.random() * pixels.length)]);
  for (let c = 1; c < k; c++) {
    const dists = pixels.map((p) => {
      let minD = Infinity;
      for (const cent of centroids) { const d = oklchDist(p, cent); if (d < minD) minD = d; }
      return minD * minD;
    });
    const total = dists.reduce((a, b) => a + b, 0);
    let r = Math.random() * total;
    let picked = false;
    for (let i = 0; i < dists.length; i++) {
      r -= dists[i];
      if (r <= 0) { centroids.push({ ...pixels[i] }); picked = true; break; }
    }
    if (!picked) centroids.push({ ...pixels[Math.floor(Math.random() * pixels.length)] });
  }
  return centroids;
}

function kmeansRun(pixels: OklchColor[], k: number, iterations: number): ExtractedCluster[] {
  if (pixels.length === 0) return [];
  const actualK = Math.min(k, pixels.length);
  let centroids = kmeansInit(pixels, actualK);
  const assignments = new Array<number>(pixels.length).fill(0);
  for (let iter = 0; iter < iterations; iter++) {
    for (let i = 0; i < pixels.length; i++) {
      let bestC = 0, bestD = Infinity;
      for (let c = 0; c < actualK; c++) { const d = oklchDist(pixels[i], centroids[c]); if (d < bestD) { bestD = d; bestC = c; } }
      assignments[i] = bestC;
    }
    const next: OklchColor[] = [];
    for (let c = 0; c < actualK; c++) {
      const members: OklchColor[] = [];
      for (let i = 0; i < pixels.length; i++) { if (assignments[i] === c) members.push(pixels[i]); }
      if (members.length === 0) { next.push(centroids[c]); continue; }
      next.push({
        mode: "oklch",
        l: members.reduce((s, p) => s + p.l, 0) / members.length,
        c: members.reduce((s, p) => s + p.c, 0) / members.length,
        h: circularMean(members.map((p) => p.h)),
      });
    }
    centroids = next;
  }
  const sizes = new Array<number>(actualK).fill(0);
  for (const a of assignments) sizes[a]++;
  return centroids.map((color, i) => ({ color, size: sizes[i], label: "" }));
}

function imageToPixels(img: HTMLImageElement): OklchColor[] {
  const canvas = document.createElement("canvas");
  canvas.width = 200;
  canvas.height = 200;
  const ctx = canvas.getContext("2d")!;
  ctx.drawImage(img, 0, 0, 200, 200);
  const { data } = ctx.getImageData(0, 0, 200, 200);
  const pixels: OklchColor[] = [];
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 128) continue;
    const oklch = toOklch({ mode: "rgb", r: data[i] / 255, g: data[i + 1] / 255, b: data[i + 2] / 255 });
    if (oklch) pixels.push({ mode: "oklch", l: oklch.l, c: oklch.c, h: oklch.h ?? 0 });
  }
  return pixels;
}

// ── Auto-labeling ─────────────────────────────────────────────────────
// Heuristic rules for naming extracted clusters.

function autoLabel(clusters: ExtractedCluster[]): ExtractedCluster[] {
  if (clusters.length === 0) return clusters;
  const result = clusters.map((c) => ({ ...c }));
  const used = new Set<string>();

  result[0].label = "DOMINANT";
  used.add("DOMINANT");

  let maxChromaIdx = -1, maxChroma = -1;
  for (let i = 1; i < result.length; i++) {
    if (result[i].color.c > maxChroma) { maxChroma = result[i].color.c; maxChromaIdx = i; }
  }

  for (let i = 1; i < result.length; i++) {
    const { l, c, h } = result[i].color;
    if (i === maxChromaIdx && !used.has("ACCENT"))           { result[i].label = "ACCENT";    used.add("ACCENT"); }
    else if (l > 0.85 && !used.has("HIGHLIGHT"))             { result[i].label = "HIGHLIGHT"; used.add("HIGHLIGHT"); }
    else if (l < 0.25 && !used.has("SHADOW"))                { result[i].label = "SHADOW";    used.add("SHADOW"); }
    else if (c < 0.03 && !used.has("NEUTRAL"))               { result[i].label = "NEUTRAL";   used.add("NEUTRAL"); }
    else if (h >= 20 && h <= 60 && !used.has("EARTH"))       { result[i].label = "EARTH";     used.add("EARTH"); }
    else if (h >= 180 && h <= 260 && !used.has("SKY"))       { result[i].label = "SKY";       used.add("SKY"); }
    else                                                     { result[i].label = "WARM"; }
  }
  return result;
}

// ── Public API ────────────────────────────────────────────────────────

export function extractFromImage(img: HTMLImageElement, k: number): ExtractedCluster[] {
  const pixels = imageToPixels(img);
  if (pixels.length === 0) return [];
  const raw = kmeansRun(pixels, k, 20);
  raw.sort((a, b) => b.size - a.size);
  return autoLabel(raw);
}

export function applyExtractTransforms(
  clusters: ExtractedCluster[],
  remapEnabled: boolean,
  lightnessLock: boolean,
  lockedL: number,
): ExtractedCluster[] {
  if (clusters.length === 0) return clusters;
  if (!remapEnabled && !lightnessLock) return clusters;
  const result = clusters.map((c) => ({ ...c, color: { ...c.color } }));
  if (remapEnabled) {
    const hueOrder = result.map((c, i) => ({ h: c.color.h, idx: i })).sort((a, b) => a.h - b.h);
    const baseHue = hueOrder[0].h;
    const step = 360 / hueOrder.length;
    hueOrder.forEach((entry, rank) => { result[entry.idx].color.h = (baseHue + rank * step) % 360; });
  }
  if (lightnessLock) { for (const c of result) c.color.l = lockedL; }
  return result;
}

export function buildExtractRamp(clusters: ExtractedCluster[]): RampColor[] {
  if (clusters.length === 0) return [];
  const totalSize = clusters.reduce((s, c) => s + c.size, 0);
  if (totalSize === 0) return clusters.map((c) => ({ color: c.color, badge: c.label }));
  const ramp: RampColor[] = [];
  for (const c of clusters) {
    const n = Math.max(1, Math.round((c.size / totalSize) * 12));
    for (let i = 0; i < n; i++) ramp.push({ color: c.color, badge: c.label });
  }
  return ramp;
}

// Re-export oklchToCss for the UI file
export { oklchToCss };
