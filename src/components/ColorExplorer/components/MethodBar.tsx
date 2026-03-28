import { useId } from "react";
import { motion } from "framer-motion";
import { springSnap } from "../../../lib/motion";
import type { MethodName } from "../types";

const VISIBLE_METHODS: MethodName[] = ["Hue Lock", "Temperature Corridor", "Word Picker", "Macro Knob", "Extract"];

interface MethodBarProps {
  activeMethod: MethodName;
  onMethodChange: (m: MethodName) => void;
  albersOpen: boolean;
  onToggleAlbers: () => void;
}

export function MethodBar({
  activeMethod,
  onMethodChange,
  albersOpen,
  onToggleAlbers,
}: MethodBarProps) {
  const layoutId = useId();

  return (
    <div className="flex-shrink-0 flex items-center gap-1.5 px-4 h-10 border-b border-neutral-800 bg-neutral-900 overflow-x-auto">
      {VISIBLE_METHODS.map((method) => {
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

      {/* Albers toggle */}
      <button
        className="flex items-center gap-1.5 font-mono uppercase cursor-pointer flex-shrink-0"
        style={{
          fontSize: "var(--text-label)",
          letterSpacing: "var(--track-caps)",
          color: albersOpen ? "var(--c-text-2)" : "var(--c-text-3)",
          transition: "color var(--dur-fast) var(--ease-hover)",
        }}
        onMouseEnter={(e) => { (e.currentTarget as HTMLButtonElement).style.color = "var(--c-text-2)"; }}
        onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.color = albersOpen ? "var(--c-text-2)" : "var(--c-text-3)"; }}
        onClick={onToggleAlbers}
        aria-label={albersOpen ? "Close Albers panel" : "Open Albers panel"}
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <rect x="3" y="3" width="18" height="18" rx="2" />
          <path d="M15 3v18" />
        </svg>
        Albers
      </button>
    </div>
  );
}
