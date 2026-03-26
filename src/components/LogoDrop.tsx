import { useRef, useState } from "react";
import { parseSvg } from "../lib/svgUtils";

interface Props {
  svg: string | null;
  onLoad: (svg: string) => void;
  onClear: () => void;
  onScaleChange?: (scale: number) => void;
  logoScale?: number;
}

export function LogoDrop({ svg, onLoad, onClear, onScaleChange, logoScale = 1.0 }: Props) {
  const [dragging, setDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  async function handleFile(file: File) {
    if (!file.name.endsWith(".svg") && file.type !== "image/svg+xml") return;
    const text = await file.text();
    const parsed = parseSvg(text);
    if (parsed) onLoad(parsed);
  }

  function onDragOver(e: React.DragEvent) {
    e.preventDefault();
    setDragging(true);
  }

  function onDragLeave(e: React.DragEvent) {
    e.preventDefault();
    setDragging(false);
  }

  async function onDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragging(false);
    const file = e.dataTransfer.files[0];
    if (file) await handleFile(file);
  }

  async function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (file) await handleFile(file);
    e.target.value = "";
  }

  function stepScale(delta: number) {
    if (!onScaleChange) return;
    const next = Math.max(0.2, Math.min(3.0, Math.round((logoScale + delta) * 10) / 10));
    onScaleChange(Math.round(next * 100) / 100);
  }

  // ── Loaded state ──────────────────────────────────────────────
  if (svg) {
    return (
      <div className="flex items-center gap-0.5 flex-shrink-0">
        {/* SVG thumbnail — always white in toolbar (dark bg) */}
        <div
          className="h-8 flex-shrink-0 flex items-center justify-center overflow-hidden"
          style={{ width: 36, color: "white" }}
          dangerouslySetInnerHTML={{ __html: svg }}
        />

        {/* Scale: − / % / + */}
        <button
          className="text-neutral-500 hover:text-white w-5 h-5 flex items-center justify-center text-sm font-mono leading-none cursor-pointer"
          style={{ transition: "color 150ms ease-out" }}
          onClick={() => stepScale(-0.1)}
        >
          −
        </button>
        <button
          className="text-neutral-500 hover:text-white text-[10px] font-mono tabular-nums cursor-pointer min-w-[30px] text-center leading-none"
          style={{ transition: "color 150ms ease-out" }}
          onClick={() => onScaleChange?.(1.0)}
          title="Reset to 100%"
        >
          {Math.round(logoScale * 100)}%
        </button>
        <button
          className="text-neutral-500 hover:text-white w-5 h-5 flex items-center justify-center text-sm font-mono leading-none cursor-pointer"
          style={{ transition: "color 150ms ease-out" }}
          onClick={() => stepScale(0.1)}
        >
          +
        </button>

        {/* Separator */}
        <div className="w-px h-4 bg-neutral-800 mx-1 flex-shrink-0" />

        {/* Swap */}
        <button
          className="text-neutral-500 hover:text-white text-[10px] font-mono cursor-pointer px-1"
          style={{ transition: "color 150ms ease-out" }}
          onClick={() => inputRef.current?.click()}
        >
          swap
        </button>

        {/* Clear */}
        <button
          className="text-neutral-500 hover:text-white text-[11px] font-mono cursor-pointer px-0.5"
          style={{ transition: "color 150ms ease-out" }}
          onClick={onClear}
        >
          ×
        </button>

        <input
          ref={inputRef}
          type="file"
          accept=".svg"
          className="hidden"
          onChange={onFileChange}
        />
      </div>
    );
  }

  // ── Empty / drop state ────────────────────────────────────────
  return (
    <div
      className={[
        "flex items-center justify-center gap-1.5 h-9 w-24 rounded-md",
        "border border-dashed cursor-pointer flex-shrink-0 transition-colors select-none",
        dragging
          ? "border-neutral-400 bg-neutral-800/60"
          : "border-neutral-700 hover:border-neutral-500",
      ].join(" ")}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
      onClick={() => inputRef.current?.click()}
    >
      <input
        ref={inputRef}
        type="file"
        accept=".svg"
        className="hidden"
        onChange={onFileChange}
      />

      <svg
        width="13"
        height="13"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="text-neutral-600 flex-shrink-0"
      >
        <rect x="3" y="3" width="18" height="18" rx="2.5" />
        <circle cx="8.5" cy="8.5" r="1.5" fill="currentColor" stroke="none" />
        <polyline points="3 15 8 10 13 15" />
        <polyline points="13 15 16 12 21 17" />
      </svg>

      <span className="text-[11px] text-neutral-600 font-mono">SVG</span>
    </div>
  );
}
