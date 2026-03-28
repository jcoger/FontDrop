import type { ReactNode } from "react";
import { supportsP3 } from "../../../utils/oklch";

interface BottomBarProps {
  label: string;
  children: ReactNode;
}

export function BottomBar({ label, children }: BottomBarProps) {
  return (
    <div className="h-14 w-full border-t border-neutral-800 bg-[#161616] shrink-0 flex items-center px-6 justify-between relative z-20 shadow-[0_-4px_24px_rgba(0,0,0,0.3)]">
      {/* Left: method label */}
      <div className="w-[260px] flex items-center gap-2.5 shrink-0">
        <div className="w-2 h-2 rounded-full shadow-[0_0_6px_rgba(217,119,54,0.5)]" style={{ backgroundColor: "var(--c-accent)" }} />
        <span
          className="font-mono font-medium uppercase"
          style={{ fontSize: "var(--text-body)", letterSpacing: "var(--track-caps)", color: "var(--c-text)" }}
        >
          {label}
        </span>
      </div>

      {/* Center: method-specific controls */}
      <div className="flex-1 flex justify-center">{children}</div>

      {/* Right: P3 badge when on wide-gamut display */}
      <div className="w-[260px] shrink-0 flex justify-end">
        {supportsP3 && (
          <span
            className="font-mono uppercase"
            style={{ fontSize: "var(--text-micro)", letterSpacing: "var(--track-caps)", color: "var(--c-text-4)" }}
          >
            Display P3
          </span>
        )}
      </div>
    </div>
  );
}
