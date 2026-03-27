import { useId } from "react";
import { motion } from "framer-motion";
import { springSnap } from "../../../lib/motion";
import type { MethodName } from "../types";

const METHODS: MethodName[] = ["Hue Lock", "Temperature Corridor", "Contrast Safe", "Role Builder", "Extract"];

interface MethodBarProps {
  activeMethod: MethodName;
  onMethodChange: (m: MethodName) => void;
  displayFontCount: number;
  hasStarred: boolean;
  albersExpanded: boolean;
  onToggleAlbers: () => void;
}

export function MethodBar({
  activeMethod,
  onMethodChange,
  displayFontCount,
  hasStarred,
  albersExpanded,
  onToggleAlbers,
}: MethodBarProps) {
  const layoutId = useId();

  return (
    <div className="flex-shrink-0 flex items-center gap-1.5 px-4 h-10 border-b border-neutral-800 bg-neutral-900 overflow-x-auto">
      {METHODS.map((method) => {
        const isActive = method === activeMethod;
        return (
          <button
            key={method}
            className="relative px-2.5 py-1 font-medium cursor-pointer flex-shrink-0 whitespace-nowrap"
            style={{ fontSize: "var(--text-body)", color: isActive ? "var(--c-text)" : "var(--c-text-3)", transition: "color var(--dur-fast) var(--ease-out)" }}
            onMouseEnter={(e) => { if (!isActive) (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text)"; }}
            onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = isActive ? "var(--c-text)" : "var(--c-text-3)"; }}
            onClick={() => onMethodChange(method)}
          >
            {isActive && (
              <motion.div
                className="absolute inset-0 bg-neutral-700 rounded-md"
                layoutId={`method-${layoutId}`}
                initial={false}
                transition={springSnap}
              />
            )}
            <span className="relative">{method}</span>
          </button>
        );
      })}

      <div className="flex-1 min-w-0" />

      {/* Right: font count + Albers toggle */}
      <div className="flex items-center gap-2 flex-shrink-0">
        <span className="font-mono tabular-nums whitespace-nowrap" style={{ fontSize: "var(--text-body)", color: "var(--c-text-4)" }}>
          {displayFontCount} {hasStarred ? "starred" : "fonts"}
        </span>
        <button
          className="flex items-center gap-1.5 font-mono uppercase cursor-pointer"
          style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)", transition: "color var(--dur-fast) var(--ease-hover)" }}
          onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text-2)"; }}
          onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text-3)"; }}
          onClick={onToggleAlbers}
          aria-label={albersExpanded ? "Collapse Albers row" : "Expand Albers row"}
        >
          Albers
          <svg width="10" height="6" viewBox="0 0 10 6" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"
            className="transition-transform" style={{ transform: albersExpanded ? "rotate(180deg)" : "rotate(0deg)" }}>
            <path d="M1 1L5 5L9 1" />
          </svg>
        </button>
      </div>
    </div>
  );
}
