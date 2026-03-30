import { useState, useMemo, useCallback, useRef, useEffect } from "react";
import { motion } from "framer-motion";
import { HexColorPicker } from "react-colorful";
import { oklchToCss, oklchToSrgbHex, hexToOklch, contrastRatio } from "../../../utils/oklch";
import type { OklchColor } from "../../../utils/oklch";
import { fontFamily } from "../../../lib/fontFace";
import type { FontInfo } from "../../../hooks/useFonts";
import type { BrandKitSlot, BrandKitColors, BrandKitFont } from "../types";
import { deriveBrandKit, deriveBody, deriveSurface, deriveAccent } from "../methods/brandKitLogic";
import {
  exportBrandKitCSS,
  exportBrandKitJSON,
  exportBrandKitPrompt,
  downloadFile,
  todayStr,
} from "../exportUtils";

// ── Constants ────────────────────────────────────────────────────────

const SLOTS: { key: BrandKitSlot; label: string }[] = [
  { key: "bg", label: "Background" },
  { key: "headline", label: "Headline" },
  { key: "body", label: "Body" },
  { key: "surface", label: "Surface" },
  { key: "accent", label: "Accent" },
];

const SUGGESTED_SLOTS = new Set<BrandKitSlot>(["body", "surface", "accent"]);

// ── Props ────────────────────────────────────────────────────────────

interface BrandKitViewProps {
  initialBg: OklchColor;
  initialFg: OklchColor;
  font: BrandKitFont;
  fontFilePath?: string;
  fonts: FontInfo[];
  brandName: string;
  logoSvg?: string | null;
  onClose: () => void;
  onToast: (msg: string) => void;
  exportRef?: React.MutableRefObject<(() => void) | null>;
}

// ── Component ────────────────────────────────────────────────────────

export function BrandKitView({
  initialBg,
  initialFg,
  font,
  fontFilePath,
  fonts,
  brandName,
  onClose,
  onToast,
  exportRef,
}: BrandKitViewProps) {
  // ── State ──────────────────────────────────────────────────────
  const [colors, setColors] = useState<BrandKitColors>(() =>
    deriveBrandKit(initialBg, initialFg),
  );
  const [userEdited, setUserEdited] = useState<Set<BrandKitSlot>>(new Set());
  const [editingSlot, setEditingSlot] = useState<BrandKitSlot | null>(null);
  const pickerRef = useRef<HTMLDivElement>(null);

  // ── Font CSS lookup ────────────────────────────────────────────
  const fontCss = useMemo(() => {
    if (fontFilePath) return fontFamily(fontFilePath);
    // Fallback: find by name + weight in fonts array
    const match = fonts.find(
      (f) => f.font_family === font.name && String(f.weight) === font.weight,
    );
    return match ? fontFamily(match.file_path) : `"${font.name}", system-ui, sans-serif`;
  }, [fontFilePath, font, fonts]);

  // ── Close picker on outside click ──────────────────────────────
  useEffect(() => {
    if (!editingSlot) return;
    function handleClick(e: MouseEvent) {
      if (pickerRef.current && !pickerRef.current.contains(e.target as Node)) {
        setEditingSlot(null);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [editingSlot]);

  // ── Color change handler with re-derivation ────────────────────
  const handleColorChange = useCallback(
    (slot: BrandKitSlot, color: OklchColor) => {
      setUserEdited((prev) => new Set(prev).add(slot));
      setColors((prev) => {
        const next = { ...prev, [slot]: color };

        // Re-derive dependents that haven't been manually edited
        if (slot === "bg") {
          if (!userEdited.has("surface")) next.surface = deriveSurface(color);
          if (!userEdited.has("body")) next.body = deriveBody(prev.headline, color);
          if (!userEdited.has("accent"))
            next.accent = deriveAccent(prev.headline, color, next.surface);
        }
        if (slot === "headline") {
          if (!userEdited.has("body")) next.body = deriveBody(color, prev.bg);
          if (!userEdited.has("accent"))
            next.accent = deriveAccent(color, prev.bg, prev.surface);
        }
        if (slot === "surface" && !userEdited.has("accent")) {
          next.accent = deriveAccent(prev.headline, prev.bg, color);
        }

        return next;
      });
    },
    [userEdited],
  );

  // ── Export handlers ────────────────────────────────────────────
  const handleExportCSS = useCallback(() => {
    downloadFile(
      `fontdrop-brand-kit-${todayStr()}.css`,
      exportBrandKitCSS(colors, font),
      "text/css",
    );
    onToast("CSS downloaded");
  }, [colors, font, onToast]);

  const handleExportJSON = useCallback(() => {
    downloadFile(
      `fontdrop-brand-kit-${todayStr()}.json`,
      exportBrandKitJSON(colors, font, brandName),
    );
    onToast("JSON downloaded");
  }, [colors, font, brandName, onToast]);

  const handleCopyPrompt = useCallback(() => {
    navigator.clipboard.writeText(exportBrandKitPrompt(colors, font, brandName));
    onToast("Prompt copied");
  }, [colors, font, brandName, onToast]);

  // ── Wire export ref (for Cmd+E from App) ───────────────────────
  useEffect(() => {
    if (exportRef) exportRef.current = handleCopyPrompt;
    return () => {
      if (exportRef) exportRef.current = null;
    };
  }, [exportRef, handleCopyPrompt]);

  // ── Contrast helpers ───────────────────────────────────────────
  const heroContrast = contrastRatio(colors.bg, colors.headline).toFixed(1);
  const bodyContrast = contrastRatio(colors.surface, colors.body).toFixed(1);
  const accentOnBgContrast = contrastRatio(colors.bg, colors.accent).toFixed(1);
  const accentOnSurfaceContrast = contrastRatio(colors.surface, colors.accent).toFixed(1);

  // ── Render ─────────────────────────────────────────────────────
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.2 }}
      className="flex flex-col h-full overflow-y-auto"
    >
      {/* ── Top bar ──────────────────────────────────────────────── */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-border-default">
        <button
          onClick={onClose}
          className="text-[var(--c-text-3)] hover:text-[var(--c-text)] text-xs flex items-center gap-1.5 transition-colors"
        >
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M19 12H5M12 19l-7-7 7-7" />
          </svg>
          Back
        </button>
        <span className="text-[var(--c-text-2)] text-xs tracking-wide uppercase">
          Brand Kit{brandName ? ` — ${brandName}` : ""}
        </span>
        <div className="flex items-center gap-2">
          <button onClick={handleExportCSS} className="text-[10px] px-2.5 py-1 rounded border border-border-default text-[var(--c-text-3)] hover:text-[var(--c-text)] hover:border-[var(--border-strong)] transition-colors">
            CSS
          </button>
          <button onClick={handleExportJSON} className="text-[10px] px-2.5 py-1 rounded border border-border-default text-[var(--c-text-3)] hover:text-[var(--c-text)] hover:border-[var(--border-strong)] transition-colors">
            JSON
          </button>
          <button onClick={handleCopyPrompt} className="text-[10px] px-2.5 py-1 rounded border border-border-default text-[var(--c-text-3)] hover:text-[var(--c-text)] hover:border-[var(--border-strong)] transition-colors">
            Prompt
          </button>
        </div>
      </div>

      {/* ── Palette strip ────────────────────────────────────────── */}
      <div className="flex items-start gap-3 px-4 py-4 border-b border-border-default" ref={pickerRef}>
        {SLOTS.map(({ key, label }) => {
          const isEditing = editingSlot === key;
          const isSuggested = SUGGESTED_SLOTS.has(key) && !userEdited.has(key);
          return (
            <div key={key} className="flex flex-col items-center gap-1.5 relative">
              <button
                onClick={() => setEditingSlot(isEditing ? null : key)}
                className="w-12 h-12 rounded-lg border-2 transition-all"
                style={{
                  backgroundColor: oklchToCss(colors[key]),
                  borderColor: isEditing ? "var(--c-accent)" : "var(--border-default)",
                }}
              />
              <span className="text-[10px] text-[var(--c-text-3)]">{label}</span>
              {isSuggested && (
                <span className="text-[8px] text-[var(--c-text-4)] italic">suggested</span>
              )}
              {isEditing && (
                <div className="absolute top-14 left-1/2 -translate-x-1/2 z-50 bg-[var(--surface-1)] rounded-lg p-2 border border-border-default shadow-lg">
                  <div className="compact-picker" style={{ width: 180 }}>
                    <HexColorPicker
                      color={oklchToSrgbHex(colors[key])}
                      onChange={(hex) => handleColorChange(key, hexToOklch(hex))}
                      style={{ width: "100%" }}
                    />
                  </div>
                  <div className="mt-1.5 text-center text-[10px] text-[var(--c-text-3)] font-mono">
                    {oklchToSrgbHex(colors[key])}
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* ── Website preview ──────────────────────────────────────── */}
      <div className="flex-1 px-4 py-6 flex flex-col gap-4 overflow-y-auto">

        {/* Hero block */}
        <div
          className="rounded-xl overflow-hidden"
          style={{ backgroundColor: oklchToCss(colors.bg) }}
        >
          <div className="px-8 py-12 flex flex-col gap-3">
            <p
              className="text-[48px] leading-[1.1] tracking-tight"
              style={{
                color: oklchToCss(colors.headline),
                fontFamily: fontCss,
                fontWeight: font.weight,
              }}
            >
              {brandName || "Your Brand"}
            </p>
            <p
              className="text-[16px] leading-relaxed max-w-[48ch]"
              style={{
                color: oklchToCss(colors.body),
                fontFamily: fontCss,
              }}
            >
              A short paragraph showing how body text looks against the background.
              This uses a softer version of your headline color for comfortable reading.
            </p>
            <div className="flex gap-3 mt-2">
              <button
                className="px-5 py-2.5 rounded-lg text-sm font-medium transition-transform hover:scale-[1.02]"
                style={{
                  backgroundColor: oklchToCss(colors.accent),
                  color: contrastRatio(colors.accent, { mode: "oklch", l: 1, c: 0, h: 0 }) > contrastRatio(colors.accent, { mode: "oklch", l: 0, c: 0, h: 0 })
                    ? "#ffffff" : "#000000",
                  fontFamily: fontCss,
                }}
              >
                Get Started
              </button>
              <button
                className="px-5 py-2.5 rounded-lg text-sm font-medium border transition-transform hover:scale-[1.02]"
                style={{
                  borderColor: oklchToCss(colors.headline),
                  color: oklchToCss(colors.headline),
                  fontFamily: fontCss,
                }}
              >
                Learn More
              </button>
            </div>
          </div>
          {/* Contrast badge */}
          <div className="px-8 pb-3 flex gap-4">
            <span className="text-[9px] font-mono" style={{ color: oklchToCss(colors.headline), opacity: 0.5 }}>
              Headline {heroContrast}:1
            </span>
            <span className="text-[9px] font-mono" style={{ color: oklchToCss(colors.body), opacity: 0.5 }}>
              Body {bodyContrast}:1
            </span>
          </div>
        </div>

        {/* Content block on surface */}
        <div
          className="rounded-xl overflow-hidden"
          style={{ backgroundColor: oklchToCss(colors.surface) }}
        >
          <div className="px-8 py-8 flex flex-col gap-3">
            <p
              className="text-[28px] leading-tight tracking-tight"
              style={{
                color: oklchToCss(colors.headline),
                fontFamily: fontCss,
                fontWeight: font.weight,
              }}
            >
              A section heading
            </p>
            <p
              className="text-[15px] leading-relaxed max-w-[52ch]"
              style={{
                color: oklchToCss(colors.body),
                fontFamily: fontCss,
              }}
            >
              Content sections use the surface color as a background to create visual depth.
              Body text remains readable with consistent contrast across surfaces.
            </p>
            <div className="flex gap-3 mt-2">
              <button
                className="px-5 py-2.5 rounded-lg text-sm font-medium"
                style={{
                  backgroundColor: oklchToCss(colors.accent),
                  color: contrastRatio(colors.accent, { mode: "oklch", l: 1, c: 0, h: 0 }) > contrastRatio(colors.accent, { mode: "oklch", l: 0, c: 0, h: 0 })
                    ? "#ffffff" : "#000000",
                  fontFamily: fontCss,
                }}
              >
                Call to Action
              </button>
            </div>
          </div>
          <div className="px-8 pb-3 flex gap-4">
            <span className="text-[9px] font-mono" style={{ color: oklchToCss(colors.body), opacity: 0.5 }}>
              Body on Surface {bodyContrast}:1
            </span>
            <span className="text-[9px] font-mono" style={{ color: oklchToCss(colors.accent), opacity: 0.5 }}>
              Accent on Surface {accentOnSurfaceContrast}:1
            </span>
          </div>
        </div>

        {/* Accent showcase strip */}
        <div className="flex gap-3">
          <div
            className="flex-1 rounded-xl px-6 py-5 flex flex-col gap-1"
            style={{ backgroundColor: oklchToCss(colors.accent) }}
          >
            <p
              className="text-sm font-medium"
              style={{
                color: contrastRatio(colors.accent, { mode: "oklch", l: 1, c: 0, h: 0 }) > contrastRatio(colors.accent, { mode: "oklch", l: 0, c: 0, h: 0 })
                  ? "#ffffff" : "#000000",
                fontFamily: fontCss,
              }}
            >
              Accent color
            </p>
            <p
              className="text-[10px] font-mono"
              style={{
                color: contrastRatio(colors.accent, { mode: "oklch", l: 1, c: 0, h: 0 }) > contrastRatio(colors.accent, { mode: "oklch", l: 0, c: 0, h: 0 })
                  ? "rgba(255,255,255,0.6)" : "rgba(0,0,0,0.5)",
              }}
            >
              {oklchToSrgbHex(colors.accent)} · {accentOnBgContrast}:1 on bg
            </p>
          </div>
          <div
            className="flex-1 rounded-xl px-6 py-5 flex flex-col gap-1 border"
            style={{
              backgroundColor: oklchToCss(colors.bg),
              borderColor: oklchToCss(colors.headline),
            }}
          >
            <p
              className="text-sm font-medium"
              style={{ color: oklchToCss(colors.headline), fontFamily: fontCss }}
            >
              {font.name}
            </p>
            <p
              className="text-[10px] font-mono"
              style={{ color: oklchToCss(colors.body) }}
            >
              {font.weight} · {font.category}
            </p>
          </div>
        </div>
      </div>
    </motion.div>
  );
}
