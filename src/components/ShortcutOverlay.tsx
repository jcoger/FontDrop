import { useEffect } from "react";

interface Shortcut {
  keys: string[];
  description: string;
}

const SHORTCUTS: Shortcut[] = [
  { keys: ["Tab"], description: "Switch between Logo Grid / Type Explorer" },
  { keys: ["S"], description: "Star / unstar hovered font" },
  { keys: ["F"], description: "Focus search" },
  { keys: ["⌘", "E"], description: "Export PNG (Type Explorer starred view)" },
  { keys: ["⌘", "⇧", "C"], description: "Copy Figma prompt" },
  { keys: ["Esc"], description: "Clear search" },
  { keys: ["?"], description: "Show / hide this overlay" },
];

interface Props {
  onClose: () => void;
}

export function ShortcutOverlay({ onClose }: Props) {
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" || e.key === "?") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      onClick={onClose}
    >
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />

      {/* Panel */}
      <div
        className="relative bg-neutral-900 border border-neutral-800 rounded-xl shadow-2xl
                   w-80 p-5"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-sm font-medium text-white">Keyboard shortcuts</h2>
          <button
            className="text-neutral-600 hover:text-neutral-300 transition-colors cursor-pointer"
            onClick={onClose}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>

        <div className="flex flex-col gap-2.5">
          {SHORTCUTS.map((s) => (
            <div key={s.description} className="flex items-center justify-between gap-4">
              <span className="text-xs text-neutral-500">{s.description}</span>
              <div className="flex items-center gap-1 flex-shrink-0">
                {s.keys.map((k) => (
                  <kbd
                    key={k}
                    className="inline-flex items-center justify-center min-w-[22px] h-[22px] px-1.5
                               bg-neutral-800 border border-neutral-700 rounded text-[11px]
                               text-neutral-300 font-mono leading-none"
                  >
                    {k}
                  </kbd>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
