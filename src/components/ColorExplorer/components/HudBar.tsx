import type { OklchColor } from "../../../utils/oklch";
import { contrastRatio } from "../../../utils/oklch";
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
  onBrandKit?: () => void;
  onBackToExplore?: () => void;
  brandKitOpen?: boolean;
  activeMethod: string;
  collectionCount?: number;
  onCollectionClick?: () => void;
}

// ── Separator ─────────────────────────────────────────────────────────

function Dot() {
  return <div className="w-1 h-1 rounded-full bg-surface-active shrink-0" />;
}

// ── Component ─────────────────────────────────────────────────────────

export function HudBar({
  workingCard,
  cardPairs,
  contrastLevel,
  onContrastLevelChange,
  onBrandKit,
  onBackToExplore,
  brandKitOpen,
  collectionCount = 0,
  onCollectionClick,
}: HudBarProps) {
  // Compute contrast pass rate from per-card bg/fg pairs
  const threshold = contrastLevel === "accessible" ? 4.5 : contrastLevel === "display" ? 3.0 : 1.5;
  const passRate = (() => {
    if (cardPairs.length === 0) return null;
    if (contrastLevel === "clash") return null;
    let pass = 0;
    for (const p of cardPairs) {
      if (contrastRatio(p.bg, p.fg) >= threshold) pass++;
    }
    return { pass, total: cardPairs.length };
  })();

  const hasSpotlight = workingCard !== null;

  return (
    <div className="flex-shrink-0 flex items-center justify-between min-h-[44px] py-1.5 border-b border-border-default bg-surface-1 px-4">

      {/* ── Left: Working card readout ──────────────────────── */}
      <div className="flex items-center min-w-0 flex-1">
        <div className="max-w-[280px] truncate">
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

      {/* ── Center: Contrast toggle ────────────────────────── */}
      <div className="flex items-center gap-3">
        <Dot />
        <div className="flex items-center gap-2">
          <div className="flex rounded-md overflow-hidden border border-border-strong">
            {(["display", "clash", "accessible"] as const).map((level) => {
              const isActive = contrastLevel === level;
              const label = level === "clash" ? "Clash ⚡" : level.charAt(0).toUpperCase() + level.slice(1);
              return (
                <button key={level} className="px-2 py-1 font-medium transition-colors cursor-pointer whitespace-nowrap"
                  style={{ fontSize: "var(--text-badge)", backgroundColor: isActive ? "var(--surface-active)" : "transparent", color: isActive ? "var(--c-text)" : "var(--c-text-2)" }}
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

      {/* ── Right: Collection + Brand Kit ───────────────────── */}
      <div className="flex items-center gap-2 shrink-0">
        {collectionCount > 0 && (
          <button
            className="flex items-center gap-1 px-2 py-1 rounded font-mono cursor-pointer transition-colors"
            style={{ fontSize: "var(--text-badge)", color: "var(--c-text-3)", backgroundColor: "var(--border-subtle)" }}
            onClick={onCollectionClick}
            title="View collection"
          >
            <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" strokeWidth="1" strokeLinecap="round" strokeLinejoin="round">
              <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
            </svg>
            {collectionCount}
          </button>
        )}
        {brandKitOpen ? (
          <button
            className="px-3 py-1.5 rounded font-semibold shadow-sm flex items-center gap-1.5 shrink-0 transition-colors cursor-pointer"
            style={{ fontSize: "var(--text-body)", backgroundColor: "var(--border-subtle)", color: "var(--c-text-2)" }}
            onClick={() => onBackToExplore?.()}
          >
            ← Back to Explore
          </button>
        ) : (() => {
          const canOpen = collectionCount > 0 || hasSpotlight;
          return (
            <button
              className="px-3 py-1.5 rounded font-semibold shadow-sm flex items-center gap-1.5 shrink-0 transition-colors"
              style={{
                fontSize: "var(--text-body)",
                backgroundColor: canOpen ? "var(--c-text)" : "var(--border-subtle)",
                color: canOpen ? "var(--surface-0)" : "var(--c-text-4)",
                cursor: canOpen ? "pointer" : "not-allowed",
                opacity: canOpen ? 1 : 0.5,
              }}
              onClick={() => canOpen && onBrandKit?.()}
              disabled={!canOpen}
            >
              Brand Kit →
            </button>
          );
        })()}
      </div>
    </div>
  );
}
