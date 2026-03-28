import type { ReactNode } from "react";

interface MethodSidebarProps {
  children: ReactNode;
  /** Remove top padding so content sits flush against the method bar */
  flush?: boolean;
}

export function MethodSidebar({ children, flush }: MethodSidebarProps) {
  return (
    <div className="w-[280px] bg-surface-1 border-r border-border-default flex flex-col shrink-0 overflow-y-auto z-10">
      <div className={`${flush ? "pt-0 px-4 pb-4" : "p-4"} flex flex-col flex-1`}>
        <div className="px-1 flex flex-col gap-5">{children}</div>
      </div>
    </div>
  );
}

// Slider class that relies on App.css range reset — no inline thumb overrides needed
export const SIDEBAR_SLIDER = "w-full";
