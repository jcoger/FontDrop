import type { ReactNode } from "react";

interface MethodSidebarProps {
  children: ReactNode;
}

export function MethodSidebar({ children }: MethodSidebarProps) {
  return (
    <div className="w-[280px] bg-[#141414] border-r border-neutral-800 flex flex-col shrink-0 overflow-y-auto z-10">
      <div className="p-4 flex flex-col flex-1">
        <div
          className="font-mono uppercase mb-5 px-1"
          style={{ fontSize: "var(--text-label)", letterSpacing: "var(--track-caps)", color: "var(--c-text-3)" }}
        >
          Parameters
        </div>
        <div className="px-1 flex flex-col gap-6">{children}</div>
      </div>
    </div>
  );
}

// Slider class that relies on App.css range reset — no inline thumb overrides needed
export const SIDEBAR_SLIDER = "w-full";
