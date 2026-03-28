import { useState } from "react";
import { HexColorPicker } from "react-colorful";
import type { OklchColor } from "../../../utils/oklch";
import { oklchToCss, contrastRatio } from "../../../utils/oklch";
import type { ContrastLevel } from "../types";

// ── Types ─────────────────────────────────────────────────────────────

interface WorkingCardInfo {
  badge: string;
  fontName: string;
  bgColor: OklchColor;
  fgColor: string;
}

/** Per-card bg/fg OklchColor pair for computing pass rate */
export interface CardContrastPair {
  bg: OklchColor;
  fg: OklchColor;
}

interface HudBarProps {
  workingCard: WorkingCardInfo | null;
  cardPairs: CardContrastPair[];
  contrastLevel: ContrastLevel;
  onContrastLevelChange: (v: ContrastLevel) => void;
  onBuildSystem?: () => void;
  onBackToExplore?: () => void;
  buildSystemOpen?: boolean;
  activeMethod: string;
  collectionCount?: number;
  onCollectionClick?: () => void;
}

// ── Separator ─────────────────────────────────────────────────────────

function Dot() {
  return <div className="w-1 h-1 rounded-full bg-neutral-700 shrink-0" />;
}

// ── Component ─────────────────────────────────────────────────────────

export function HudBar({
  workingCard,
  cardPairs,
  contrastLevel,
  onContrastLevelChange,
  onBuildSystem,
  onBackToExplore,
  buildSystemOpen,
  activeMethod,
  collectionCount = 0,
  onCollectionClick,
}: HudBarProps) {
  const [editingSwatch, setEditingSwatch] = useState<"bg" | "fg" | null>(null);

  // Compute contrast pass rate from per-card bg/fg pairs
  const threshold = contrastLevel === "accessible" ? 4.5 : contrastLevel === "display" ? 3.0 : 1.5;
  const passRate = (() => {
    if (cardPairs.length === 0) return null;
    if (contrastLevel === "clash") return null; // no pass/fail in clash
    let pass = 0;
    for (const p of cardPairs) {
      if (contrastRatio(p.bg, p.fg) >= threshold) pass++;
    }
    return { pass, total: cardPairs.length };
  })();

  const bgCss = workingCard ? oklchToCss(workingCard.bgColor) : "#1a1a1a";
  const fgCss = workingCard?.fgColor || "#ffffff";
  const isHueLocked = activeMethod === "Hue Lock";
  const hasSpotlight = workingCard !== null;

  return (
    <div className="flex-shrink-0 grid items-center min-h-[44px] py-1.5 border-b border-neutral-800 bg-neutral-900 px-4"
      style={{ gridTemplateColumns: "auto 1fr auto auto" }}>

      {/* ── Left: BG/FG swatches ─────────────────────────── */}
      <div className="flex items-center gap-3">
        <div className="flex items-center gap-2">
          <div className="relative">
            <button className="w-6 h-6 rounded border border-neutral-700 cursor-pointer transition-shadow hover:ring-1 hover:ring-neutral-500"
              style={{ backgroundColor: bgCss }}
              onClick={() => setEditingSwatch(editingSwatch === "bg" ? null : "bg")}
              aria-label="Background color" />
            <span className="font-mono uppercase block text-center mt-0.5" style={{ fontSize: 6, letterSpacing: "var(--track-caps)", color: "var(--c-text-4)" }}>BG</span>
            {editingSwatch === "bg" && (
              <div className="absolute top-8 left-0 z-50 compact-picker shadow-xl rounded-lg overflow-hidden">
                <HexColorPicker color={bgCss} onChange={() => {}} style={{ width: 160 }} />
              </div>
            )}
          </div>
          <div className="relative">
            <button className="w-6 h-6 rounded border border-neutral-700 cursor-pointer transition-shadow hover:ring-1 hover:ring-neutral-500"
              style={{ backgroundColor: fgCss }}
              onClick={() => setEditingSwatch(editingSwatch === "fg" ? null : "fg")}
              aria-label="Foreground color" />
            {isHueLocked && (
              <svg className="absolute -top-1 -right-1 pointer-events-none" width="8" height="8" viewBox="0 0 24 24"
                fill="none" stroke="var(--c-text-3)" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="11" width="18" height="11" rx="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
            )}
            <span className="font-mono uppercase block text-center mt-0.5" style={{ fontSize: 6, letterSpacing: "var(--track-caps)", color: "var(--c-text-4)" }}>FG</span>
            {editingSwatch === "fg" && (
              <div className="absolute top-8 left-0 z-50 compact-picker shadow-xl rounded-lg overflow-hidden">
                <HexColorPicker color={fgCss} onChange={() => {}} style={{ width: 160 }} />
              </div>
            )}
          </div>
        </div>
        <Dot />
      </div>

      {/* ── Center: Working card readout (fixed width, centered) ── */}
      <div className="flex items-center justify-center min-w-0 px-4">
        <div className="max-w-[240px] text-center truncate cursor-pointer">
          {hasSpotlight ? (
            <span className="font-mono truncate" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-2)" }}>
              {workingCard.badge}
              <span style={{ color: "var(--c-text-4)", margin: "0 6px" }}>·</span>
              {workingCard.fontName}
            </span>
          ) : (
            <span className="font-mono italic" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-4)" }}>
              No card selected
            </span>
          )}
        </div>
      </div>

      {/* ── Right-center: Contrast toggle ────────────────── */}
      <div className="flex items-center gap-3">
        <Dot />
        <div className="flex items-center gap-2">
          <div className="flex rounded-md overflow-hidden border border-neutral-700">
            {(["display", "clash", "accessible"] as const).map((level) => {
              const isActive = contrastLevel === level;
              const label = level === "clash" ? "Clash ⚡" : level.charAt(0).toUpperCase() + level.slice(1);
              return (
                <button key={level} className="px-2 py-1 font-medium transition-colors cursor-pointer whitespace-nowrap"
                  style={{ fontSize: "var(--text-badge)", backgroundColor: isActive ? "#404040" : "transparent", color: isActive ? "var(--c-text)" : "var(--c-text-2)" }}
                  onClick={() => onContrastLevelChange(level)}>{label}</button>
              );
            })}
          </div>
          {passRate && (
            <span className="font-mono tabular-nums" style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)" }}>
              {passRate.pass}/{passRate.total}
            </span>
          )}
        </div>
        <Dot />
      </div>

      {/* ── Right: Collection count + Build System CTA ───── */}
      <div className="flex items-center gap-2 shrink-0">
        {collectionCount > 0 && (
          <button
            className="flex items-center gap-1 px-2 py-1 rounded font-mono cursor-pointer transition-colors"
            style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)", backgroundColor: "rgba(255,255,255,0.06)" }}
            onClick={onCollectionClick}
            title="View collection"
          >
            <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" strokeWidth="1" strokeLinecap="round" strokeLinejoin="round">
              <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
            </svg>
            {collectionCount}
          </button>
        )}
      {buildSystemOpen ? (
        <button
          className="px-3 py-1.5 rounded font-semibold shadow-sm flex items-center gap-1.5 shrink-0 transition-colors cursor-pointer"
          style={{ fontSize: "var(--text-body)", backgroundColor: "rgba(255,255,255,0.08)", color: "var(--c-text-2)" }}
          onClick={() => onBackToExplore?.()}
        >
          ← Back to Explore
        </button>
      ) : (
        <button
          className="px-3 py-1.5 rounded font-semibold shadow-sm flex items-center gap-1.5 shrink-0 transition-colors"
          style={{
            fontSize: "var(--text-body)",
            backgroundColor: hasSpotlight ? "#ffffff" : "rgba(255,255,255,0.08)",
            color: hasSpotlight ? "#000000" : "var(--c-text-4)",
            cursor: hasSpotlight ? "pointer" : "not-allowed",
            opacity: hasSpotlight ? 1 : 0.5,
          }}
          onClick={() => hasSpotlight && onBuildSystem?.()}
          disabled={!hasSpotlight}
        >
          Build System →
        </button>
      )}
      </div>
    </div>
  );
}
