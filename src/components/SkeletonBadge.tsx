import { Menu } from "bloom-menu";
import { invoke } from "@tauri-apps/api/core";
import type { FontDBRow, FontUpdate } from "../hooks/useFontDB";

const SKELETON_COLORS: Record<string, { bg: string; text: string }> = {
  dynamic:   { bg: "rgba(34,197,94,0.15)",  text: "#4ade80" },
  rational:  { bg: "rgba(59,130,246,0.15)", text: "#60a5fa" },
  geometric: { bg: "rgba(168,85,247,0.15)", text: "#c084fc" },
  unknown:   { bg: "rgba(163,163,163,0.15)", text: "#a3a3a3" },
};

const SKELETON_OPTIONS = [
  {
    value: "dynamic",
    label: "Dynamic",
    line1: "Open apertures, diagonal stress",
    line2: "Friendly, warm, approachable",
  },
  {
    value: "rational",
    label: "Rational",
    line1: "Closed apertures, vertical stress",
    line2: "Orderly, serious, reserved",
  },
  {
    value: "geometric",
    label: "Geometric",
    line1: "Constructed shapes, circular forms",
    line2: "Clean, modern, functional",
  },
] as const;

interface Props {
  font: FontDBRow;
  onUpdate: (fontId: string, updates: FontUpdate) => Promise<void>;
  onAfterChange?: () => void;
  onToast?: (msg: string) => void;
  size?: "sm" | "md";
}

export function SkeletonBadge({ font, onUpdate, onAfterChange, onToast, size = "md" }: Props) {
  const colors = SKELETON_COLORS[font.skeleton] ?? SKELETON_COLORS.unknown;
  const isManual = font.user_override === 1;

  const textSize = size === "sm" ? "text-[10px]" : "text-[11px]";
  const px = size === "sm" ? "px-2 py-0.5" : "px-2.5 py-1";
  const btnW = size === "sm" ? 90 : 110;
  const btnH = size === "sm" ? 22 : 28;

  async function handleSelect(skeleton: string) {
    await onUpdate(font.font_id, {
      skeleton,
      classification_source: "manual",
      user_override: 1,
    });
    onAfterChange?.();
    onToast?.(`Reclassified as ${skeleton} — matches updated`);
  }

  async function handleReset() {
    // Remove override, re-run auto classification
    await onUpdate(font.font_id, {
      user_override: 0,
      classification_source: "file",
    });
    // Re-run Tier 1 classifier for this font
    try {
      const result = await invoke<{ skeleton: string }>("classify_single_font", { fontId: font.font_id });
      await onUpdate(font.font_id, {
        skeleton: result.skeleton,
        user_override: 0,
      });
    } catch {
      // fallback — just set to unknown
      await onUpdate(font.font_id, { skeleton: "unknown", user_override: 0 });
    }
    onAfterChange?.();
    onToast?.("Reset to auto classification");
  }

  return (
    <Menu.Root direction="bottom" anchor="start">
      <Menu.Container
        buttonSize={{ width: btnW, height: btnH }}
        menuWidth={260}
        menuRadius={10}
        buttonRadius={999}
        className="bg-surface-1 ring-1 ring-border-strong shadow-2xl"
      >
        <Menu.Trigger>
          <div
            className={`flex items-center gap-1 w-full h-full ${px} rounded-full cursor-pointer transition-opacity hover:opacity-80`}
            style={{ backgroundColor: colors.bg, color: colors.text }}
          >
            <span className={`${textSize} font-medium capitalize leading-none`}>
              {font.skeleton}
            </span>
            {isManual && (
              <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="flex-shrink-0 opacity-60">
                <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
              </svg>
            )}
          </div>
        </Menu.Trigger>
        <Menu.Content className="p-1.5 flex flex-col gap-0.5">
          {SKELETON_OPTIONS.map((opt) => {
            const optColors = SKELETON_COLORS[opt.value];
            const isActive = font.skeleton === opt.value;

            return (
              <Menu.Item
                key={opt.value}
                onSelect={() => handleSelect(opt.value)}
                className={`flex flex-col gap-0.5 px-3 py-2.5 rounded-md cursor-pointer transition-colors ${
                  isActive ? "bg-white/10" : "hover:bg-white/5"
                }`}
              >
                <span className="text-xs font-medium" style={{ color: optColors.text }}>
                  {opt.label}
                </span>
                <span className="text-[11px] text-fg-3 leading-snug">{opt.line1}</span>
                <span className="text-[11px] text-fg-4 leading-snug">{opt.line2}</span>
              </Menu.Item>
            );
          })}

          {isManual && (
            <>
              <div className="h-px bg-border-default my-1" />
              <Menu.Item
                onSelect={handleReset}
                className="flex items-center gap-2 px-3 py-2 rounded-md cursor-pointer hover:bg-white/5 transition-colors"
              >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-fg-4">
                  <polyline points="1 4 1 10 7 10" />
                  <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10" />
                </svg>
                <span className="text-xs text-fg-3">Reset to auto</span>
              </Menu.Item>
            </>
          )}
        </Menu.Content>
      </Menu.Container>
    </Menu.Root>
  );
}
