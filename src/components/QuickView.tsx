import { useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { fontFamily } from "../lib/fontFace";
import { easeOut, dur, springModal, useReducedMotion } from "../lib/motion";
import type { FontInfo } from "../hooks/useFonts";
import type { Controls } from "../types/controls";

// Heights of top bars and controls bar
const TOP_OFFSET = 56 + 40; // Row 1 + Row 2
const BOTTOM_OFFSET = 48;   // controls bar

interface Props {
  font: FontInfo | null;
  sourceRect: DOMRect | null;
  allFonts: FontInfo[];
  wordmark: string;
  logoSvg: string | null;
  logoScale: number;
  controls: Controls;
  starred: Set<string>;
  onToggleStar: (fp: string) => void;
  onExclude: (fp: string) => void;
  onClose: () => void;
  onNavigate: (font: FontInfo) => void;
  topOffset?: number;
}

export function QuickView({
  font,
  sourceRect,
  allFonts,
  wordmark,
  logoSvg,
  logoScale,
  controls,
  starred,
  onToggleStar,
  onExclude,
  onClose,
  onNavigate,
  topOffset = TOP_OFFSET,
}: Props) {
  const reduced = useReducedMotion();
  const currentIndex = font ? allFonts.findIndex((f) => f.file_path === font.file_path) : -1;
  const isStarred = font ? starred.has(font.file_path) : false;

  const goNext = useCallback(() => {
    if (currentIndex >= 0 && currentIndex < allFonts.length - 1) {
      onNavigate(allFonts[currentIndex + 1]);
    }
  }, [currentIndex, allFonts, onNavigate]);

  const goPrev = useCallback(() => {
    if (currentIndex > 0) {
      onNavigate(allFonts[currentIndex - 1]);
    }
  }, [currentIndex, allFonts, onNavigate]);

  useEffect(() => {
    if (!font) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") { onClose(); return; }
      if (e.key === "ArrowDown" || e.key === "ArrowRight") { e.preventDefault(); goNext(); }
      if (e.key === "ArrowUp" || e.key === "ArrowLeft") { e.preventDefault(); goPrev(); }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [font, onClose, goNext, goPrev]);

  // Target dimensions
  const vpW = window.innerWidth;
  const vpH = window.innerHeight;
  const targetLeft = 16;
  const targetTop = topOffset + 8;
  const targetWidth = vpW - 32;
  const targetHeight = vpH - topOffset - BOTTOM_OFFSET - 16;

  return (
    <AnimatePresence>
      {font && (
        <>
          {/* Backdrop — stops at controls bar */}
          <motion.div
            className="fixed bg-black/70 backdrop-blur-sm"
            style={{ zIndex: 48, top: topOffset, left: 0, right: 0, bottom: BOTTOM_OFFSET }}
            initial={reduced ? false : { opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: dur.normal, ease: easeOut }}
            onClick={onClose}
          />

          {/* Expanded card */}
          <motion.div
            className="fixed overflow-hidden rounded-xl flex flex-col"
            style={{
              zIndex: 49,
              backgroundColor: controls.bgColor,
            }}
            initial={
              reduced ? false
              : sourceRect
                ? {
                    left: sourceRect.left,
                    top: sourceRect.top,
                    width: sourceRect.width,
                    height: sourceRect.height,
                    borderRadius: "0.5rem",
                    opacity: 0.8,
                    filter: "blur(6px)",
                  }
                : {
                    left: targetLeft,
                    top: targetTop,
                    width: targetWidth,
                    height: targetHeight,
                    opacity: 0,
                    scale: 0.97,
                    filter: "blur(8px)",
                  }
            }
            animate={{
              left: targetLeft,
              top: targetTop,
              width: targetWidth,
              height: targetHeight,
              borderRadius: "0.75rem",
              opacity: 1,
              scale: 1,
              filter: "blur(0px)",
            }}
            exit={
              reduced ? { opacity: 0 }
              : sourceRect
                ? {
                    left: sourceRect.left,
                    top: sourceRect.top,
                    width: sourceRect.width,
                    height: sourceRect.height,
                    borderRadius: "0.5rem",
                    opacity: 0,
                    filter: "blur(6px)",
                  }
                : {
                    opacity: 0,
                    scale: 0.97,
                    filter: "blur(8px)",
                  }
            }
            transition={{
              ...springModal,
              opacity: { duration: dur.normal, ease: easeOut },
              filter: { duration: dur.exit, ease: easeOut },
              scale: { duration: dur.exit, ease: easeOut },
            }}
          >
            {/* Content */}
            <div className="flex-1 flex flex-col items-center justify-center px-12 py-10 min-h-0">
              {/* Logo + wordmark preview */}
              <div className="flex items-center gap-6 max-w-full overflow-hidden">
                {logoSvg && (
                  <div
                    className="flex-shrink-0"
                    style={{
                      height: Math.min(controls.fontSize * logoScale, 80),
                      color: controls.fgColor,
                    }}
                    dangerouslySetInnerHTML={{ __html: logoSvg }}
                  />
                )}
                <p
                  className="leading-none overflow-hidden"
                  style={{
                    fontFamily: fontFamily(font.file_path),
                    fontSize: Math.min(controls.fontSize * 2.5, 120),
                    fontWeight: controls.fontWeight,
                    letterSpacing: `${controls.letterSpacing}em`,
                    color: controls.fgColor,
                    maxWidth: "100%",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {wordmark}
                </p>
              </div>

              {/* Font info */}
              <div className="mt-6 flex flex-col items-center gap-1">
                <p
                  className="text-sm font-mono"
                  style={{ color: controls.fgColor, opacity: 0.6 }}
                >
                  {font.font_family}
                </p>
                <p
                  className="text-xs font-mono"
                  style={{ color: controls.fgColor, opacity: 0.35 }}
                >
                  {font.classification.category} · {font.source}
                  {font.classification.style === "italic" ? " · Italic" : ""}
                </p>
              </div>
            </div>

            {/* Action buttons row */}
            <div
              className="flex-shrink-0 flex items-center justify-between px-6 py-3 border-t"
              style={{ borderColor: `${controls.fgColor}22` }}
            >
              {/* Left: exclude */}
              <button
                className="flex items-center gap-1.5 text-xs font-mono opacity-40 hover:opacity-80 transition-opacity cursor-pointer"
                style={{ color: controls.fgColor }}
                onClick={() => { onExclude(font.file_path); onClose(); }}
              >
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                  <line x1="18" y1="6" x2="6" y2="18" />
                  <line x1="6" y1="6" x2="18" y2="18" />
                </svg>
                Hide
              </button>

              {/* Center: prev/next navigation */}
              <div className="flex items-center gap-4">
                <button
                  className="flex items-center gap-1 text-xs font-mono opacity-40 hover:opacity-80 transition-opacity cursor-pointer disabled:opacity-20"
                  style={{ color: controls.fgColor }}
                  onClick={goPrev}
                  disabled={currentIndex <= 0}
                >
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                    <polyline points="15 18 9 12 15 6" />
                  </svg>
                  Prev
                </button>
                <span
                  className="text-[10px] font-mono tabular-nums opacity-30"
                  style={{ color: controls.fgColor }}
                >
                  {currentIndex + 1} / {allFonts.length}
                </span>
                <button
                  className="flex items-center gap-1 text-xs font-mono opacity-40 hover:opacity-80 transition-opacity cursor-pointer disabled:opacity-20"
                  style={{ color: controls.fgColor }}
                  onClick={goNext}
                  disabled={currentIndex >= allFonts.length - 1}
                >
                  Next
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                    <polyline points="9 18 15 12 9 6" />
                  </svg>
                </button>
              </div>

              {/* Right: hint + star */}
              <div className="flex items-center gap-3">
                <span
                  className="text-[10px] font-mono select-none opacity-20"
                  style={{ color: controls.fgColor }}
                >
                  ↑↓ · Esc
                </span>
                <button
                  className={[
                    "flex items-center gap-1.5 text-xs font-mono transition-all cursor-pointer",
                    isStarred ? "opacity-100" : "opacity-40 hover:opacity-80",
                  ].join(" ")}
                  style={{ color: isStarred ? "var(--c-star)" : controls.fgColor }}
                  onClick={() => onToggleStar(font.file_path)}
                >
                  <svg width="12" height="12" viewBox="0 0 24 24" fill={isStarred ? "currentColor" : "none"} stroke="currentColor" strokeWidth="1.75" strokeLinejoin="round">
                    <polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26" />
                  </svg>
                  {isStarred ? "Starred" : "Star"}
                </button>
              </div>
            </div>

          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
