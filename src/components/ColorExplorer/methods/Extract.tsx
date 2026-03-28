import { useRef, useState, useEffect } from "react";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { oklchToCss } from "../../../utils/oklch";
import type { ExtractedCluster } from "../types";
import { SIDEBAR_SLIDER } from "../components/MethodSidebar";

// Re-export pure functions for use in index.tsx
export {
  extractFromImage,
  applyExtractTransforms,
  buildExtractRamp,
} from "./extractColors";
export type { ExtractedCluster };

// ── Constants ─────────────────────────────────────────────────────────

const IMAGE_TYPES = ["image/png", "image/jpeg", "image/webp"];

// ── Sidebar ───────────────────────────────────────────────────────────

interface EXParamsProps {
  thumbnail: string | null;
  onImageLoad: (img: HTMLImageElement, thumbnail: string) => void;
  onImageClear: () => void;
  remapEnabled: boolean;
  onRemapChange: (v: boolean) => void;
  lightnessLock: boolean;
  onLightnessLockChange: (v: boolean) => void;
  lockedL: number;
  onLockedLChange: (v: number) => void;
  clusters: ExtractedCluster[];
  clusterCount: number;
  onClusterCountChange: (v: number) => void;
  workingColorIndex: number;
  onSetWorkingColor: (idx: number) => void;
}

export function EXParams({
  thumbnail,
  onImageLoad,
  onImageClear,
  remapEnabled,
  onRemapChange,
  lightnessLock,
  onLightnessLockChange,
  lockedL,
  onLockedLChange,
  clusters,
  clusterCount,
  onClusterCountChange,
  workingColorIndex,
  onSetWorkingColor,
}: EXParamsProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);
  const [hoveredBar, setHoveredBar] = useState<number | null>(null);

  // Tauri native drag-drop listener (browser drop events don't fire in Tauri v2)
  useEffect(() => {
    let unlisten: (() => void) | null = null;
    getCurrentWebviewWindow().onDragDropEvent((event) => {
      if (event.payload.type === "over") {
        setDragging(true);
      } else if (event.payload.type === "leave") {
        setDragging(false);
      } else if (event.payload.type === "drop") {
        setDragging(false);
        const paths = event.payload.paths;
        if (paths.length > 0) {
          const filePath = paths[0];
          const ext = filePath.toLowerCase().split(".").pop() || "";
          if (["png", "jpg", "jpeg", "webp"].includes(ext)) {
            // Load via Tauri asset protocol
            const img = new Image();
            img.crossOrigin = "anonymous";
            img.onload = () => onImageLoad(img, img.src);
            // Tauri v2: use convertFileSrc or direct file:// protocol
            import("@tauri-apps/api/core").then(({ convertFileSrc }) => {
              img.src = convertFileSrc(filePath);
            });
          }
        }
      }
    }).then((fn) => { unlisten = fn; });
    return () => { unlisten?.(); };
  }, [onImageLoad]);

  function handleFile(file: File) {
    const ext = file.name.toLowerCase().split(".").pop() || "";
    const validExt = ["png", "jpg", "jpeg", "webp"].includes(ext);
    if (!IMAGE_TYPES.includes(file.type) && !validExt) return;
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      onImageLoad(img, url);
      // Revoke the object URL once the image element has loaded to prevent memory leaks
      URL.revokeObjectURL(url);
    };
    img.src = url;
  }

  const totalSize = clusters.reduce((s, c) => s + c.size, 0);
  const maxSize = clusters.length > 0 ? Math.max(...clusters.map((c) => c.size)) : 1;

  return (
    <>
      {/* Image drop zone / thumbnail */}
      <div>
        <div className="font-mono uppercase mb-2" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
          Source Image
        </div>
        {thumbnail ? (
          <div className={["relative group rounded-lg transition-colors", dragging ? "ring-2 ring-neutral-400" : ""].join(" ")}
            onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
            onDragLeave={(e) => { e.preventDefault(); setDragging(false); }}
            onDrop={(e) => { e.preventDefault(); setDragging(false); const f = e.dataTransfer.files[0]; if (f) handleFile(f); }}
          >
            <img src={thumbnail} className="w-full rounded-lg border border-neutral-700" alt="Source" />
            <div className="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity rounded-lg flex items-center justify-center gap-3">
              <button className="font-mono cursor-pointer transition-colors" style={{ fontSize: "var(--text-label)", color: "var(--c-text-2)" }}
                onClick={() => inputRef.current?.click()}>swap</button>
              <button className="font-mono cursor-pointer transition-colors" style={{ fontSize: "var(--text-label)", color: "var(--c-text-2)" }}
                onClick={onImageClear}>clear</button>
            </div>
          </div>
        ) : (
          <div
            className={["flex flex-col items-center justify-center gap-2 py-8 rounded-lg border border-dashed cursor-pointer transition-colors select-none",
              dragging ? "border-neutral-400 bg-neutral-800/60" : "border-neutral-700 hover:border-neutral-500"].join(" ")}
            onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
            onDragLeave={(e) => { e.preventDefault(); setDragging(false); }}
            onDrop={(e) => { e.preventDefault(); setDragging(false); const f = e.dataTransfer.files[0]; if (f) handleFile(f); }}
            onClick={() => inputRef.current?.click()}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="text-neutral-600">
              <rect x="3" y="3" width="18" height="18" rx="2.5" />
              <circle cx="8.5" cy="8.5" r="1.5" fill="currentColor" stroke="none" />
              <polyline points="3 15 8 10 13 15" /><polyline points="13 15 16 12 21 17" />
            </svg>
            <span className="font-mono" style={{ fontSize: "var(--text-label)", color: "var(--c-text-4)" }}>Drop PNG, JPG, WebP</span>
          </div>
        )}
        <input ref={inputRef} type="file" accept=".png,.jpg,.jpeg,.webp,image/png,image/jpeg,image/webp" className="hidden"
          onChange={(e) => { const f = e.target.files?.[0]; if (f) handleFile(f); e.target.value = ""; }} />
      </div>

      {/* Frequency bar chart */}
      {clusters.length > 0 && (
        <div>
          <div className="flex justify-between items-center mb-2">
            <span className="font-mono uppercase" style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-2)" }}>
              Extracted Palette
            </span>
            <div className="flex items-center gap-1">
              <button className="w-5 h-5 rounded flex items-center justify-center font-mono cursor-pointer border border-neutral-700 hover:border-neutral-500 transition-colors"
                style={{ fontSize: "var(--text-ui)", color: "var(--c-text-2)" }}
                onClick={() => onClusterCountChange(Math.max(3, clusterCount - 1))} aria-label="Fewer clusters">-</button>
              <span className="font-mono w-5 text-center tabular-nums" style={{ fontSize: "var(--text-badge)", color: "var(--c-text)" }}>{clusterCount}</span>
              <button className="w-5 h-5 rounded flex items-center justify-center font-mono cursor-pointer border border-neutral-700 hover:border-neutral-500 transition-colors"
                style={{ fontSize: "var(--text-ui)", color: "var(--c-text-2)" }}
                onClick={() => onClusterCountChange(Math.min(8, clusterCount + 1))} aria-label="More clusters">+</button>
            </div>
          </div>

          <div className="flex items-end gap-1 relative" style={{ height: 80 }}>
            {clusters.map((cluster, i) => {
              const pct = maxSize > 0 ? cluster.size / maxSize : 0;
              const barH = lightnessLock ? 80 : Math.max(8, pct * 80);
              const css = oklchToCss(cluster.color);
              const isWorking = i === (workingColorIndex % clusters.length);
              const isHovered = hoveredBar === i;

              return (
                <div key={i} className="flex-1 flex flex-col items-center gap-0.5 relative cursor-pointer"
                  style={{ height: 80, justifyContent: "flex-end" }}
                  onClick={() => onSetWorkingColor(i)}
                  onMouseEnter={() => setHoveredBar(i)}
                  onMouseLeave={() => setHoveredBar(null)}
                >
                  {isHovered && (
                    <div className="absolute -top-7 left-1/2 -translate-x-1/2 font-mono bg-black/80 px-1.5 py-0.5 rounded shadow-lg whitespace-nowrap z-10"
                      style={{ fontSize: "var(--text-micro)", color: "var(--c-text)" }}>
                      L:{Math.round(cluster.color.l * 100)} C:{cluster.color.c.toFixed(2)} H:{Math.round(cluster.color.h)}
                    </div>
                  )}
                  <div className="w-full rounded-t-sm relative"
                    style={{
                      height: barH,
                      backgroundColor: css,
                      transition: "height 300ms cubic-bezier(0.25,0.46,0.45,0.94)",
                      borderTop: isWorking ? "2px solid white" : "none",
                      boxShadow: isWorking ? "0 -2px 6px rgba(255,255,255,0.2)" : "none",
                    }}
                  />
                </div>
              );
            })}
          </div>

          <div className="flex gap-1 mt-1">
            {clusters.map((cluster, i) => (
              <div key={i} className="flex-1 text-center font-mono uppercase truncate"
                style={{ fontSize: 6, letterSpacing: "var(--track-caps)", color: "var(--c-text-4)" }}>
                {cluster.label}
              </div>
            ))}
          </div>
          <div className="flex gap-1 mt-0.5">
            {clusters.map((cluster, i) => (
              <div key={i} className="flex-1 text-center font-mono tabular-nums"
                style={{ fontSize: 7, color: "var(--c-text-4)" }}>
                {totalSize > 0 ? Math.round((cluster.size / totalSize) * 100) : 0}%
              </div>
            ))}
          </div>
        </div>
      )}

      {/* OKLCH Remap toggle */}
      <div>
        <label className="flex items-center gap-2.5 cursor-pointer">
          <button className="w-8 h-[18px] rounded-full relative transition-colors shrink-0"
            style={{ backgroundColor: remapEnabled ? "var(--c-accent)" : "#404040" }}
            onClick={() => onRemapChange(!remapEnabled)}>
            <div className="absolute top-[3px] w-3 h-3 rounded-full bg-white shadow transition-transform"
              style={{ transform: remapEnabled ? "translateX(17px)" : "translateX(3px)" }} />
          </button>
          <span style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)" }}>OKLCH Remap</span>
        </label>
        <div className="font-mono mt-0.5 pl-[42px]" style={{ fontSize: "var(--text-micro)", color: "var(--c-text-4)" }}>Even hue spacing</div>
      </div>

      {/* Lightness Lock toggle */}
      <div>
        <label className="flex items-center gap-2.5 cursor-pointer">
          <button className="w-8 h-[18px] rounded-full relative transition-colors shrink-0"
            style={{ backgroundColor: lightnessLock ? "var(--c-accent)" : "#404040" }}
            onClick={() => onLightnessLockChange(!lightnessLock)}>
            <div className="absolute top-[3px] w-3 h-3 rounded-full bg-white shadow transition-transform"
              style={{ transform: lightnessLock ? "translateX(17px)" : "translateX(3px)" }} />
          </button>
          <span style={{ fontSize: "var(--text-body)", color: "var(--c-text-2)" }}>Lightness Lock</span>
        </label>
      </div>

      {/* Locked L slider */}
      {lightnessLock && (
        <div>
          <div className="flex justify-between items-end mb-1">
            <span className="font-mono uppercase" style={{ fontSize: "var(--text-badge)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}>Locked L</span>
            <span className="font-mono bg-black/30 px-1.5 py-0.5 rounded" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>{Math.round(lockedL * 100)}%</span>
          </div>
          <input type="range" min={0} max={1} step={0.01} value={lockedL}
            onChange={(e) => onLockedLChange(+e.target.value)} className={SIDEBAR_SLIDER}
            aria-label="Locked lightness" aria-valuetext={`${Math.round(lockedL * 100)} percent`} />
        </div>
      )}
    </>
  );
}

// ── Bottom bar ────────────────────────────────────────────────────────

interface EXBottomControlsProps {
  clusterCount: number;
}

export function EXBottomControls({ clusterCount }: EXBottomControlsProps) {
  return (
    <div className="flex items-center gap-4 bg-black/40 px-5 py-2 rounded-full border border-neutral-800/80 shadow-inner">
      <span className="font-mono" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
        {clusterCount} clusters
      </span>
    </div>
  );
}
